import 'dart:async';
import 'dart:io';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';

import 'frame_analysis.dart';
import 'processing_params.dart';
import 'video/frame_extractor.dart';
import 'quality/quality_assessor.dart';
import 'alignment/phase_correlator.dart';
import 'stacking/sigma_clip_stacker.dart';
import 'sharpening/wavelet_sharpener.dart';

/// Progress callback typedef
typedef ProgressCallback = void Function(int progress, String message);

/// Main planetary stacker class
///
/// Orchestrates the full stacking pipeline:
/// 1. Extract frames from video
/// 2. Analyze frame quality (Laplacian variance)
/// 3. Select best frames
/// 4. Align frames (phase correlation)
/// 5. Stack frames (sigma clipping)
/// 6. Sharpen result (wavelet sharpening)
/// 7. Save output
class PlanetaryStacker {
  final FrameExtractor _frameExtractor = FrameExtractor();
  final QualityAssessor _qualityAssessor = QualityAssessor();
  final PhaseCorrelator _phaseCorrelator = PhaseCorrelator();
  final SigmaClipStacker _sigmaClipStacker = SigmaClipStacker();
  final WaveletSharpener _waveletSharpener = WaveletSharpener();

  /// Analyze video frames for quality
  ///
  /// Returns an [AnalysisResult] containing quality scores for all analyzed frames.
  ///
  /// [videoPath]: Path to the input video file (MP4/MOV)
  /// [sampleStep]: Analyze every Nth frame (default: 3)
  /// [onProgress]: Optional progress callback
  Future<AnalysisResult> analyzeVideo({
    required String videoPath,
    int sampleStep = 3,
    ProgressCallback? onProgress,
  }) async {
    onProgress?.call(0, 'Getting video info...');

    // Get video metadata
    final videoInfo = await _frameExtractor.getVideoInfo(videoPath);

    onProgress?.call(5, 'Extracting frames for analysis...');

    // Extract frames for analysis
    final framePaths = await _frameExtractor.extractFramesForAnalysis(
      videoPath: videoPath,
      sampleStep: sampleStep,
      onProgress: (p, m) => onProgress?.call(5 + (p * 0.4).round(), m),
    );

    onProgress?.call(45, 'Analyzing frame quality...');

    // Analyze frame quality
    final qualityScores = await _qualityAssessor.analyzeFrames(
      framePaths: framePaths,
      onProgress: (p, m) => onProgress?.call(45 + (p * 0.5).round(), m),
    );

    // Convert to FrameScore objects
    final scores = qualityScores.map((qs) => FrameScore(
      frameIndex: qs.frameIndex,
      qualityScore: qs.normalizedScore,
      roi: Rectangle(x: 0, y: 0, width: videoInfo.width, height: videoInfo.height),
    )).toList();

    onProgress?.call(100, 'Analysis complete');

    return AnalysisResult(
      scores: scores,
      totalFrames: videoInfo.frameCount,
    );
  }

