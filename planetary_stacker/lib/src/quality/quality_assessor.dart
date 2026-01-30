import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Progress callback type
typedef ProgressCallback = void Function(int progress, String message);

/// Frame quality score with metadata
class FrameQualityScore {
  /// Path to the frame image file
  final String framePath;

  /// Original frame index in the video
  final int frameIndex;

  /// Raw Laplacian variance value
  final double rawVariance;

  /// Normalized quality score (0.0 to 1.0)
  final double normalizedScore;

  const FrameQualityScore({
    required this.framePath,
    required this.frameIndex,
    required this.rawVariance,
    required this.normalizedScore,
  });

  @override
  String toString() =>
      'FrameQualityScore(frame: $frameIndex, raw: ${rawVariance.toStringAsFixed(1)}, score: ${normalizedScore.toStringAsFixed(3)})';
}

/// Assesses frame quality using Laplacian variance (sharpness metric)
///
/// Higher variance = sharper image = better quality for stacking
class QualityAssessor {
  /// Calculate Laplacian variance (sharpness metric) for an image
  ///
  /// The Laplacian operator detects edges, and the variance of the Laplacian
  /// response indicates how sharp/detailed the image is. Higher values mean
  /// more detail/sharpness.
  Future<double> calculateLaplacianVariance(String imagePath) async {
    // Read image
    final img = cv.imread(imagePath, flags: cv.IMREAD_COLOR);
    if (img.isEmpty) {
      throw Exception('Failed to load image: $imagePath');
    }

    try {
      // Convert to grayscale for analysis
      final gray = cv.cvtColor(img, cv.COLOR_BGR2GRAY);

      // Apply Laplacian operator
      // CV_64F (6) gives double precision for accurate variance calculation
      final laplacian = cv.laplacian(gray, cv.MatType.CV_64F);

      // Calculate mean and standard deviation
      final (mean, stdDev) = cv.meanStdDev(laplacian);

      // Variance = stdDev^2
      // stdDev is a Scalar, get the first channel value
      final variance = stdDev.val1 * stdDev.val1;

      // Cleanup
      gray.dispose();
      laplacian.dispose();

      return variance;
    } finally {
      img.dispose();
    }
  }

  /// Analyze multiple frames and return sorted quality scores
  ///
  /// [framePaths]: List of paths to frame images
  /// [onProgress]: Optional progress callback
  ///
  /// Returns list of FrameQualityScore objects sorted by quality (best first)
  Future<List<FrameQualityScore>> analyzeFrames({
    required List<String> framePaths,
    ProgressCallback? onProgress,
  }) async {
    if (framePaths.isEmpty) {
      return [];
    }

    final scores = <FrameQualityScore>[];
    final variances = <double>[];

    // First pass: calculate all variances
    for (int i = 0; i < framePaths.length; i++) {
      try {
        final variance = await calculateLaplacianVariance(framePaths[i]);
        variances.add(variance);
        scores.add(FrameQualityScore(
          framePath: framePaths[i],
          frameIndex: _extractFrameIndex(framePaths[i]),
          rawVariance: variance,
          normalizedScore: 0.0, // Will be normalized later
        ));
      } catch (e) {
        // Skip frames that fail to load
        continue;
      }

      onProgress?.call(
        ((i + 1) * 100 / framePaths.length).round(),
        'Analyzing frame ${i + 1}/${framePaths.length}',
      );
    }

    if (scores.isEmpty) {
      return [];
    }

    // Find min and max for normalization
    final minVariance = variances.reduce(math.min);
    final maxVariance = variances.reduce(math.max);
    final range = maxVariance - minVariance;

    // Normalize scores to 0-1 range
    final normalizedScores = <FrameQualityScore>[];
    for (final score in scores) {
      final normalizedScore = range > 0
          ? (score.rawVariance - minVariance) / range
          : 1.0;

      normalizedScores.add(FrameQualityScore(
        framePath: score.framePath,
        frameIndex: score.frameIndex,
        rawVariance: score.rawVariance,
        normalizedScore: normalizedScore,
      ));
    }

    // Sort by quality (best first = highest score first)
    normalizedScores.sort((a, b) => b.normalizedScore.compareTo(a.normalizedScore));

    return normalizedScores;
  }

  /// Extract frame index from filename
  ///
  /// Expects filenames like "frame_000123.png" or "frame_123.png"
  int _extractFrameIndex(String path) {
    final filename = path.split('/').last.split('\\').last;
    final match = RegExp(r'frame_0*(\d+)\.png').firstMatch(filename);
    return match != null ? int.parse(match.group(1)!) : 0;
  }
}
