import 'dart:math' as math;
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Progress callback type
typedef ProgressCallback = void Function(int progress, String message);

/// Wavelet decomposition result
class WaveletDecomposition {
  /// Detail layers (finest to coarsest)
  final List<cv.Mat> detailLayers;

  /// Residual (smoothest approximation)
  final cv.Mat residual;

  WaveletDecomposition({
    required this.detailLayers,
    required this.residual,
  });

  /// Dispose all matrices
  void dispose() {
    for (final layer in detailLayers) {
      layer.dispose();
    }
    residual.dispose();
  }
}

/// Applies wavelet-based sharpening using the à trous algorithm
///
/// The à trous ("with holes") algorithm performs multi-scale wavelet decomposition
/// using a B3-spline kernel. Each level captures different spatial frequencies,
/// allowing precise control over sharpening at different scales.
class WaveletSharpener {
  /// Number of wavelet detail layers (like Registax)
  static const int numLayers = 5;

  /// B3-spline kernel coefficients: (1/16, 4/16, 6/16, 4/16, 1/16)
  static const List<double> b3Kernel = [
    1.0 / 16.0,
    4.0 / 16.0,
    6.0 / 16.0,
    4.0 / 16.0,
    1.0 / 16.0,
  ];

  /// Apply wavelet sharpening with adjustable layer strengths
  Future<cv.Mat> sharpen({
    required cv.Mat image,
    required List<double> layerStrengths,
    ProgressCallback? onProgress,
  }) async {
    if (layerStrengths.length < numLayers) {
      throw ArgumentError('Must provide at least $numLayers layer strengths');
    }

    onProgress?.call(0, 'Starting wavelet sharpening...');

    // Process each channel separately for color images
    if (image.channels == 3) {
      return _sharpenColor(image, layerStrengths, onProgress);
    } else {
      return _sharpenGrayscale(image, layerStrengths, onProgress);
    }
  }

  /// Sharpen a grayscale image
  Future<cv.Mat> _sharpenGrayscale(
    cv.Mat image,
    List<double> layerStrengths,
    ProgressCallback? onProgress,
  ) async {
    // Convert to float for processing
    final floatImage = image.convertTo(cv.MatType.CV_64FC1);

    onProgress?.call(10, 'Decomposing into wavelet layers...');

    // Decompose into wavelet layers
    final decomposition = await _decompose(floatImage);

    onProgress?.call(50, 'Applying layer strengths...');

    // Apply layer strengths to detail layers
    final modifiedLayers = <cv.Mat>[];
    for (int i = 0; i < numLayers; i++) {
      final strength = layerStrengths[i];
      if ((strength - 1.0).abs() < 0.001) {
        modifiedLayers.add(decomposition.detailLayers[i].clone());
      } else {
        final modified = _multiplyScalar(decomposition.detailLayers[i], strength);
        modifiedLayers.add(modified);
      }
    }

    onProgress?.call(70, 'Reconstructing image...');

    // Reconstruct image from modified layers
    final reconstructed = await _reconstruct(
      WaveletDecomposition(
        detailLayers: modifiedLayers,
        residual: decomposition.residual,
      ),
    );

    // Convert back to 8-bit and clamp values
    final result = _convertTo8Bit(reconstructed);

    // Cleanup
    floatImage.dispose();
    decomposition.dispose();
    for (final layer in modifiedLayers) {
      layer.dispose();
    }
    reconstructed.dispose();

    onProgress?.call(100, 'Wavelet sharpening complete');

    return result;
  }

  /// Sharpen a color image (process each channel separately)
  Future<cv.Mat> _sharpenColor(
    cv.Mat image,
    List<double> layerStrengths,
    ProgressCallback? onProgress,
  ) async {
    // Split into channels
    final channels = cv.split(image);

    final sharpenedChannels = <cv.Mat>[];
    for (int c = 0; c < channels.length; c++) {
      onProgress?.call(
        (c * 33).round(),
        'Processing channel ${c + 1}/${channels.length}...',
      );

      final sharpened = await _sharpenGrayscale(channels[c], layerStrengths, null);
      sharpenedChannels.add(sharpened);
    }

    // Merge channels back using VecMat
    final vecMat = cv.VecMat.fromList(sharpenedChannels);
    final result = cv.merge(vecMat);

    // Cleanup
    for (final ch in channels) {
      ch.dispose();
    }
    for (final ch in sharpenedChannels) {
      ch.dispose();
    }

    onProgress?.call(100, 'Color wavelet sharpening complete');

    return result;
  }

