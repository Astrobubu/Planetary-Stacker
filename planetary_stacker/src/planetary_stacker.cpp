/**
 * Planetary Stacker - C++ Implementation
 *
 * This file implements the C API defined in planetary_stacker.h
 */

#include "planetary_stacker.h"
#include <string>
#include <cstring>
#include <thread>

// Thread-local error storage
thread_local std::string g_last_error;

// ============================================================================
// Version Information
// ============================================================================

const char* ps_get_version() {
    return "0.1.0";
}

// ============================================================================
// Default Parameters
// ============================================================================

PSProcessingParams ps_get_default_params() {
    PSProcessingParams params;

    // Frame selection
    params.keep_percentage = 0.25f;  // Top 25%
    params.min_frames = 50;
    params.max_frames = 500;

    // Alignment
    params.enable_local_align = true;
    params.tile_size = 32;

    // Stacking
    params.sigma_clip_threshold = 2.5f;
    params.sigma_iterations = 2;

    // Sharpening
    params.wavelet_layer_0 = 0.8f;   // Reduce finest (noise)
    params.wavelet_layer_1 = 1.5f;   // Boost fine details
    params.wavelet_layer_2 = 2.0f;   // Boost medium details
    params.wavelet_layer_3 = 1.8f;   // Boost coarse details
    params.wavelet_layer_4 = 1.2f;   // Slight boost very coarse

    return params;
}

// ============================================================================
// Frame Analysis Functions
// ============================================================================

PSAnalysisResult* ps_analyze_video(
    const char* video_path,
    int32_t sample_step,
    PSProgressCallback callback,
    void* user_data
) {
    try {
        // TODO: Implement actual video analysis
        // For now, return a stub result

        if (callback) {
            callback(0, "Starting video analysis...", user_data);
        }

        // Create stub result
        auto* result = new PSAnalysisResult();
        result->total_frames = 1000;  // Example
        result->count = 10;            // Example: 10 analyzed frames
        result->scores = new PSFrameScore[result->count];

        // Fill with example data
        for (int i = 0; i < result->count; ++i) {
            result->scores[i].frame_index = i * sample_step;
            result->scores[i].quality_score = 0.5 + (i * 0.05);  // Example scores
            result->scores[i].roi_x = 100;
            result->scores[i].roi_y = 100;
            result->scores[i].roi_width = 800;
            result->scores[i].roi_height = 600;
        }

        if (callback) {
            callback(100, "Analysis complete", user_data);
        }

        return result;

    } catch (const std::exception& e) {
        g_last_error = std::string("Video analysis failed: ") + e.what();
        return nullptr;
    }
}

void ps_free_analysis_result(PSAnalysisResult* result) {
    if (result) {
        delete[] result->scores;
        delete result;
    }
}

// ============================================================================
// Full Processing Pipeline
// ============================================================================

int32_t ps_process_video(
    const char* video_path,
    const char* output_path,
    const PSProcessingParams* params,
    PSProgressCallback callback,
    void* user_data
) {
    try {
        // TODO: Implement full processing pipeline

        if (callback) {
            callback(0, "Analyzing frames...", user_data);
        }

        // Simulate processing stages
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        if (callback) callback(20, "Analyzed frames", user_data);

        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        if (callback) callback(40, "Selecting best frames...", user_data);

        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        if (callback) callback(60, "Aligning frames...", user_data);

        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        if (callback) callback(80, "Stacking frames...", user_data);

        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        if (callback) callback(90, "Sharpening...", user_data);

        if (callback) callback(100, "Complete!", user_data);

        return 0;  // Success

    } catch (const std::exception& e) {
        g_last_error = std::string("Processing failed: ") + e.what();
        return -1;  // Error
    }
}

// ============================================================================
// Error Handling
// ============================================================================

const char* ps_get_last_error() {
    return g_last_error.c_str();
}

void ps_clear_error() {
    g_last_error.clear();
}

void ps_free_string(char* str) {
    if (str) {
        delete[] str;
    }
}
