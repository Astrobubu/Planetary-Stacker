# Getting Started with Planetary Stacker

## 🎉 What's Been Created

You now have a complete Flutter FFI plugin foundation for the Planetary Stacker app!

### Project Layout

```
Planetary-Stacker/
├── docs/
│   ├── DESIGN_SPECIFICATION.md    # Complete algorithm documentation (20+ pages)
│   └── NEXT_STEPS.md              # Detailed implementation roadmap
│
├── planetary_stacker/             # ← Flutter FFI Plugin (MAIN WORK HERE)
│   ├── lib/                       # Dart API layer
│   │   ├── planetary_stacker.dart # Main public API
│   │   └── src/
│   │       ├── processing_params.dart   # Parameters & presets
│   │       ├── frame_analysis.dart      # Analysis result types
│   │       └── stacker.dart             # Main stacker class
│   │
│   ├── src/                       # C++ implementation
│   │   ├── planetary_stacker.h    # C API header (FFI boundary)
│   │   └── planetary_stacker.cpp  # C++ implementation (stub, ready for code)
│   │
│   ├── android/
│   │   └── CMakeLists.txt         # Android build configuration
│   │
│   ├── example/
│   │   └── lib/main.dart          # Demo app (Material 3 UI)
│   │
│   ├── README.md                  # Plugin usage guide
│   ├── PROJECT_STATUS.md          # Current status & roadmap
│   └── pubspec.yaml               # Flutter configuration
│
└── README.md                      # Main project overview
```

## 🚀 Quick Start

### 1. Flutter SDK Installation

Flutter is currently installing in the background (Dart SDK ~75% downloaded).

Once complete, verify:
```bash
~/flutter/bin/flutter doctor
```

Add to your PATH permanently:
```bash
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.zshrc
source ~/.zshrc
flutter --version
```

### 2. Test the Example App (with stub data)

```bash
cd planetary_stacker/example
flutter pub get
flutter run
# Choose your device/simulator
```

You'll see:
- Library version displayed
- "Test Frame Analysis" button (returns mock data)
- "Test Full Processing" button (simulates pipeline)
- Progress bar and status updates

### 3. Explore the Dart API

Open `planetary_stacker/lib/planetary_stacker.dart`:

```dart
import 'package:planetary_stacker/planetary_stacker.dart';

// Create stacker
final stacker = PlanetaryStacker();

// Analyze video (currently returns stub data)
final analysis = await stacker.analyzeVideo(
  videoPath: '/path/to/jupiter.mp4',
  sampleStep: 3,
  onProgress: (progress, message) {
    print('$progress%: $message');
  },
);

// Use planet-specific presets
final params = ProcessingParams.forJupiterSaturn();

// Process full video (currently simulated)
await stacker.processVideo(
  videoPath: '/path/to/jupiter.mp4',
  outputPath: '/path/to/stacked.png',
  params: params,
  onProgress: (progress, message) {
    print('$progress%: $message');
  },
);
```

## 💻 Next: Implement the C++ Pipeline

The fun part - making it actually work!

### Phase 1: Add OpenCV & FFmpeg

1. **Download OpenCV for Android**:
   ```bash
   cd planetary_stacker/android
   # Download OpenCV Android SDK
   wget https://github.com/opencv/opencv/releases/download/4.8.0/opencv-4.8.0-android-sdk.zip
   unzip opencv-4.8.0-android-sdk.zip
   ```

2. **Update CMakeLists.txt**:
   ```cmake
   # Add OpenCV
   set(OpenCV_DIR "${CMAKE_CURRENT_SOURCE_DIR}/OpenCV-android-sdk/sdk/native/jni")
   find_package(OpenCV REQUIRED)
   
   target_link_libraries(planetary_stacker
       ${OpenCV_LIBS}
       android
       log
   )
   ```

### Phase 2: Implement Video Decoding

Create `src/video/VideoReader.cpp`:

```cpp
#include <opencv2/opencv.hpp>
#include "../planetary_stacker.h"

class VideoReader {
public:
    VideoReader(const std::string& path) {
        cap_.open(path);
        if (!cap_.isOpened()) {
            throw std::runtime_error("Cannot open video");
        }
    }
    
    cv::Mat readFrame(int index) {
        cap_.set(cv::CAP_PROP_POS_FRAMES, index);
        cv::Mat frame;
        cap_.read(frame);
        return frame;
    }
    
    int getFrameCount() const {
        return cap_.get(cv::CAP_PROP_FRAME_COUNT);
    }
    
private:
    cv::VideoCapture cap_;
};
```

