# Planetary Stacker - Mobile

A high-performance planetary imaging application for mobile devices, bringing AutoStakkert-quality processing to your smartphone.

## Vision

**"The algorithms are open - it's the engineering polish that separates a toy from a tool."**

This project aims to create a production-quality mobile app for planetary image stacking, combining the proven algorithms from AutoStakkert and Registax with mobile-optimized engineering.

## What is Planetary Stacking?

Planetary imaging through telescopes faces a fundamental challenge: Earth's atmosphere constantly blurs and distorts the view. Professional planetary photographers use a technique called "lucky imaging":

1. **Capture video** - Record thousands of frames through your telescope
2. **Analyze quality** - Identify the sharpest frames (when atmospheric turbulence was minimal)
3. **Align frames** - Compensate for tracking drift and atmospheric distortion
4. **Stack frames** - Combine the best frames to reduce noise
5. **Sharpen** - Enhance fine details using wavelet processing

The result: Stunning high-resolution images of Jupiter's cloud bands, Saturn's rings, Mars' surface features, and lunar craters.

## Current Desktop Solutions

- **AutoStakkert!3** - Gold standard for alignment, Windows-only
- **Registax 6** - Famous for wavelet sharpening, Windows-only
- **PIPP** - Pre-processing tool, Windows-only
- **PyStacker** - Open-source Python implementation, desktop-focused

**The gap**: No production-quality mobile solution exists.

## Project Goals

### Phase 1: Core Pipeline (Current Focus)
- ✅ Algorithm specification (see `docs/DESIGN_SPECIFICATION.md`)
- ⬜ C++ implementation with OpenCV
- ⬜ Flutter UI framework
- ⬜ Video import (MP4/MOV support)
- ⬜ Frame quality analysis
- ⬜ Global + local alignment
- ⬜ Weighted stacking with sigma rejection
- ⬜ Multi-layer wavelet sharpening

### Phase 2: Mobile Optimization
- ⬜ Memory-efficient processing (chunked operations)
- ⬜ Thermal management (avoid CPU throttling)
- ⬜ Background processing support
- ⬜ Progressive preview updates
- ⬜ Battery efficiency optimization

### Phase 3: Advanced Features
- ⬜ Planetary derotation (for long captures)
- ⬜ RGB channel processing
- ⬜ Batch processing
- ⬜ Custom processing profiles
- ⬜ Export to FITS/TIFF formats

### Phase 4: Community Features
- ⬜ Processing preset sharing
- ⬜ Before/after gallery
- ⬜ Integration with astrophotography platforms
- ⬜ Tutorial system

## Architecture

```
┌─────────────────────────────────────────────┐
│  Flutter UI Layer                           │
│  - Video selection                          │
│  - Processing controls                      │
│  - Progress visualization                   │
│  - Wavelet adjustment sliders               │
└──────────────┬──────────────────────────────┘
               │
┌──────────────▼──────────────────────────────┐
│  Dart/FFI Bridge                            │
│  - Parameter passing                        │
│  - Progress callbacks                       │
│  - Memory management                        │
└──────────────┬──────────────────────────────┘
               │
┌──────────────▼──────────────────────────────┐
│  C++ Processing Core (NDK)                  │
│  - OpenCV-based pipeline                    │
│  - FFmpeg video decoding                    │
│  - Multi-threaded processing                │
│  - ARM NEON optimization                    │
└─────────────────────────────────────────────┘
```

## Technical Specifications

See [`docs/DESIGN_SPECIFICATION.md`](docs/DESIGN_SPECIFICATION.md) for complete algorithmic details.

### Key Algorithms

| Stage | Algorithm | Key Technology |
|-------|-----------|----------------|
| Frame Analysis | Multi-metric quality scoring | Laplacian variance + FFT + Sobel |
| Frame Selection | Temporal spread selection | Quality-based sampling |
| Global Alignment | Phase correlation | FFT-based sub-pixel registration |
| Local Alignment | Tile-based warping | Template matching + thin-plate spline |
| Stacking | Sigma-clipped weighted average | Outlier rejection |
| Sharpening | À trous wavelet decomposition | Multi-scale detail enhancement |

### Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| RAM Usage | < 500MB peak | Chunked processing enables this |
| Processing Time | 2-5 min for 500 frames | On mid-range phone (2020+) |
| Battery Impact | < 15% drain | Thermal-aware scheduling |
| Supported Resolution | Up to 4K | 3840×2160 input video |
| Frame Count | 50-500 frames | Adjustable by user |

## Development Roadmap

### Immediate Next Steps

1. **Set up C++ project structure**
   - Configure CMake build
   - Integrate OpenCV for Android
   - Set up FFmpeg for video decoding
   - Create FFI interface definitions

2. **Implement Pass 1: Frame Analysis**
   - Video decoding infrastructure
   - Planet detection (Otsu + contours)
   - Quality metrics (Laplacian, Sobel, FFT)
   - ROI tracking

3. **Build minimal Flutter UI**
   - Video picker
   - Processing trigger
   - Progress display
   - Results viewer

4. **Validate on test data**
   - Collect sample Jupiter/Saturn videos
   - Benchmark against AutoStakkert
   - Tune quality metric weights

## Technology Stack

- **Frontend**: Flutter (Dart)
- **Backend**: C++ (Android NDK)
- **Computer Vision**: OpenCV 4.x
- **Video Decoding**: FFmpeg / Android MediaCodec
- **Build System**: CMake
- **Platforms**: Android (iOS future consideration)

## Project Structure

```
Planetary-Stacker/
├── docs/
│   └── DESIGN_SPECIFICATION.md    # Complete algorithm documentation
├── lib/                            # Flutter/Dart code
│   ├── ui/                        # User interface
│   ├── models/                    # Data models
│   └── native_bridge/             # FFI bindings
├── native/                        # C++ processing core
│   ├── src/
│   │   ├── video/                 # Video decoding
│   │   ├── analysis/              # Quality scoring
│   │   ├── alignment/             # Phase correlation & warping
│   │   ├── stacking/              # Frame combination
│   │   └── wavelets/              # Sharpening
│   ├── include/                   # Public headers
│   ├── test/                      # C++ unit tests
│   └── CMakeLists.txt
├── android/                       # Android-specific config
├── test/                          # Dart tests
└── assets/                        # UI resources, sample data
```

## Getting Started

*This section will be populated once the initial implementation is complete.*

## Contributing

*Contribution guidelines will be added once the core architecture is stable.*

## License

*To be determined - considering MIT or Apache 2.0*

## Acknowledgments

This project builds on decades of planetary imaging knowledge from the amateur astronomy community:

- **Emil Kraaikamp** (AutoStakkert) - Tile-based alignment approach
- **Cor Berrevoets** (Registax) - Wavelet sharpening techniques
- **Grischa Hahn** (WinJUPOS) - Derotation methods
- The global amateur planetary imaging community for openly sharing techniques

## References

- Fried, D.L. (1978). "Probability of getting a lucky short-exposure image through turbulence"
- Law, N.M. et al. (2006). "Lucky Imaging: High Angular Resolution Imaging in the Visible from the Ground"
- Starck, J.L. et al. (1998). "Image decomposition via the combination of sparse representations and a variational approach"

---

**Status**: Early design phase - algorithm specification complete, implementation in progress
**Last Updated**: 2026-01-11
