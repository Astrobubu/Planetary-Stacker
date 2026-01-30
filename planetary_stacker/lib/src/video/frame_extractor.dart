import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Video metadata information
class VideoInfo {
  final int width;
  final int height;
  final int frameCount;
  final int durationMs;
  final double frameRate;

  const VideoInfo({
    required this.width,
    required this.height,
    required this.frameCount,
    required this.durationMs,
    required this.frameRate,
  });

  @override
  String toString() =>
      'VideoInfo(${width}x$height, $frameCount frames, ${frameRate.toStringAsFixed(1)} fps)';
}

/// Progress callback type
typedef ProgressCallback = void Function(int progress, String message);

/// Extracts frames from video files using FFmpeg
class FrameExtractor {
  /// Get video metadata
  Future<VideoInfo> getVideoInfo(String videoPath) async {
    final session = await FFprobeKit.getMediaInformation(videoPath);
    final info = session.getMediaInformation();

    if (info == null) {
      throw Exception('Failed to read video info from: $videoPath');
    }

    final streams = info.getStreams();
    final videoStream = streams.firstWhere(
      (s) => s.getType() == 'video',
      orElse: () => throw Exception('No video stream found'),
    );

    final widthStr = videoStream.getWidth()?.toString() ?? '0';
    final heightStr = videoStream.getHeight()?.toString() ?? '0';
    final width = int.tryParse(widthStr) ?? 0;
    final height = int.tryParse(heightStr) ?? 0;

    final durationStr = info.getDuration() ?? '0';
    final duration = double.tryParse(durationStr) ?? 0.0;

    // Parse frame rate (e.g., "30/1" or "29.97")
    final frameRateStr = videoStream.getAverageFrameRate() ?? '30/1';
    double frameRate;
    if (frameRateStr.contains('/')) {
      final parts = frameRateStr.split('/');
      final num = double.tryParse(parts[0]) ?? 30.0;
      final den = double.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1.0;
      frameRate = den > 0 ? num / den : 30.0;
    } else {
      frameRate = double.tryParse(frameRateStr) ?? 30.0;
    }

    final frameCount = (duration * frameRate).round();

    return VideoInfo(
      width: width,
      height: height,
      frameCount: frameCount,
      durationMs: (duration * 1000).round(),
      frameRate: frameRate,
    );
  }

  /// Get temporary directory for frame extraction
  Future<Directory> _getFramesDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final framesDir = Directory(p.join(tempDir.path, 'planetary_frames'));

    // Clean up any previous extraction
    if (await framesDir.exists()) {
      await framesDir.delete(recursive: true);
    }
    await framesDir.create(recursive: true);

    return framesDir;
  }

  /// Extract all frames from video at regular intervals for quality analysis
  ///
  /// [videoPath]: Path to the video file
  /// [sampleStep]: Extract every Nth frame (1 = all frames, 3 = every 3rd frame)
  /// [onProgress]: Optional progress callback
  ///
  /// Returns list of paths to extracted PNG frames
  Future<List<String>> extractFramesForAnalysis({
    required String videoPath,
    int sampleStep = 3,
    ProgressCallback? onProgress,
  }) async {
    final info = await getVideoInfo(videoPath);
    final framesDir = await _getFramesDirectory();

    onProgress?.call(0, 'Starting frame extraction...');

    // Calculate how many frames we'll extract
    final framesToExtract = (info.frameCount / sampleStep).ceil();

    // Use FFmpeg to extract frames
    // -vf select='not(mod(n,$sampleStep))' selects every Nth frame
    // Using frame rate filter to control extraction
    final outputPattern = p.join(framesDir.path, 'frame_%06d.png');

    // Build FFmpeg command
    // Extract every Nth frame using the select filter
    final command = '-y -i "$videoPath" '
        '-vf "select=not(mod(n\\,$sampleStep))" '
        '-vsync vfr '
        '-pix_fmt rgb24 '
        '"$outputPattern"';

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      throw Exception('Frame extraction failed: $logs');
    }

    onProgress?.call(80, 'Collecting extracted frames...');

    // List the extracted frames
    final extractedFiles = await framesDir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.png'))
        .map((entity) => entity.path)
        .toList();

    extractedFiles.sort(); // Ensure consistent ordering

    // Create a mapping of extracted file names to original frame indices
    final result = <String>[];
    for (int i = 0; i < extractedFiles.length; i++) {
      result.add(extractedFiles[i]);
    }

    onProgress?.call(100, 'Extracted ${result.length} frames');

    return result;
  }

  /// Extract specific frames by their indices
  ///
  /// [videoPath]: Path to the video file
  /// [frameIndices]: List of frame indices to extract
  /// [onProgress]: Optional progress callback
  ///
  /// Returns list of paths to extracted PNG frames
  Future<List<String>> extractFrames({
    required String videoPath,
    required List<int> frameIndices,
    ProgressCallback? onProgress,
  }) async {
    if (frameIndices.isEmpty) {
      return [];
    }

    final info = await getVideoInfo(videoPath);
    final framesDir = await _getFramesDirectory();
    final extractedPaths = <String>[];

    for (int i = 0; i < frameIndices.length; i++) {
      final frameIndex = frameIndices[i];
      final outputPath = p.join(framesDir.path, 'frame_${frameIndex.toString().padLeft(6, '0')}.png');

      // Calculate timestamp for this frame
      final timestamp = frameIndex / info.frameRate;

      // FFmpeg command to extract single frame at specific time
      // Using -ss before -i for fast seeking
      final command = '-y '
          '-ss ${timestamp.toStringAsFixed(6)} '
          '-i "$videoPath" '
          '-vframes 1 '
          '-pix_fmt rgb24 '
          '"$outputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode) && await File(outputPath).exists()) {
        extractedPaths.add(outputPath);
      }

      onProgress?.call(
        ((i + 1) * 100 / frameIndices.length).round(),
        'Extracting frame ${i + 1}/${frameIndices.length}',
      );
    }

    return extractedPaths;
  }

  /// Clean up extracted frames
  Future<void> cleanup() async {
    final tempDir = await getTemporaryDirectory();
    final framesDir = Directory(p.join(tempDir.path, 'planetary_frames'));

    if (await framesDir.exists()) {
      await framesDir.delete(recursive: true);
    }
  }
}
