/// Processing parameters for planetary stacking
class ProcessingParams {
  /// Percentage of frames to keep (0.0 to 1.0)
  /// Default: 0.25 (top 25% sharpest frames)
  final double keepPercentage;

  /// Minimum number of frames to use
  final int minFrames;

  /// Maximum number of frames to use
  final int maxFrames;

  /// Enable tile-based local alignment
  /// Slower but better quality for large planets
  final bool enableLocalAlign;

  /// Tile size for local alignment (16, 32, or 64)
  final int tileSize;

  /// Sigma clipping threshold for outlier rejection
  final double sigmaClipThreshold;

  /// Number of sigma clipping iterations
  final int sigmaIterations;

  /// Wavelet sharpening layer strengths
  final WaveletLayers waveletLayers;

  const ProcessingParams({
    this.keepPercentage = 0.25,
    this.minFrames = 50,
    this.maxFrames = 500,
    this.enableLocalAlign = true,
    this.tileSize = 32,
    this.sigmaClipThreshold = 2.5,
    this.sigmaIterations = 2,
    this.waveletLayers = const WaveletLayers(),
  });

  /// Create params optimized for Jupiter/Saturn
  factory ProcessingParams.forJupiterSaturn() {
    return const ProcessingParams(
      keepPercentage: 0.25,
      tileSize: 32,
      waveletLayers: WaveletLayers.aggressive(),
    );
  }

  /// Create params optimized for Mars
  factory ProcessingParams.forMars() {
    return const ProcessingParams(
      keepPercentage: 0.30,
      tileSize: 24,
      waveletLayers: WaveletLayers.moderate(),
    );
  }

  /// Create params optimized for the Moon
  factory ProcessingParams.forMoon() {
    return const ProcessingParams(
      keepPercentage: 0.15,
      tileSize: 48,
      waveletLayers: WaveletLayers.conservative(),
    );
  }

  /// Create params optimized for the Sun
  factory ProcessingParams.forSun() {
    return const ProcessingParams(
      keepPercentage: 0.20,
      tileSize: 32,
      waveletLayers: WaveletLayers.solar(),
    );
  }
}

/// Wavelet sharpening layer strengths
class WaveletLayers {
  /// Layer 0: Finest details (1-2px features) - often contains noise
  final double layer0;

  /// Layer 1: Fine details (2-4px features) - planetary surface texture
  final double layer1;

  /// Layer 2: Medium details (4-8px features) - cloud bands
  final double layer2;

  /// Layer 3: Coarse details (8-16px features) - major features
  final double layer3;

  /// Layer 4: Very coarse (16-32px features) - limb, large shadows
  final double layer4;

  const WaveletLayers({
    this.layer0 = 0.8, // Reduce to minimize noise
    this.layer1 = 1.5, // Boost fine details
    this.layer2 = 2.0, // Boost medium details
    this.layer3 = 1.8, // Boost coarse details
    this.layer4 = 1.2, // Slight boost
  });

  /// Aggressive sharpening (for good seeing conditions)
  const WaveletLayers.aggressive()
      : layer0 = 0.6,
        layer1 = 2.0,
        layer2 = 2.5,
        layer3 = 2.2,
        layer4 = 1.5;

  /// Moderate sharpening (balanced)
  const WaveletLayers.moderate()
      : layer0 = 0.8,
        layer1 = 1.5,
        layer2 = 2.0,
        layer3 = 1.8,
        layer4 = 1.2;

  /// Conservative sharpening (for noisy data)
  const WaveletLayers.conservative()
      : layer0 = 0.5,
        layer1 = 1.2,
        layer2 = 1.5,
        layer3 = 1.3,
        layer4 = 1.0;

  /// Solar imaging preset (different characteristics)
  const WaveletLayers.solar()
      : layer0 = 0.7,
        layer1 = 1.8,
        layer2 = 2.2,
        layer3 = 1.5,
        layer4 = 1.0;
}
