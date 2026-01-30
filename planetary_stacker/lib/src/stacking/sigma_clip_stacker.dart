import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Progress callback type
typedef ProgressCallback = void Function(int progress, String message);

/// Stacks aligned frames using sigma-clipped averaging
///
/// Sigma clipping rejects outlier pixels (cosmic rays, hot pixels, atmospheric
/// spikes) by excluding values that deviate too far from the mean.
class SigmaClipStacker {
  /// Stack frames using sigma-clipped averaging
  ///
  /// [alignedFrames]: List of aligned frames to stack (must all be same size)
  /// [sigmaThreshold]: Reject pixels beyond this many standard deviations (default: 2.5)
  /// [iterations]: Number of clipping iterations (default: 2)
  /// [onProgress]: Optional progress callback
  ///
  /// Returns the stacked image
  Future<cv.Mat> stackFrames({
    required List<cv.Mat> alignedFrames,
    double sigmaThreshold = 2.5,
    int iterations = 2,
    ProgressCallback? onProgress,
  }) async {
    if (alignedFrames.isEmpty) {
      throw ArgumentError('No frames to stack');
    }

    final height = alignedFrames[0].rows;
    final width = alignedFrames[0].cols;
    final channels = alignedFrames[0].channels;

    // Validate all frames have same dimensions
    for (final frame in alignedFrames) {
      if (frame.rows != height || frame.cols != width || frame.channels != channels) {
        throw ArgumentError('All frames must have the same dimensions');
      }
    }

    // Create output matrix
    final cv.Mat result;
    if (channels == 1) {
      result = cv.Mat.zeros(height, width, cv.MatType.CV_8UC1);
    } else {
      result = cv.Mat.zeros(height, width, cv.MatType.CV_8UC3);
    }

    // Process each pixel position
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (channels == 1) {
          // Grayscale
          final values = <double>[];
          for (final frame in alignedFrames) {
            values.add(frame.at<num>(y, x).toDouble());
          }
          final clippedMean = _sigmaClippedMean(values, sigmaThreshold, iterations);
          result.set<int>(y, x, clippedMean.round().clamp(0, 255));
        } else {
          // Color (BGR) - process each channel
          final valuesB = <double>[];
          final valuesG = <double>[];
          final valuesR = <double>[];

          for (final frame in alignedFrames) {
            final vec = frame.at<cv.Vec3b>(y, x);
            valuesB.add(vec.val1.toDouble());
            valuesG.add(vec.val2.toDouble());
            valuesR.add(vec.val3.toDouble());
          }

          final meanB = _sigmaClippedMean(valuesB, sigmaThreshold, iterations);
          final meanG = _sigmaClippedMean(valuesG, sigmaThreshold, iterations);
          final meanR = _sigmaClippedMean(valuesR, sigmaThreshold, iterations);

          result.set<cv.Vec3b>(y, x, cv.Vec3b(
            meanB.round().clamp(0, 255),
            meanG.round().clamp(0, 255),
            meanR.round().clamp(0, 255),
          ));
        }
      }

      if (y % 50 == 0 || y == height - 1) {
        onProgress?.call(
          ((y + 1) * 100 / height).round(),
          'Stacking row ${y + 1}/$height',
        );
      }
    }

    return result;
  }

  /// Calculate sigma-clipped mean of values
  double _sigmaClippedMean(
    List<double> values,
    double sigmaThreshold,
    int iterations,
  ) {
    if (values.isEmpty) return 0.0;
    if (values.length == 1) return values[0];

    var clippedValues = List<double>.from(values);

    for (int iter = 0; iter < iterations; iter++) {
      if (clippedValues.length <= 2) break;

      final mean = _mean(clippedValues);
      final stdDev = _stdDev(clippedValues, mean);

      if (stdDev < 0.001) break;

      final lowerBound = mean - sigmaThreshold * stdDev;
      final upperBound = mean + sigmaThreshold * stdDev;

      clippedValues = clippedValues
          .where((v) => v >= lowerBound && v <= upperBound)
          .toList();

      if (clippedValues.isEmpty) {
        return _mean(values);
      }
    }

    return _mean(clippedValues);
  }

  double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double _stdDev(List<double> values, double mean) {
    if (values.length < 2) return 0.0;
    final variance = values
        .map((v) => (v - mean) * (v - mean))
        .reduce((a, b) => a + b) / values.length;
    return math.sqrt(variance);
  }

  /// Simple average stacking (no outlier rejection)
  Future<cv.Mat> stackFramesSimple({
    required List<cv.Mat> alignedFrames,
    ProgressCallback? onProgress,
  }) async {
    if (alignedFrames.isEmpty) {
      throw ArgumentError('No frames to stack');
    }

    final height = alignedFrames[0].rows;
    final width = alignedFrames[0].cols;
    final channels = alignedFrames[0].channels;
    final numFrames = alignedFrames.length;

    // Create output matrix
    final cv.Mat result;
    if (channels == 1) {
      result = cv.Mat.zeros(height, width, cv.MatType.CV_8UC1);
    } else {
      result = cv.Mat.zeros(height, width, cv.MatType.CV_8UC3);
    }

    // Process each pixel
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (channels == 1) {
          double sum = 0;
          for (final frame in alignedFrames) {
            sum += frame.at<num>(y, x).toDouble();
          }
          result.set<int>(y, x, (sum / numFrames).round().clamp(0, 255));
        } else {
          double sumB = 0, sumG = 0, sumR = 0;
          for (final frame in alignedFrames) {
            final vec = frame.at<cv.Vec3b>(y, x);
            sumB += vec.val1;
            sumG += vec.val2;
            sumR += vec.val3;
          }
          result.set<cv.Vec3b>(y, x, cv.Vec3b(
            (sumB / numFrames).round().clamp(0, 255),
            (sumG / numFrames).round().clamp(0, 255),
            (sumR / numFrames).round().clamp(0, 255),
          ));
        }
      }

      if (y % 50 == 0 || y == height - 1) {
        onProgress?.call(
          ((y + 1) * 100 / height).round(),
          'Stacking row ${y + 1}/$height',
        );
      }
    }

    return result;
  }
}
