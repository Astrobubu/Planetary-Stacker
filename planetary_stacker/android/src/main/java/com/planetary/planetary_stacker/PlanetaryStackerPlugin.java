package com.planetary.planetary_stacker;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Planetary Stacker Plugin
 *
 * This is a minimal plugin class. All actual processing is done in Dart
 * using opencv_dart and ffmpeg_kit_flutter packages.
 */
public class PlanetaryStackerPlugin implements FlutterPlugin {
    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        // No-op: All processing is done in Dart
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        // No-op
    }
}
