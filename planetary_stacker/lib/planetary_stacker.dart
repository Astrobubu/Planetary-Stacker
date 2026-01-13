/// Planetary Stacker - Main Dart API
///
/// High-performance planetary image stacking for mobile devices
library planetary_stacker;

import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// Export the main classes
export 'src/processing_params.dart';
export 'src/frame_analysis.dart';
export 'src/stacker.dart';

/// Get the library version
String getVersion() {
  // TODO: Call native function once FFI bindings are generated
  return '0.1.0';
}

/// Load the native library
ffi.DynamicLibrary _loadLibrary() {
  if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('libplanetary_stacker.so');
  } else if (Platform.isIOS || Platform.isMacOS) {
    return ffi.DynamicLibrary.open('planetary_stacker.framework/planetary_stacker');
  } else if (Platform.isLinux) {
    return ffi.DynamicLibrary.open('libplanetary_stacker.so');
  } else if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('planetary_stacker.dll');
  } else {
    throw UnsupportedError('Platform not supported: ${Platform.operatingSystem}');
  }
}

/// Global reference to the native library
final ffi.DynamicLibrary nativeLib = _loadLibrary();
