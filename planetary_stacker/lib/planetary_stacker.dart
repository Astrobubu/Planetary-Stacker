/// Planetary Stacker - Main Dart API
///
/// Process phone-through-telescope videos into sharp planetary images.
/// Uses opencv_dart for image processing and ffmpeg_kit for video extraction.
library planetary_stacker;

// Export the main classes
export 'src/processing_params.dart';
export 'src/frame_analysis.dart';
export 'src/stacker.dart';
export 'src/video/frame_extractor.dart' show FrameExtractor, VideoInfo;
export 'src/sharpening/wavelet_sharpener.dart' show WaveletSharpener, WaveletDecomposition, WaveletPreset;
export 'src/quality/quality_assessor.dart' show QualityAssessor;
export 'src/alignment/phase_correlator.dart' show PhaseCorrelator, AlignmentResult;
export 'src/stacking/sigma_clip_stacker.dart' show SigmaClipStacker;

/// Library version
const String version = '0.2.0';
