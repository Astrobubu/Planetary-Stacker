# Mobile Planetary Stacker - Complete Design Specification

**Vision**: The algorithms are open - it's the engineering polish that separates a toy from a tool.

This document outlines the complete technical architecture for a phone-friendly planetary stacking application, covering all major algorithmic components from frame analysis to wavelet sharpening.

---

## Table of Contents

1. [Design Constraints](#design-constraints)
2. [High-Level Architecture](#high-level-architecture)
3. [Pass 1: Frame Quality Analysis](#pass-1-frame-quality-analysis)
4. [Pass 2: Frame Selection](#pass-2-frame-selection)
5. [Pass 3: Alignment](#pass-3-alignment)
6. [Pass 4: Stacking](#pass-4-stacking)
7. [Pass 5: Wavelet Sharpening](#pass-5-wavelet-sharpening)
8. [Complete Pipeline](#complete-pipeline)
9. [User Interface Parameters](#user-interface-parameters)
10. [Next Steps](#next-steps)

---

## Design Constraints

### Mobile Reality

```
┌─────────────────────────────────────────────────────┐
│  MOBILE REALITY                                     │
├─────────────────────────────────────────────────────┤
│  RAM: 4-8GB shared (keep under 500MB for our app)   │
│  CPU: 8 cores, but thermal throttles after 30s     │
│  GPU: Powerful but API complexity (Vulkan/OpenCL)  │
│  Storage: Fast NVMe, use it for temp files         │
│  Battery: Users will complain if we drain it       │
│  Input: MP4/MOV (H.264/HEVC), not SER/AVI          │
└─────────────────────────────────────────────────────┘
```

**Key Design Principles:**
- Memory efficiency through chunked processing
- Leverage fast storage for intermediate results
- Thermal-aware processing (batch work, allow cooling)
- Native video codec support (H.264/HEVC)
- Progressive feedback (users see progress in real-time)

---

## High-Level Architecture

```
VIDEO IN (MP4/MOV)
      │
      ▼
┌─────────────────┐
│ PASS 1: ANALYZE │  ◄── Fast scan, don't decode full frames
│ - Frame count   │      Use thumbnail/preview decode
│ - Detect planet │
│ - Quality score │      Store: frame_index → quality_score
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ PASS 2: SELECT  │  ◄── Pick top N% frames
│ - Sort by score │      Cluster temporally (avoid all from one moment)
│ - Sample evenly │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ PASS 3: ALIGN   │  ◄── This is where magic happens
│ - Global align  │      Phase correlation first (fast)
│ - Local warp    │      Tile-based optical flow (quality)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ PASS 4: STACK   │  ◄── Combine aligned frames
│ - Weighted mean │      Quality score = weight
│ - Sigma reject  │      Reject outlier pixels
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ PASS 5: SHARPEN │  ◄── User-controlled
│ - Wavelets      │      Multi-layer, adjustable per layer
│ - Edge aware    │      Don't amplify noise
└────────┬────────┘
         │
         ▼
    RESULT IMAGE
```

---

## Pass 1: Frame Quality Analysis

This is the "lucky imaging" core. We need to score each frame quickly to identify the sharpest moments when atmospheric turbulence was minimal.

### Algorithm: Frame Quality Scoring

```
INPUT:  Video file path
OUTPUT: Array of (frame_index, quality_score, planet_bbox)

FUNCTION analyze_video(video_path):

    scores = []

    # First frame: detect planet location
    first_frame = decode_frame(video_path, index=0)
    planet_roi = detect_planet(first_frame)  # Returns bounding box

    # Expand ROI slightly for tracking margin
    roi = expand_bbox(planet_roi, margin=1.2)

    FOR frame_index IN range(0, frame_count, sample_step):

        # Decode only the ROI region if possible (faster)
        # Otherwise decode full frame, crop
        frame = decode_frame_roi(video_path, frame_index, roi)

        # Convert to grayscale (luminance)
        gray = to_grayscale(frame)

        # Quality metric: combination approach
        score = compute_quality(gray)

        # Update ROI tracking (planet may drift)
        IF frame_index % 30 == 0:
            planet_roi = detect_planet(frame)
            roi = expand_bbox(planet_roi, margin=1.2)

        scores.append({
            index: frame_index,
            score: score,
            roi: roi
        })

    RETURN scores
```

### Planet Detection

```
FUNCTION detect_planet(frame):
    """
    Find the planetary disk in frame.
    Works for Jupiter, Saturn, Mars, Moon, Sun.
    """
    gray = to_grayscale(frame)

    # Method 1: Brightness thresholding + contour
    # (Works when planet is brightest object)
    _, binary = threshold(gray, method=OTSU)
    contours = find_contours(binary)
    largest = max(contours, key=area)
    bbox = bounding_rect(largest)

    # Method 2: Hough circles (backup)
    # circles = HoughCircles(gray, ...)

    RETURN bbox
```

### Multi-Metric Quality Scoring

```
FUNCTION compute_quality(gray_roi):
    """
    Multi-metric quality score.
    Higher = sharper = better seeing moment.
    """

    # Metric 1: Laplacian variance (edge sharpness)
    laplacian = cv2.Laplacian(gray_roi, CV_64F)
    lap_var = variance(laplacian)

    # Metric 2: Gradient energy (Sobel-based)
    gx = cv2.Sobel(gray_roi, CV_64F, 1, 0)
    gy = cv2.Sobel(gray_roi, CV_64F, 0, 1)
    gradient_energy = mean(gx² + gy²)

    # Metric 3: High-frequency content (FFT-based)
    fft = np.fft.fft2(gray_roi)
    fft_shift = np.fft.fftshift(fft)
    magnitude = np.abs(fft_shift)
    # Measure energy in outer ring (high frequencies)
    hf_energy = ring_energy(magnitude, inner=0.3, outer=0.8)

    # Combine metrics (weighted)
    # These weights need tuning based on real data
    score = (
        0.4 * normalize(lap_var) +
        0.3 * normalize(gradient_energy) +
        0.3 * normalize(hf_energy)
    )

    RETURN score
```

### Design Rationale

| Decision | Reason |
|----------|--------|
| Sample frames (not all) | 30fps video = 1800 frames/min. Scoring every 3rd is fine |
| ROI tracking | Avoid scoring sky, only planetary disk matters |
| Multi-metric | Single metrics fail on specific cases (rings, bands) |
| Luminance only | Color doesn't help quality assessment |

---

## Pass 2: Frame Selection

### Algorithm: Smart Frame Selection

```
INPUT:  scores[], keep_percentage (e.g., 0.25)
OUTPUT: selected_frame_indices[]

FUNCTION select_frames(scores, keep_pct, min_frames=50, max_frames=500):

    n_total = len(scores)
    n_keep = clamp(n_total * keep_pct, min_frames, max_frames)

    # Sort by quality (descending)
    sorted_scores = sort(scores, by=score, descending=True)

    # NAIVE: Just take top N
    # selected = sorted_scores[:n_keep]

    # BETTER: Temporal spread
    # Avoid selecting 100 frames from same 1-second burst
    selected = select_with_temporal_spread(sorted_scores, n_keep)

    RETURN selected
```

### Temporal Distribution

```
FUNCTION select_with_temporal_spread(sorted_scores, n_keep):
    """
    Select top frames but ensure they're spread across video.
    Prevents all frames coming from one lucky moment.
    """

    selected = []
    used_windows = set()
    window_size = 10  # frames

    FOR score_entry IN sorted_scores:
        window = score_entry.index // window_size

        IF window NOT IN used_windows OR len(selected) < n_keep * 0.5:
            selected.append(score_entry)
            used_windows.add(window)

        IF len(selected) >= n_keep:
            BREAK

    # If we didn't get enough (very short video), just take top N
    IF len(selected) < n_keep:
        selected = sorted_scores[:n_keep]

    RETURN selected
```

**Why Temporal Distribution Matters:**
- Atmospheric turbulence creates brief "good seeing" windows
- Without spread, all selected frames might come from a single 2-second period
- Spreading selections across the video ensures diversity in atmospheric conditions
- Better represents the overall quality of the capture session

---

## Pass 3: Alignment

This is where AutoStakkert excels. We implement a two-stage approach:

### Stage 3A: Global Alignment (Fast, Gets You 80%)

```
INPUT:  reference_frame, frames_to_align[]
OUTPUT: globally_aligned_frames[]

FUNCTION global_align(reference, frames):

    ref_gray = to_grayscale(reference)
    aligned = []

    FOR frame IN frames:
        gray = to_grayscale(frame)

        # Phase correlation: finds translation offset
        # Sub-pixel accurate, FFT-based, very fast
        shift, confidence = cv2.phaseCorrelate(ref_gray, gray)

        dx, dy = shift

        # Apply translation
        M = translation_matrix(dx, dy)
        aligned_frame = cv2.warpAffine(frame, M, frame.size)

        aligned.append({
            frame: aligned_frame,
            shift: (dx, dy),
            confidence: confidence
        })

    RETURN aligned
```

**Phase Correlation Internals:**
1. FFT both images
2. Compute cross-power spectrum: `(F1 * conj(F2)) / |F1 * conj(F2)|`
3. Inverse FFT
4. Peak location = translation offset
5. Sub-pixel via parabolic fitting around peak

### Stage 3B: Local/Tile-Based Alignment (The AutoStakkert Secret)

This compensates for atmospheric turbulence that affects different parts of the planetary disk differently.

```
INPUT:  reference_frame, globally_aligned_frame, tile_size
OUTPUT: locally_warped_frame

FUNCTION local_align(reference, frame, tile_size=32):

    ref_gray = to_grayscale(reference)
    frame_gray = to_grayscale(frame)

    height, width = ref_gray.shape

    # Create grid of alignment points
    grid_points = []
    displacements = []

    FOR y IN range(tile_size//2, height - tile_size//2, tile_size):
        FOR x IN range(tile_size//2, width - tile_size//2, tile_size):

            # Extract tile from reference
            ref_tile = ref_gray[y-tile_size//2 : y+tile_size//2,
                                x-tile_size//2 : x+tile_size//2]

            # Search window in frame (larger than tile)
            search_margin = tile_size // 2
            frame_region = frame_gray[
                y - tile_size//2 - search_margin : y + tile_size//2 + search_margin,
                x - tile_size//2 - search_margin : x + tile_size//2 + search_margin
            ]

            # Find best match (sub-pixel)
            dx, dy = match_tile(ref_tile, frame_region)

            # Store displacement
            grid_points.append((x, y))
            displacements.append((dx, dy))

    # Interpolate displacements across full image
    # Create smooth warp field
    warp_field = interpolate_displacements(
        grid_points,
        displacements,
        image_size=(width, height)
    )

    # Apply warp
    warped = apply_warp_field(frame, warp_field)

    RETURN warped
```

### Tile Matching

```
FUNCTION match_tile(template, search_region):
    """
    Find sub-pixel offset of template within search region.
    """

    # Method 1: Normalized cross-correlation (robust)
    result = cv2.matchTemplate(search_region, template, cv2.TM_CCOEFF_NORMED)
    _, _, _, max_loc = cv2.minMaxLoc(result)

    # Sub-pixel refinement via parabolic fit
    x, y = max_loc
    dx, dy = subpixel_refine(result, x, y)

    RETURN (dx, dy)

    # Method 2: Optical flow (alternative)
    # flow = cv2.calcOpticalFlowPyrLK(...)
```

### Warp Field Interpolation

```
FUNCTION interpolate_displacements(points, displacements, image_size):
    """
    Create smooth displacement field from sparse measurements.
    """

    # Thin-plate spline interpolation (smooth, handles sparse data)
    # Or bilinear/bicubic interpolation (faster)

    dx_map = interpolate_2d(points, [d[0] for d in displacements], image_size)
    dy_map = interpolate_2d(points, [d[1] for d in displacements], image_size)

    RETURN (dx_map, dy_map)


FUNCTION apply_warp_field(image, warp_field):
    """
    Apply per-pixel displacement.
    """
    dx_map, dy_map = warp_field

    # cv2.remap does exactly this
    map_x = base_x_coords + dx_map
    map_y = base_y_coords + dy_map

    warped = cv2.remap(image, map_x, map_y, cv2.INTER_LANCZOS4)

    RETURN warped
```

### Tile Alignment Visualization

```
Reference Frame:                  Frame to Align:
┌─────────────────────────┐       ┌─────────────────────────┐
│     ┌───┐               │       │       ┌───┐             │
│     │ A │    ┌───┐      │       │       │ A'│  ┌───┐      │
│     └───┘    │ B │      │       │       └───┘  │ B'│      │
│  ┌───┐       └───┘      │       │    ┌───┐     └───┘      │
│  │ C │  ○ Planet        │       │    │ C'│  ○ Planet      │
│  └───┘    ┌───┐         │       │    └───┘      ┌───┐     │
│           │ D │         │       │               │ D'│     │
│           └───┘         │       │               └───┘     │
└─────────────────────────┘       └─────────────────────────┘

Each tile (A,B,C,D) finds its own offset.
Atmospheric turbulence shifts them differently.
Interpolation creates smooth warp field.
```

---

## Pass 4: Stacking

### Weighted Stacking with Outlier Rejection

```
INPUT:  aligned_frames[], quality_scores[]
OUTPUT: stacked_image

FUNCTION stack_frames(frames, scores):

    n_frames = len(frames)
    height, width, channels = frames[0].shape

    # Normalize scores to weights (sum = 1)
    weights = normalize_to_sum_one(scores)

    # Stack as 3D array: (n_frames, height, width, channels)
    stack = np.array(frames, dtype=np.float32)

    # Method 1: Simple weighted mean
    # result = np.average(stack, axis=0, weights=weights)

    # Method 2: Sigma-clipped weighted mean (better)
    result = sigma_clipped_stack(stack, weights, sigma=2.5)

    RETURN result.astype(np.uint8)
```

### Sigma Clipping

```
FUNCTION sigma_clipped_stack(stack, weights, sigma=2.5, iterations=2):
    """
    Reject outlier pixels before averaging.
    Removes satellite trails, hot pixels, cosmic rays.
    """

    FOR iteration IN range(iterations):

        # Compute weighted mean and std per pixel
        mean = np.average(stack, axis=0, weights=weights)
        std = weighted_std(stack, weights, mean)

        # Create mask: reject pixels > sigma*std from mean
        lower = mean - sigma * std
        upper = mean + sigma * std

        mask = (stack >= lower) & (stack <= upper)

        # Zero out rejected pixels' weights
        masked_weights = weights[:, None, None, None] * mask

    # Final weighted average with mask
    result = np.sum(stack * masked_weights, axis=0) / np.sum(masked_weights, axis=0)

    # Handle division by zero (all pixels rejected)
    result = np.nan_to_num(result, nan=mean)

    RETURN result
```

### Memory-Efficient Stacking (For Mobile)

```
FUNCTION stack_frames_chunked(frame_paths, scores, chunk_size=20):
    """
    Process in chunks to avoid loading all frames into RAM.
    """

    # Initialize accumulators
    sum_weighted = None
    sum_weights = 0

    FOR chunk_start IN range(0, len(frame_paths), chunk_size):
        chunk_end = min(chunk_start + chunk_size, len(frame_paths))

        # Load this chunk
        chunk_frames = [load_frame(p) for p in frame_paths[chunk_start:chunk_end]]
        chunk_weights = scores[chunk_start:chunk_end]

        # Accumulate
        FOR frame, weight IN zip(chunk_frames, chunk_weights):
            IF sum_weighted IS None:
                sum_weighted = frame.astype(np.float64) * weight
            ELSE:
                sum_weighted += frame.astype(np.float64) * weight
            sum_weights += weight

        # Free memory
        del chunk_frames

    result = (sum_weighted / sum_weights).astype(np.uint8)
    RETURN result
```

**Why Chunked Processing:**
- 500 frames × 4K resolution × 3 channels × 4 bytes = ~12GB RAM (impossible on mobile)
- Processing in chunks of 20 frames keeps peak RAM under 500MB
- Slightly slower but enables processing of arbitrarily large frame counts

---

## Pass 5: Wavelet Sharpening

The "Registax sliders" everyone loves. Each layer controls a different detail size.

### Multi-Scale Wavelet Sharpening

```
INPUT:  stacked_image, layer_strengths[6]
OUTPUT: sharpened_image

FUNCTION wavelet_sharpen(image, strengths):
    """
    À trous wavelet decomposition + selective enhancement.

    Layer 0: Finest details (1-2 pixel features) - noise lives here
    Layer 1: Fine details (2-4 pixels) - planetary texture
    Layer 2: Medium details (4-8 pixels) - cloud bands
    Layer 3: Coarse details (8-16 pixels) - major features
    Layer 4: Very coarse (16-32 pixels) - limb, large shadows
    Layer 5: Residual (base brightness)
    """

    n_layers = len(strengths)

    # Decompose into wavelet layers
    layers = atrous_decompose(image, n_layers)

    # Enhance each layer according to strength
    enhanced_layers = []
    FOR i, (layer, strength) IN enumerate(zip(layers, strengths)):

        IF i == n_layers - 1:
            # Residual layer: don't sharpen, just keep
            enhanced_layers.append(layer)
        ELSE:
            # Detail layer: apply strength
            # strength = 1.0 means no change
            # strength = 2.0 means double the detail
            # strength = 0.5 means reduce detail
            enhanced = layer * strength
            enhanced_layers.append(enhanced)

    # Reconstruct
    result = sum(enhanced_layers)

    # Clip to valid range
    result = np.clip(result, 0, 255)

    RETURN result.astype(np.uint8)
```

### À Trous Wavelet Decomposition

```
FUNCTION atrous_decompose(image, n_layers):
    """
    À trous ("with holes") wavelet decomposition.
    Uses dilated convolution kernels.
    """

    # B3 spline kernel (classic choice)
    kernel_1d = [1/16, 4/16, 6/16, 4/16, 1/16]

    layers = []
    current = image.astype(np.float32)

    FOR scale IN range(n_layers - 1):

        # Create dilated kernel for this scale
        dilation = 2 ** scale
        dilated_kernel = dilate_kernel(kernel_1d, dilation)

        # Smooth (low-pass)
        smoothed = separable_convolve(current, dilated_kernel)

        # Detail = current - smoothed (band-pass)
        detail = current - smoothed

        layers.append(detail)
        current = smoothed

    # Final layer is the residual (low-pass)
    layers.append(current)

    RETURN layers
```

### Kernel Dilation

```
FUNCTION dilate_kernel(kernel_1d, dilation):
    """
    Insert zeros between kernel elements.
    dilation=1: [a, b, c]
    dilation=2: [a, 0, b, 0, c]
    dilation=4: [a, 0, 0, 0, b, 0, 0, 0, c]
    """
    IF dilation == 1:
        RETURN kernel_1d

    dilated = []
    FOR i, val IN enumerate(kernel_1d):
        dilated.append(val)
        IF i < len(kernel_1d) - 1:
            dilated.extend([0] * (dilation - 1))

    RETURN dilated
```

### Wavelet Layers Visualized

```
Original Stacked Image
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│ Layer 0 (finest)     [━━━━━░░░░░░░░░░░░] strength: 0.8  │  ◄─ Reduce (has noise)
│ Layer 1 (fine)       [━━━━━━━━━━░░░░░░░] strength: 1.5  │  ◄─ Boost (texture)
│ Layer 2 (medium)     [━━━━━━━━━━━━░░░░░] strength: 2.0  │  ◄─ Boost (cloud bands)
│ Layer 3 (coarse)     [━━━━━━━━━━━░░░░░░] strength: 1.8  │  ◄─ Boost (features)
│ Layer 4 (v. coarse)  [━━━━━━━░░░░░░░░░░] strength: 1.2  │  ◄─ Slight boost
│ Layer 5 (residual)   [━━━━━━━━━━━━━━━━━] strength: 1.0  │  ◄─ Keep as-is
└─────────────────────────────────────────────────────────┘
         │
         ▼
    Sharpened Result
```

**Why À Trous Wavelets:**
- Translation-invariant (no artifacts from pixel alignment)
- Fast (separable convolution, no complex transforms)
- Intuitive (each layer = specific detail size)
- Proven in Registax/AutoStakkert for 20+ years

---

## Complete Pipeline

### Full Processing Function

```
FUNCTION process_planetary_video(video_path, params):

    # ═══════════════════════════════════════════════════
    # PASS 1: Analyze (Progress: 0-20%)
    # ═══════════════════════════════════════════════════
    emit_progress(0, "Analyzing frames...")

    frame_scores = analyze_video(video_path)

    emit_progress(20, f"Analyzed {len(frame_scores)} frames")

    # ═══════════════════════════════════════════════════
    # PASS 2: Select (Progress: 20-25%)
    # ═══════════════════════════════════════════════════
    emit_progress(20, "Selecting best frames...")

    selected = select_frames(
        frame_scores,
        keep_pct=params.keep_percentage
    )

    emit_progress(25, f"Selected {len(selected)} frames")

    # ═══════════════════════════════════════════════════
    # PASS 3A: Global Alignment (Progress: 25-50%)
    # ═══════════════════════════════════════════════════
    emit_progress(25, "Aligning frames (global)...")

    # Use highest quality frame as reference
    reference_idx = selected[0].index
    reference_frame = decode_frame(video_path, reference_idx)

    globally_aligned = []
    FOR i, entry IN enumerate(selected):
        frame = decode_frame(video_path, entry.index)
        aligned = global_align_single(reference_frame, frame)
        globally_aligned.append(aligned)

        emit_progress(25 + (i / len(selected)) * 25)

    # ═══════════════════════════════════════════════════
    # PASS 3B: Local Alignment (Progress: 50-75%)
    # ═══════════════════════════════════════════════════
    IF params.local_align:
        emit_progress(50, "Aligning frames (local)...")

        locally_aligned = []
        FOR i, frame IN enumerate(globally_aligned):
            warped = local_align(reference_frame, frame, tile_size=32)
            locally_aligned.append(warped)

            emit_progress(50 + (i / len(globally_aligned)) * 25)

        frames_to_stack = locally_aligned
    ELSE:
        frames_to_stack = globally_aligned

    emit_progress(75, "Alignment complete")

    # ═══════════════════════════════════════════════════
    # PASS 4: Stack (Progress: 75-90%)
    # ═══════════════════════════════════════════════════
    emit_progress(75, "Stacking frames...")

    quality_weights = [s.score for s in selected]
    stacked = stack_frames(frames_to_stack, quality_weights)

    emit_progress(90, "Stacking complete")

    # ═══════════════════════════════════════════════════
    # PASS 5: Sharpen (Progress: 90-100%)
    # ═══════════════════════════════════════════════════
    emit_progress(90, "Sharpening...")

    sharpened = wavelet_sharpen(stacked, params.wavelet_strengths)

    emit_progress(100, "Complete!")

    RETURN {
        raw_stack: stacked,
        sharpened: sharpened,
        frames_used: len(selected),
        quality_graph: frame_scores
    }
```

---

## User Interface Parameters

### Stacking Settings

```
┌─────────────────────────────────────────────────────────┐
│  STACKING SETTINGS                                      │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Frames to use:  [━━━━━━━○━━━━━━━━━] 25%               │
│                  ▲                                      │
│                  More frames = smoother but softer      │
│                  Fewer frames = sharper but noisier     │
│                                                         │
│  ☑ Local alignment (slower, better for large planets)  │
│                                                         │
│  Tile size:      ○ Small (16px) - turbulent conditions │
│                  ● Medium (32px) - default              │
│                  ○ Large (64px) - stable conditions     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Sharpening Controls

```
┌─────────────────────────────────────────────────────────┐
│  SHARPENING (adjust after preview)                      │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Layer 1 (fine):    [━━━━━━━━○━━━━] 1.5x               │
│  Layer 2 (medium):  [━━━━━━━━━━○━━] 2.0x               │
│  Layer 3 (coarse):  [━━━━━━━━━○━━━] 1.8x               │
│  Layer 4 (v.coarse):[━━━━━━○━━━━━━] 1.2x               │
│                                                         │
│  [Preview] [Reset] [Apply]                              │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Default Parameter Sets

| Planet Type | Keep % | Local Align | Tile Size | Sharpen Preset |
|-------------|--------|-------------|-----------|----------------|
| Jupiter/Saturn | 25% | Yes | 32px | Aggressive |
| Mars | 30% | Yes | 24px | Moderate |
| Moon | 15% | Yes | 48px | Conservative |
| Sun | 20% | Yes | 32px | Solar |

---

## Next Steps

This pseudocode covers the complete mathematical pipeline. From here we can proceed to:

1. **C++ Implementation** - Actual OpenCV code for Android NDK
   - Frame decoding with FFmpeg/MediaCodec
   - OpenCV-based processing pipeline
   - Multi-threading strategy
   - Memory management

2. **Flutter UI Design** - The screens, controls, progress display
   - Video selection and preview
   - Processing progress visualization
   - Interactive wavelet controls
   - Before/after comparison

3. **Derotation (WinJUPOS-style)** - For long videos where Jupiter/Saturn rotates
   - Ephemeris calculation
   - Per-frame rotation compensation
   - Great Red Spot tracking

4. **Performance Optimization**
   - SIMD vectorization (ARM NEON)
   - Multi-threaded processing
   - GPU acceleration (Vulkan compute shaders)
   - Thermal throttling management

---

## References and Prior Art

- **AutoStakkert!3** - Emil Kraaikamp's tile-based alignment approach
- **Registax 6** - Cor Berrevoets' wavelet sharpening
- **WinJUPOS** - Grischa Hahn's derotation techniques
- **PyStacker** - Open-source Python implementation
- **PIPP** - Pre-processing for planetary imaging

---

## License Considerations

All algorithms described here are well-established in the planetary imaging community and have been described in academic literature and open-source implementations. This specification draws on:

- Phase correlation (public domain algorithm, 1970s)
- À trous wavelet decomposition (Starck et al., 1998)
- Lucky imaging technique (Fried, 1978; Law et al., 2006)

No proprietary AutoStakkert or Registax code is referenced - only the publicly documented algorithmic approaches.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-11
**Status**: Design specification ready for implementation