  /// Process planetary video end-to-end
  ///
  /// Performs frame analysis, selection, alignment, stacking, and sharpening.
  ///
  /// [videoPath]: Path to the input video file
  /// [outputPath]: Path for the output stacked image
  /// [params]: Processing parameters
  /// [onProgress]: Optional progress callback
  ///
  /// Returns the output path on success, null on failure
  Future<String?> processVideo({
    required String videoPath,
    required String outputPath,
    ProcessingParams params = const ProcessingParams(),
    ProgressCallback? onProgress,
  }) async {
    try {
      // Stage 1: Analyze frames (0-15%)
      onProgress?.call(0, 'Analyzing video...');
      final analysis = await analyzeVideo(
        videoPath: videoPath,
        sampleStep: 2,
        onProgress: (p, m) => onProgress?.call((p * 0.15).round(), m),
      );

      if (analysis.scores.isEmpty) {
        throw Exception('No frames could be analyzed');
      }

      // Stage 2: Select best frames (15-20%)
      onProgress?.call(15, 'Selecting best frames...');
      final framesToUse = analysis.getTopFrames(params.keepPercentage);
      final frameCount = framesToUse.length.clamp(params.minFrames, params.maxFrames);
      final selectedFrames = framesToUse.take(frameCount).toList();

      onProgress?.call(20, 'Selected ${selectedFrames.length} frames');

      // Stage 3: Extract selected frames (20-35%)
      onProgress?.call(20, 'Extracting selected frames...');
      final frameIndices = selectedFrames.map((f) => f.frameIndex).toList();
      final framePaths = await _frameExtractor.extractFrames(
        videoPath: videoPath,
        frameIndices: frameIndices,
        onProgress: (p, m) => onProgress?.call(20 + (p * 0.15).round(), m),
      );

      if (framePaths.isEmpty) {
        throw Exception('No frames could be extracted');
      }

      // Stage 4: Load and align frames (35-55%)
      onProgress?.call(35, 'Aligning frames...');
      final alignedFrames = await _phaseCorrelator.alignFramesFromPaths(
        framePaths: framePaths,
        referenceIndex: 0, // Use best quality frame as reference
        onProgress: (p, m) => onProgress?.call(35 + (p * 0.2).round(), m),
      );

      if (alignedFrames.isEmpty) {
        throw Exception('Frame alignment failed');
      }

      // Stage 5: Stack frames (55-75%)
      onProgress?.call(55, 'Stacking frames...');
      final stacked = await _sigmaClipStacker.stackFrames(
        alignedFrames: alignedFrames,
        sigmaThreshold: params.sigmaClipThreshold,
        iterations: params.sigmaIterations,
        onProgress: (p, m) => onProgress?.call(55 + (p * 0.2).round(), m),
      );

      // Dispose aligned frames (no longer needed)
      for (final frame in alignedFrames) {
        frame.dispose();
      }

      // Stage 6: Wavelet sharpening (75-90%)
      onProgress?.call(75, 'Applying wavelet sharpening...');
      final layerStrengths = [
        params.waveletLayers.layer0,
        params.waveletLayers.layer1,
        params.waveletLayers.layer2,
        params.waveletLayers.layer3,
        params.waveletLayers.layer4,
      ];

      final sharpened = await _waveletSharpener.sharpen(
        image: stacked,
        layerStrengths: layerStrengths,
        onProgress: (p, m) => onProgress?.call(75 + (p * 0.15).round(), m),
      );

      stacked.dispose();

      // Stage 7: Save output (90-100%)
      onProgress?.call(90, 'Saving output...');

      // Ensure output directory exists
      final outputFile = File(outputPath);
      final outputDir = outputFile.parent;
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // Save as PNG
      cv.imwrite(outputPath, sharpened);

      sharpened.dispose();

      // Cleanup temporary frames
      await _frameExtractor.cleanup();

      onProgress?.call(100, 'Complete!');

      return outputPath;
    } catch (e) {
      onProgress?.call(-1, 'Error: $e');
      // Cleanup on error
      try {
        await _frameExtractor.cleanup();
      } catch (_) {}
      return null;
    }
  }

  /// Quick process with sensible defaults
  ///
  /// Uses automatic preset selection based on common planetary targets.
  Future<String?> quickProcess({
    required String videoPath,
    required String outputPath,
    ProgressCallback? onProgress,
  }) async {
    return processVideo(
      videoPath: videoPath,
      outputPath: outputPath,
      params: const ProcessingParams(), // Use defaults
      onProgress: onProgress,
    );
  }

  /// Get default output path in the Downloads folder
  Future<String> getDefaultOutputPath() async {
    // Try to use Downloads folder on Android
    final directory = await getExternalStorageDirectory();
    final downloadsPath = directory?.path ?? '/storage/emulated/0/Download';

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '$downloadsPath/stacked_$timestamp.png';
  }

  /// Get the library version
  String get version => '0.2.0';
}
