import 'dart:async';
import 'package:planetary_stacker/src/frame_analysis.dart';
import 'package:planetary_stacker/src/processing_params.dart';

/// Progress callback typedef
typedef ProgressCallback = void Function(int progress, String message);

/// Main planetary stacker class
class PlanetaryStacker {
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
    // TODO: Call native FFI function
    // For now, return stub data
    onProgress?.call(0, 'Starting analysis...');

    await Future.delayed(const Duration(milliseconds: 500));
    onProgress?.call(50, 'Analyzing frames...');

    await Future.delayed(const Duration(milliseconds: 500));
    onProgress?.call(100, 'Analysis complete');

    // Stub data
    final scores = List.generate(
      100,
      (i) => FrameScore(
        frameIndex: i * sampleStep,
        qualityScore: 0.5 + (i * 0.005),
        roi: const Rectangle(x: 100, y: 100, width: 800, height: 600),
      ),
    );

    return AnalysisResult(scores: scores, totalFrames: 1000);
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
  /// Returns `true` on success, `false` on failure
  Future<bool> processVideo({
    required String videoPath,
    required String outputPath,
    ProcessingParams params = const ProcessingParams(),
    ProgressCallback? onProgress,
  }) async {
    try {
      // TODO: Call native FFI function
      // For now, simulate processing

      onProgress?.call(0, 'Analyzing frames...');
      await Future.delayed(const Duration(milliseconds: 200));

      onProgress?.call(20, 'Selecting best frames...');
      await Future.delayed(const Duration(milliseconds: 200));

      onProgress?.call(40, 'Aligning frames globally...');
      await Future.delayed(const Duration(milliseconds: 200));

      if (params.enableLocalAlign) {
        onProgress?.call(60, 'Aligning frames locally...');
        await Future.delayed(const Duration(milliseconds: 200));
      }

      onProgress?.call(75, 'Stacking frames...');
      await Future.delayed(const Duration(milliseconds: 200));

      onProgress?.call(90, 'Sharpening with wavelets...');
      await Future.delayed(const Duration(milliseconds: 200));

      onProgress?.call(100, 'Complete!');

      return true;
    } catch (e) {
      onProgress?.call(-1, 'Error: $e');
      return false;
    }
  }

  /// Get the library version
  String get version => '0.1.0';
}
