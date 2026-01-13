/// Frame quality analysis result
class FrameScore {
  /// Frame index in the video
  final int frameIndex;

  /// Quality score (higher = sharper)
  final double qualityScore;

  /// Region of interest (planet bounding box)
  final Rectangle roi;

  const FrameScore({
    required this.frameIndex,
    required this.qualityScore,
    required this.roi,
  });

  @override
  String toString() =>
      'FrameScore(index: $frameIndex, quality: ${qualityScore.toStringAsFixed(3)}, roi: $roi)';
}

/// Rectangle representing a region of interest
class Rectangle {
  final int x;
  final int y;
  final int width;
  final int height;

  const Rectangle({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  @override
  String toString() => 'Rectangle(x: $x, y: $y, w: $width, h: $height)';
}

/// Video analysis result
class AnalysisResult {
  /// All analyzed frame scores (sorted by quality, descending)
  final List<FrameScore> scores;

  /// Total number of frames in the video
  final int totalFrames;

  const AnalysisResult({
    required this.scores,
    required this.totalFrames,
  });

  /// Get the top N% of frames
  List<FrameScore> getTopFrames(double percentage) {
    final count = (scores.length * percentage).round().clamp(1, scores.length);
    return scores.take(count).toList();
  }

  /// Get a specific number of top frames
  List<FrameScore> getTopNFrames(int n) {
    return scores.take(n.clamp(1, scores.length)).toList();
  }

  /// Get quality statistics
  QualityStats get stats {
    if (scores.isEmpty) {
      return const QualityStats(min: 0, max: 0, mean: 0, median: 0);
    }

    final qualities = scores.map((s) => s.qualityScore).toList();
    qualities.sort();

    final min = qualities.first;
    final max = qualities.last;
    final mean = qualities.reduce((a, b) => a + b) / qualities.length;
    final median = qualities[qualities.length ~/ 2];

    return QualityStats(min: min, max: max, mean: mean, median: median);
  }

  @override
  String toString() =>
      'AnalysisResult(analyzed: ${scores.length}, total: $totalFrames, stats: $stats)';
}

/// Quality statistics
class QualityStats {
  final double min;
  final double max;
  final double mean;
  final double median;

  const QualityStats({
    required this.min,
    required this.max,
    required this.mean,
    required this.median,
  });

  @override
  String toString() =>
      'QualityStats(min: ${min.toStringAsFixed(3)}, max: ${max.toStringAsFixed(3)}, '
      'mean: ${mean.toStringAsFixed(3)}, median: ${median.toStringAsFixed(3)})';
}
