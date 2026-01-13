# Next Steps: Implementation Roadmap

This document outlines the concrete next steps to move from pseudocode specification to a working mobile application.

## Decision Point: Choose Your Path

Based on the design specification, we can now proceed in several directions:

### Option 1: C++ Implementation (Recommended First)
Start building the actual processing engine that will do the heavy lifting.

**Why this first?**
- Core algorithms are the hardest part
- Can validate the design with real performance data
- UI can come later once we know the processing pipeline works
- Can test on desktop before mobile integration

**What you'll build:**
- CMake project structure
- OpenCV integration
- Pass 1: Frame quality analysis (the foundation)
- Unit tests with sample planetary videos

**Time investment:** 1-2 weeks for Pass 1 working implementation

---

### Option 2: Flutter UI Design
Design the user experience and interface components.

**Why this first?**
- Validates the user workflow early
- Can mock the backend initially
- Helps clarify what parameters users actually need
- Good if you have sample processing to show

**What you'll build:**
- Flutter project setup
- Video selection screen
- Processing parameter controls
- Mock progress visualization
- Results viewer with before/after

**Time investment:** 1 week for UI mockups + navigation

---

### Option 3: Architecture Prototype
Build the integration layer between Flutter and C++.

**Why this first?**
- Proves the FFI approach works
- Identifies integration challenges early
- Can start with simple test functions
- Good if unfamiliar with Flutter-to-C++ communication

**What you'll build:**
- FFI bindings setup
- Simple "hello world" C++ function called from Dart
- Progress callback mechanism
- Memory management patterns

**Time investment:** 2-3 days for working integration

---

## Recommended Sequence

Based on the "build what you can validate" principle:

### Phase A: Desktop C++ Prototype (2 weeks)
Build just Pass 1 (Frame Analysis) as a standalone C++ program.

```bash
# Input: planetary_video.mp4
# Output: quality_scores.csv + selected_frames.txt

./stacker_analyze planetary_video.mp4 --top 25%
```

**Deliverable:**
- Reads MP4 file
- Detects planetary disk
- Scores all frames
- Outputs top 25% frame numbers
- Includes performance metrics (fps processed, memory used)

**Validation:**
- Compare scores to AutoStakkert's frame ranking
- Visual inspection of selected vs rejected frames
- Performance acceptable on laptop (extrapolate to mobile)

---

### Phase B: Full Pipeline (Desktop) (3 weeks)
Extend to Passes 2-5, still on desktop.

```bash
./stacker_full planetary_video.mp4 \
  --frames 25% \
  --local-align \
  --tile-size 32 \
  --output result.png
```

**Deliverable:**
- End-to-end processing
- Outputs final stacked image
- Wavelet sharpening with default parameters

**Validation:**
- Side-by-side comparison with AutoStakkert output
- Quality assessment by experienced planetary imagers
- Performance profiling (where is time spent?)

---

### Phase C: Mobile Integration (2 weeks)
Port the C++ engine to Android via Flutter.

**Deliverable:**
- Flutter app with minimal UI
- Calls C++ processing core via FFI
- Displays progress updates
- Shows final result

**Validation:**
- Runs on actual Android device
- Memory stays under 500MB
- CPU doesn't thermal throttle
- Battery impact acceptable

---

### Phase D: UI Polish (2 weeks)
Build the full user experience.

**Deliverable:**
- Wavelet adjustment sliders
- Before/after comparison
- Processing history
- Settings persistence

**Validation:**
- Beta testing with amateur astronomers
- UI/UX feedback iteration
- Performance tuning based on real usage

---

## Detailed: Phase A Implementation Guide

Since Phase A is the immediate next step, here's the detailed breakdown:

### Week 1: Project Setup + Video Decoding

**Day 1-2: Project Structure**
```bash
mkdir -p native/{src,include,test,third_party}
cd native

# CMakeLists.txt for:
# - OpenCV linkage
# - FFmpeg/libav linkage
# - C++17 standard
# - Debug/Release configs
```

