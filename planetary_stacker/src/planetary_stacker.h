/**
 * Planetary Stacker - C API Header
 *
 * This header defines the C API for the planetary stacking library.
 * It provides FFI-compatible functions that can be called from Dart.
 */

#ifndef PLANETARY_STACKER_H
#define PLANETARY_STACKER_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Version Information
// ============================================================================

/**
 * Get the library version string
 */
const char* ps_get_version(void);

// ============================================================================
// Frame Analysis Types
// ============================================================================

typedef struct {
    int32_t frame_index;
    double quality_score;
    int32_t roi_x;
    int32_t roi_y;
    int32_t roi_width;
    int32_t roi_height;
} PSFrameScore;

typedef struct {
    PSFrameScore* scores;
    int32_t count;
    int32_t total_frames;
} PSAnalysisResult;

// ============================================================================
// Processing Parameters
// ============================================================================

typedef struct {
    // Frame selection
    float keep_percentage;        // 0.0 to 1.0 (e.g., 0.25 = top 25%)
    int32_t min_frames;           // Minimum frames to use (default: 50)
    int32_t max_frames;           // Maximum frames to use (default: 500)

    // Alignment
    bool enable_local_align;      // Enable tile-based local alignment
    int32_t tile_size;            // Tile size for local alignment (16, 32, 64)

    // Stacking
    float sigma_clip_threshold;   // Sigma clipping threshold (default: 2.5)
    int32_t sigma_iterations;     // Sigma clipping iterations (default: 2)

    // Sharpening (wavelet layer strengths)
    float wavelet_layer_0;        // Finest details (default: 0.8)
    float wavelet_layer_1;        // Fine details (default: 1.5)
    float wavelet_layer_2;        // Medium details (default: 2.0)
    float wavelet_layer_3;        // Coarse details (default: 1.8)
    float wavelet_layer_4;        // Very coarse (default: 1.2)
} PSProcessingParams;

/**
 * Get default processing parameters
 */
PSProcessingParams ps_get_default_params(void);

// ============================================================================
// Progress Callback
// ============================================================================

/**
 * Progress callback function type
 *
 * @param progress Progress percentage (0-100)
 * @param message Progress message
 * @param user_data User-provided data pointer
 */
typedef void (*PSProgressCallback)(int32_t progress, const char* message, void* user_data);

// ============================================================================
// Frame Analysis Functions
// ============================================================================

/**
 * Analyze video frames for quality
 *
 * @param video_path Path to input video file
 * @param sample_step Analyze every Nth frame (default: 3)
 * @param callback Progress callback (can be NULL)
 * @param user_data User data for callback
 * @return Analysis result (must be freed with ps_free_analysis_result)
 */
PSAnalysisResult* ps_analyze_video(
    const char* video_path,
    int32_t sample_step,
    PSProgressCallback callback,
    void* user_data
);

/**
 * Free analysis result memory
 */
void ps_free_analysis_result(PSAnalysisResult* result);

// ============================================================================
// Full Processing Pipeline
// ============================================================================

/**
 * Process planetary video end-to-end
 *
 * @param video_path Path to input video file
 * @param output_path Path for output image
 * @param params Processing parameters
 * @param callback Progress callback (can be NULL)
 * @param user_data User data for callback
 * @return 0 on success, negative error code on failure
 */
int32_t ps_process_video(
    const char* video_path,
    const char* output_path,
    const PSProcessingParams* params,
    PSProgressCallback callback,
    void* user_data
);

// ============================================================================
// Error Handling
// ============================================================================

/**
 * Get last error message
 */
const char* ps_get_last_error(void);

/**
 * Clear last error
 */
void ps_clear_error(void);

// ============================================================================
// Cleanup
// ============================================================================

/**
 * Free a string returned by the library
 */
void ps_free_string(char* str);

#ifdef __cplusplus
}
#endif

#endif // PLANETARY_STACKER_H