  /// Decompose image into wavelet layers using à trous algorithm
  Future<WaveletDecomposition> _decompose(cv.Mat image) async {
    final detailLayers = <cv.Mat>[];
    var current = image.clone();

    for (int level = 0; level < numLayers; level++) {
      // Create à trous kernel for this level
      final kernel = _createATrousKernel(level);

      // Apply convolution
      final smoothed = cv.filter2D(current, cv.MatType.CV_64F, kernel);

      // Detail layer = current - smoothed
      final detail = cv.subtract(current, smoothed);
      detailLayers.add(detail);

      // Prepare for next level
      current.dispose();
      current = smoothed;
      kernel.dispose();
    }

    return WaveletDecomposition(
      detailLayers: detailLayers,
      residual: current,
    );
  }

  /// Create à trous kernel for given level
  cv.Mat _createATrousKernel(int level) {
    final spacing = math.pow(2, level).toInt();
    final kernelSize = 4 * spacing + 1;

    final kernel = cv.Mat.zeros(kernelSize, kernelSize, cv.MatType.CV_64FC1);

    for (int i = 0; i < b3Kernel.length; i++) {
      for (int j = 0; j < b3Kernel.length; j++) {
        final row = i * spacing;
        final col = j * spacing;
        if (row < kernelSize && col < kernelSize) {
          kernel.set<double>(row, col, b3Kernel[i] * b3Kernel[j]);
        }
      }
    }

    return kernel;
  }

  /// Reconstruct image from wavelet decomposition
  Future<cv.Mat> _reconstruct(WaveletDecomposition decomposition) async {
    var result = decomposition.residual.clone();

    for (int i = numLayers - 1; i >= 0; i--) {
      final added = cv.add(result, decomposition.detailLayers[i]);
      result.dispose();
      result = added;
    }

    return result;
  }

  /// Multiply a matrix by a scalar
  cv.Mat _multiplyScalar(cv.Mat mat, double scalar) {
    // Use Mat arithmetic
    final result = mat.clone();
    for (int y = 0; y < mat.rows; y++) {
      for (int x = 0; x < mat.cols; x++) {
        final value = mat.at<double>(y, x) * scalar;
        result.set<double>(y, x, value);
      }
    }
    return result;
  }

  /// Convert float matrix to 8-bit with clamping
  cv.Mat _convertTo8Bit(cv.Mat floatMat) {
    final result = cv.Mat.zeros(floatMat.rows, floatMat.cols, cv.MatType.CV_8UC1);

    for (int y = 0; y < floatMat.rows; y++) {
      for (int x = 0; x < floatMat.cols; x++) {
        final value = floatMat.at<double>(y, x);
        result.set<int>(y, x, value.round().clamp(0, 255));
      }
    }

    return result;
  }

  /// Get recommended layer strengths for different targets
  static List<double> getPreset(WaveletPreset preset) {
    switch (preset) {
      case WaveletPreset.aggressive:
        return [0.6, 2.0, 2.5, 2.2, 1.5];
      case WaveletPreset.moderate:
        return [0.8, 1.5, 2.0, 1.8, 1.2];
      case WaveletPreset.conservative:
        return [0.5, 1.2, 1.5, 1.3, 1.0];
      case WaveletPreset.solar:
        return [0.7, 1.8, 2.2, 1.5, 1.0];
      case WaveletPreset.lunar:
        return [0.6, 1.3, 1.8, 1.5, 1.2];
      case WaveletPreset.none:
        return [1.0, 1.0, 1.0, 1.0, 1.0];
    }
  }
}

/// Wavelet sharpening presets
enum WaveletPreset {
  aggressive,
  moderate,
  conservative,
  solar,
  lunar,
  none,
}
