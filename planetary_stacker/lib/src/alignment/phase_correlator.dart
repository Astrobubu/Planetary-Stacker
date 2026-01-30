import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Progress callback type
typedef ProgressCallback = void Function(int progress, String message);

/// Result of aligning a single frame
class AlignmentResult {
  /// The aligned frame image
  final cv.Mat alignedFrame;

  /// Detected horizontal shift (pixels)
  final double shiftX;

  /// Detected vertical shift (pixels)
  final double shiftY;

  /// Confidence of the alignment (higher = better match)
  final double confidence;

  const AlignmentResult({
    required this.alignedFrame,
    required this.shiftX,
    required this.shiftY,
    required this.confidence,
  });

  @override
  String toString() =>
      'AlignmentResult(shift: (${shiftX.toStringAsFixed(2)}, ${shiftY.toStringAsFixed(2)}), confidence: ${confidence.toStringAsFixed(3)})';
}

/// Aligns frames using phase correlation
///
/// Phase correlation is a frequency-domain technique that detects
/// translation (shift) between two images with sub-pixel accuracy.
/// It's robust to illumination changes and works well with planetary images.
class PhaseCorrelator {
  /// Align a single frame to a reference frame
  ///
  /// [referenceFrame]: The reference image to align to
  /// [targetFrame]: The image to be aligned
  ///
  /// Returns AlignmentResult with the aligned frame and detected shift
  Future<AlignmentResult> alignFrame({
    required cv.Mat referenceFrame,
    required cv.Mat targetFrame,
  }) async {
    // Convert to grayscale if not already
    final refGray = referenceFrame.channels == 1
        ? referenceFrame.clone()
        : cv.cvtColor(referenceFrame, cv.COLOR_BGR2GRAY);

    final targetGray = targetFrame.channels == 1
        ? targetFrame.clone()
        : cv.cvtColor(targetFrame, cv.COLOR_BGR2GRAY);

    try {
      // Convert to float32 for phase correlation
      final refFloat = refGray.convertTo(cv.MatType.CV_32FC1);
      final targetFloat = targetGray.convertTo(cv.MatType.CV_32FC1);

      // Perform phase correlation
      // Returns the detected shift of target relative to reference
      // phaseCorrelate(target, ref) = how much target is offset from ref
      final (shift, response) = cv.phaseCorrelate(targetFloat, refFloat);

      // Create translation matrix for warpAffine
      // phaseCorrelate returns how to shift target to match reference
      // Matrix format:
      // [1, 0, tx]
      // [0, 1, ty]
      final translationMatrix = cv.Mat.zeros(2, 3, cv.MatType.CV_64FC1);
      translationMatrix.set<double>(0, 0, 1.0);
      translationMatrix.set<double>(0, 2, shift.x);
      translationMatrix.set<double>(1, 1, 1.0);
      translationMatrix.set<double>(1, 2, shift.y);

      // Apply translation to the original color frame
      final aligned = cv.warpAffine(
        targetFrame,
        translationMatrix,
        (targetFrame.cols, targetFrame.rows),
        flags: cv.INTER_LINEAR,
        borderMode: cv.BORDER_REFLECT,
      );

      // Cleanup intermediate matrices
      refFloat.dispose();
      targetFloat.dispose();
      translationMatrix.dispose();
      refGray.dispose();
      targetGray.dispose();

      return AlignmentResult(
        alignedFrame: aligned,
        shiftX: shift.x,
        shiftY: shift.y,
        confidence: response,
      );
    } catch (e) {
      // If alignment fails, return the original frame
      refGray.dispose();
      targetGray.dispose();
      return AlignmentResult(
        alignedFrame: targetFrame.clone(),
        shiftX: 0.0,
        shiftY: 0.0,
        confidence: 0.0,
      );
    }
  }

  /// Align multiple frames to a reference frame
  ///
  /// [frames]: List of frames to align (will be modified)
  /// [referenceIndex]: Index of the reference frame (default: 0 = first frame)
  /// [onProgress]: Optional progress callback
  ///
  /// Returns list of aligned frames (reference frame is cloned unchanged)
  Future<List<cv.Mat>> alignFrames({
    required List<cv.Mat> frames,
    int referenceIndex = 0,
    ProgressCallback? onProgress,
  }) async {
    if (frames.isEmpty) {
      return [];
    }

    if (referenceIndex < 0 || referenceIndex >= frames.length) {
      referenceIndex = 0;
    }

    final referenceFrame = frames[referenceIndex];
    final alignedFrames = <cv.Mat>[];

    for (int i = 0; i < frames.length; i++) {
      if (i == referenceIndex) {
        // Reference frame doesn't need alignment
        alignedFrames.add(frames[i].clone());
      } else {
        final result = await alignFrame(
          referenceFrame: referenceFrame,
          targetFrame: frames[i],
        );
        alignedFrames.add(result.alignedFrame);
      }

      onProgress?.call(
        ((i + 1) * 100 / frames.length).round(),
        'Aligning frame ${i + 1}/${frames.length}',
      );
    }

    return alignedFrames;
  }

  /// Align frames from file paths
  ///
  /// [framePaths]: List of paths to frame images
  /// [referenceIndex]: Index of the reference frame (default: 0)
  /// [onProgress]: Optional progress callback
  ///
  /// Returns list of aligned cv.Mat frames (caller must dispose)
  Future<List<cv.Mat>> alignFramesFromPaths({
    required List<String> framePaths,
    int referenceIndex = 0,
    ProgressCallback? onProgress,
  }) async {
    if (framePaths.isEmpty) {
      return [];
    }

    // Load all frames
    final frames = <cv.Mat>[];
    for (int i = 0; i < framePaths.length; i++) {
      final frame = cv.imread(framePaths[i], flags: cv.IMREAD_COLOR);
      if (!frame.isEmpty) {
        frames.add(frame);
      }

      onProgress?.call(
        ((i + 1) * 50 / framePaths.length).round(),
        'Loading frame ${i + 1}/${framePaths.length}',
      );
    }

    // Align frames
    final aligned = await alignFrames(
      frames: frames,
      referenceIndex: referenceIndex,
      onProgress: (p, m) => onProgress?.call(50 + (p * 0.5).round(), m),
    );

    // Dispose original frames (aligned are new copies)
    for (final frame in frames) {
      frame.dispose();
    }

    return aligned;
  }
}
