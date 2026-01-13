## Planetary Stacker Flutter Plugin

A high-performance Flutter FFI plugin for planetary image stacking on mobile devices.

### Project Structure

```
planetary_stacker/
├── lib/
│   ├── planetary_stacker.dart              # Main public API
│   └── src/
│       ├── processing_params.dart          # Processing configuration
│       ├── frame_analysis.dart             # Analysis result types
│       └── stacker.dart                    # Main stacker class
├── src/
│   ├── planetary_stacker.h                 # C API header
│   └── planetary_stacker.cpp               # C++ implementation
├── android/
│   └── CMakeLists.txt                      # Android build configuration
├── example/
│   └── lib/
│       └── main.dart                       # Demo app
└── pubspec.yaml                            # Flutter package config
```

### Quick Start

#### 1. Add to your Flutter project

```yaml
dependencies:
  planetary_stacker:
    path: ../planetary_stacker
```

#### 2. Import and use

```dart
import 'package:planetary_stacker/planetary_stacker.dart';

// Create stacker instance
final stacker = PlanetaryStacker();

// Analyze video frames
final analysis = await stacker.analyzeVideo(
  videoPath: '/path/to/jupiter.mp4',
  onProgress: (progress, message) {
    print('$progress%: $message');
  },
);

print('Analyzed ${analysis.scores.length} frames');
print('Quality stats: ${analysis.stats}');

// Process full video
final params = ProcessingParams.forJupiterSaturn();

final success = await stacker.processVideo(
  videoPath: '/path/to/jupiter.mp4',
  outputPath: '/path/to/stacked.png',
  params: params,
  onProgress: (progress, message) {
    print('$progress%: $message');
  },
);
```

### Processing Parameters

The library provides preset parameters for different planet types:

```dart
// Jupiter/Saturn (aggressive sharpening)
ProcessingParams.forJupiterSaturn()

// Mars (moderate sharpening)
ProcessingParams.forMars()

// Moon (conservative sharpening)
ProcessingParams.forMoon()

// Sun (solar-optimized)
ProcessingParams.forSun()

// Or create custom params
ProcessingParams(
  keepPercentage: 0.25,        // Top 25% of frames
  enableLocalAlign: true,      // Tile-based alignment
  tileSize: 32,                // Tile size in pixels
  waveletLayers: WaveletLayers(
    layer0: 0.8,  // Finest details (reduce noise)
    layer1: 1.5,  // Fine details
    layer2: 2.0,  // Medium details
    layer3: 1.8,  // Coarse details
    layer4: 1.2,  // Very coarse
  ),
)
```

### Architecture

```
┌─────────────────────────────────────┐
│  Flutter UI (Dart)                  │
│  - Video selection                  │
│  - Parameter controls               │
│  - Progress display                 │
└──────────────┬──────────────────────┘
               │ FFI (dart:ffi)
┌──────────────▼──────────────────────┐
│  Native Library (C++)               │
│  - OpenCV processing                │
│  - FFmpeg video decoding            │
│  - Multi-threaded pipeline          │
└─────────────────────────────────────┘
```

### Building

#### Prerequisites

- Flutter SDK 3.0+
- Android NDK (for Android builds)
- Xcode (for iOS builds)
- CMake 3.10+

#### Generate FFI Bindings

Once the C++ implementation is complete:

```bash
cd planetary_stacker
flutter pub get
flutter pub run ffigen --config pubspec.yaml
```

This will generate `lib/planetary_stacker_bindings_generated.dart`.

#### Build Native Library

**Android:**
```bash
cd android
./gradlew assembleRelease
```

**iOS:**
```bash
cd ios
pod install
xcodebuild
```

### Development Status

- [x] Project structure
- [x] Dart API design
- [x] C API interface
- [x] Stub C++ implementation
- [ ] OpenCV integration
- [ ] FFmpeg video decoding
- [ ] Frame quality analysis
- [ ] Phase correlation alignment
- [ ] Tile-based local alignment
- [ ] Sigma-clipped stacking
- [ ] Wavelet sharpening
- [ ] Performance optimization
- [ ] Full example app with UI

### Next Steps

1. **Implement C++ processing pipeline**
   - Video decoding with FFmpeg
   - Frame quality metrics (Laplacian, gradient, FFT)
   - Global alignment (phase correlation)
   - Local alignment (tile-based warping)
   - Stacking with sigma rejection
   - Wavelet sharpening (à trous)

2. **Add OpenCV and FFmpeg dependencies**
   - Configure CMake to link OpenCV
   - Add FFmpeg for video I/O
   - Handle different codecs (H.264, HEVC)

3. **Build example app UI**
   - Video picker
   - Processing parameter controls
   - Real-time progress visualization
   - Before/after image viewer
   - Quality graph display

4. **Performance optimization**
   - Multi-threading
   - SIMD (ARM NEON)
   - Memory-efficient chunked processing
   - Thermal throttling management

5. **Testing**
   - Unit tests for processing logic
   - Integration tests with real videos
   - Benchmark against AutoStakkert
   - UI testing

### License

TBD

### References

- [Flutter FFI Documentation](https://docs.flutter.dev/platform-integration/android/c-interop)
- [ffigen Package](https://pub.dev/packages/ffigen)
- [OpenCV for Android](https://opencv.org/android/)
- [Design Specification](../../docs/DESIGN_SPECIFICATION.md)