### Phase 3: Implement Frame Analysis

Update `planetary_stacker.cpp`:

```cpp
#include "video/VideoReader.cpp"
#include <opencv2/opencv.hpp>

PSAnalysisResult* ps_analyze_video(...) {
    try {
        VideoReader reader(video_path);
        int total_frames = reader.getFrameCount();
        
        std::vector<PSFrameScore> scores;
        
        for (int i = 0; i < total_frames; i += sample_step) {
            // Read frame
            cv::Mat frame = reader.readFrame(i);
            cv::Mat gray;
            cv::cvtColor(frame, gray, cv::COLOR_BGR2GRAY);
            
            // Compute quality (Laplacian variance)
            cv::Mat laplacian;
            cv::Laplacian(gray, laplacian, CV_64F);
            cv::Scalar mean, stddev;
            cv::meanStdDev(laplacian, mean, stddev);
            double quality = stddev[0] * stddev[0];  // Variance
            
            // Store result
            PSFrameScore score;
            score.frame_index = i;
            score.quality_score = quality;
            // ... fill roi
            scores.push_back(score);
            
            // Progress callback
            if (callback) {
                int progress = (i * 100) / total_frames;
                callback(progress, "Analyzing...", user_data);
            }
        }
        
        // Return results
        auto* result = new PSAnalysisResult();
        result->count = scores.size();
        result->scores = new PSFrameScore[scores.size()];
        std::copy(scores.begin(), scores.end(), result->scores);
        
        return result;
    } catch (...) {
        return nullptr;
    }
}
```

### Phase 4: Test Your Changes

```bash
cd planetary_stacker/example
flutter run
# Click "Test Frame Analysis"
# You should see REAL quality scores from your video!
```

## 📚 Key Files to Read

1. **`docs/DESIGN_SPECIFICATION.md`** - Complete algorithm details
2. **`planetary_stacker/src/planetary_stacker.h`** - C API you need to implement
3. **`planetary_stacker/lib/src/stacker.dart`** - Dart API that calls your C++ code
4. **`planetary_stacker/PROJECT_STATUS.md`** - Current status & what to build next

## 🎯 Recommended Development Path

1. ✅ **Foundation** (Done!) - Project structure, API design
2. **Week 1**: Video decoding + frame quality analysis
3. **Week 2**: Global alignment (phase correlation)
4. **Week 3**: Local alignment + stacking
5. **Week 4**: Wavelet sharpening + optimization

## 🔧 Development Commands

```bash
# Run example app
cd planetary_stacker/example
flutter run

# Generate FFI bindings (after implementing C++ header)
cd planetary_stacker
flutter pub run ffigen

# Run Dart tests
flutter test

# Build Android APK
cd example
flutter build apk

# Hot reload during development
# (Just save files while `flutter run` is active)
```

## 📖 Learning Resources

- **Flutter FFI**: https://docs.flutter.dev/platform-integration/android/c-interop
- **OpenCV Tutorials**: https://docs.opencv.org/4.x/d9/df8/tutorial_root.html
- **Phase Correlation**: See `docs/DESIGN_SPECIFICATION.md` section on alignment
- **Wavelet Sharpening**: See `docs/DESIGN_SPECIFICATION.md` section on sharpening

## 🎨 Example UI Preview

The example app shows:
- Library version
- Progress bar (0-100%)
- Status messages
- Analysis results (frame count, quality stats)
- Top 10 sharpest frames

Once you implement the C++ code, all of this will work with REAL data!

## 💡 Tips

1. **Start small**: Get video decoding working first
2. **Test often**: Use the example app to see results immediately
3. **Check logs**: Use `flutter logs` to see print statements
4. **Debug C++**: Use Android Studio's native debugger
5. **Reference the design spec**: All algorithms are documented in detail

## 🚀 You're Ready!

The architecture is clean, the interfaces are defined, and the path is clear.

Start with `planetary_stacker/src/planetary_stacker.cpp` and bring those algorithms to life!

---

**Questions?** Check:
- `planetary_stacker/README.md` - Plugin usage
- `planetary_stacker/PROJECT_STATUS.md` - Implementation roadmap  
- `docs/DESIGN_SPECIFICATION.md` - Complete algorithm details
- `docs/NEXT_STEPS.md` - Step-by-step implementation guide