**Day 3-4: Video Decoding Infrastructure**
```cpp
// src/video/VideoReader.hpp
class VideoReader {
public:
    VideoReader(const std::string& path);
    ~VideoReader();

    int getFrameCount() const;
    cv::Mat readFrame(int index);
    cv::Mat readFrameROI(int index, cv::Rect roi);

    int getWidth() const;
    int getHeight() const;
    double getFPS() const;

private:
    // FFmpeg internals
    AVFormatContext* format_ctx_;
    AVCodecContext* codec_ctx_;
    // ... etc
};
```

**Validation:**
- Can open MP4/MOV files
- Can seek to arbitrary frame
- Returns cv::Mat in RGB format
- Performance: decode 1080p frame in < 10ms

---

**Day 5-7: Planet Detection**
```cpp
// src/analysis/PlanetDetector.hpp
class PlanetDetector {
public:
    cv::Rect detect(const cv::Mat& frame);

private:
    cv::Rect detectByBrightness(const cv::Mat& frame);
    cv::Rect detectByCircles(const cv::Mat& frame);
};
```

**Test cases:**
- Jupiter (bright, oval)
- Saturn (with rings)
- Mars (small, round)
- Moon (large, high contrast)

**Validation:**
- Correctly identifies planet in 95%+ of test frames
- Runs in < 5ms per frame
- Bounding box includes all planet features (e.g., Saturn's rings)

---

### Week 2: Quality Metrics + Integration

**Day 8-10: Quality Scoring**
```cpp
// src/analysis/QualityMetrics.hpp
class QualityMetrics {
public:
    struct Score {
        double laplacian_variance;
        double gradient_energy;
        double high_freq_energy;
        double combined;
    };

    static Score compute(const cv::Mat& roi);

private:
    static double computeLaplacianVariance(const cv::Mat& img);
    static double computeGradientEnergy(const cv::Mat& img);
    static double computeHighFreqEnergy(const cv::Mat& img);
};
```

**Validation:**
- Sharp frame scores > 0.8
- Blurry frame scores < 0.3
- Monotonic relationship with visual quality
- Runs in < 10ms per ROI

---

**Day 11-12: Frame Analyzer (Orchestration)**
```cpp
// src/analysis/FrameAnalyzer.hpp
class FrameAnalyzer {
public:
    struct FrameScore {
        int index;
        double score;
        cv::Rect roi;
    };

    std::vector<FrameScore> analyzeVideo(
        const std::string& video_path,
        int sample_step = 3
    );

    void setProgressCallback(std::function<void(int, int)> cb);
};
```

**Integration test:**
```cpp
// test/test_analyzer.cpp
TEST(FrameAnalyzer, AnalyzesJupiterVideo) {
    FrameAnalyzer analyzer;
    auto scores = analyzer.analyzeVideo("test_data/jupiter_500frames.mp4");

    EXPECT_GT(scores.size(), 100);  // Sampled frames
    EXPECT_GT(scores[0].score, scores.back().score);  // Sorted by quality

    // Top 25% should be "good" frames
    int top25 = scores.size() / 4;
    for (int i = 0; i < top25; ++i) {
        EXPECT_GT(scores[i].score, 0.6);
    }
}
```

---

**Day 13-14: Command-Line Tool + Documentation**
```cpp
// src/main_analyze.cpp
int main(int argc, char** argv) {
    // Parse arguments
    // Run analysis
    // Output CSV: frame_index, score, roi_x, roi_y, roi_w, roi_h
    // Output summary: top 25% frame indices
}
```

**Example output:**
```
Analyzing: jupiter_2024-03-15.mp4
Frames: 1200 (40 seconds @ 30fps)
Resolution: 1920x1080

Detecting planet... ━━━━━━━━━━━━━━━━━━━━━━━━ 100%
Found: Jupiter at (960, 540), size 450x400

Scoring frames... ━━━━━━━━━━━━━━━━━━━━━━━━━━ 100%
Analyzed 400 frames (sampling every 3rd)

Quality distribution:
  Top 25%:    0.78 - 0.95
  Median:     0.52
  Bottom 25%: 0.23 - 0.45

Selected 100 frames for stacking (25%)

Output written to:
  - jupiter_2024-03-15_scores.csv
  - jupiter_2024-03-15_selected.txt

Next: Run with these frames:
  ./stacker_align jupiter_2024-03-15.mp4 \
    --frames jupiter_2024-03-15_selected.txt
```

---

## What You'll Learn

### Phase A gives you:

1. **Performance reality check**
   - Is FFT quality metric fast enough?
   - Does video decoding bottleneck the pipeline?
   - Memory usage patterns

2. **Algorithm validation**
   - Do the quality metrics actually correlate with visual quality?
   - Is Laplacian variance + gradient + FFT the right combo?
   - Do we need per-planet tuning?

3. **Integration insights**
   - How to structure the C++ codebase for later mobile integration
   - What the Dart FFI interface will need to look like
   - Progress callback patterns

4. **Test data collection**
   - Which planetary videos work well as benchmarks
   - What edge cases exist (very small planets, overexposed, etc.)

---

## Making the Choice

**Choose Option 1 (C++ Implementation) if:**
- You want to validate the algorithms work as specified
- You're comfortable with C++/OpenCV/FFmpeg
- You want to benchmark performance before committing to mobile
- You can get sample planetary videos for testing

**Choose Option 2 (Flutter UI) if:**
- You want to prototype the user experience first
- You have existing processed images to show in the UI
- You're more comfortable with Dart/Flutter than C++
- You want to validate the workflow before building the engine

**Choose Option 3 (Architecture Prototype) if:**
- You've never done Flutter-to-C++ FFI before
- You want to derisk the integration layer early
- You're unsure about threading/memory management across the boundary

---

## Success Metrics

By the end of Phase A, you should be able to:

- [ ] Analyze a 500-frame Jupiter video in < 30 seconds (on laptop)
- [ ] Identify the top 25% sharpest frames
- [ ] Visual inspection confirms selected frames are indeed sharper
- [ ] Memory usage stays under 200MB during processing
- [ ] Code is clean enough to show other developers

By the end of Phase B:
- [ ] Produce a stacked image comparable to AutoStakkert output
- [ ] Complete processing pipeline runs in < 5 minutes (laptop)
- [ ] Wavelet sharpening produces natural-looking results

By the end of Phase C:
- [ ] App runs on Android device
- [ ] Processing completes without crashes or thermal throttling
- [ ] Results match desktop version (no mobile-specific bugs)

By the end of Phase D:
- [ ] 10 beta testers successfully process their own videos
- [ ] Positive feedback on usability
- [ ] No critical bugs reported

---

## Questions to Answer Before Starting

1. **Do you have sample planetary videos to test with?**
   - If not, we can find public datasets or generate synthetic test cases

2. **What's your development environment?**
   - macOS/Linux/Windows?
   - C++ compiler version?
   - CMake installed?

3. **Have you worked with OpenCV before?**
   - If yes: jump straight to implementation
   - If no: might want a tutorial detour first

4. **What's your timeline preference?**
   - Sprint mode (3-4 weeks to working prototype)?
   - Steady pace (2-3 months to polished app)?
   - Learning mode (no rush, deep understanding)?

---

## Recommended: Start with Phase A, Day 1

**Concrete first task:**
```bash
cd /Users/apple/Apps/Planetary-Stacker
mkdir -p native/{src,include,test,third_party}
cd native

# Create CMakeLists.txt
# Set up OpenCV linkage
# Write "hello world" OpenCV program that loads an image

# Compile and run to validate environment
```

**Expected output:**
```bash
$ ./build/hello_opencv
OpenCV version: 4.8.0
Successfully loaded test image: 640x480
```

Once that works, you're ready to build the VideoReader class.

---

**Ready to proceed?** Which option resonates with you?

1. Dive into C++ implementation (Phase A)
2. Design Flutter UI first (Option 2)
3. Prototype Flutter-to-C++ integration (Option 3)
4. Something else (describe your preference)
