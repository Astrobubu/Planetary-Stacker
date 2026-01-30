import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:planetary_stacker/planetary_stacker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Planetary Stacker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF818CF8),
          surface: Color(0xFF18181B),
          background: Color(0xFF09090B),
        ),
        scaffoldBackgroundColor: const Color(0xFF09090B),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xFF6366F1),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF6366F1)),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFF6366F1),
          inactiveTrackColor: Colors.grey[700],
          thumbColor: Colors.white,
          overlayColor: const Color(0xFF6366F1).withOpacity(0.2),
          valueIndicatorColor: const Color(0xFF6366F1),
          valueIndicatorTextStyle: const TextStyle(color: Colors.white),
        ),
        useMaterial3: true,
      ),
      home: const StackerApp(),
    );
  }
}

class StackerApp extends StatefulWidget {
  const StackerApp({super.key});

  @override
  State<StackerApp> createState() => _StackerAppState();
}

class _StackerAppState extends State<StackerApp> {
  int _currentStep = 0;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    // Request all needed permissions upfront
    // Android 13+ uses granular media permissions
    // Older Android uses storage permission

    Map<Permission, PermissionStatus> statuses = {};

    // Try Android 13+ permissions first
    if (await Permission.photos.status.isDenied) {
      statuses.addAll(await [
        Permission.photos,
        Permission.videos,
      ].request());
    }

    // Also request storage for older Android versions
    if (await Permission.storage.status.isDenied) {
      final storageStatus = await Permission.storage.request();
      statuses[Permission.storage] = storageStatus;
    }

    // Check if we have at least one permission
    final hasPermission = statuses.values.any((s) => s.isGranted) ||
        await Permission.photos.isGranted ||
        await Permission.videos.isGranted ||
        await Permission.storage.isGranted;

    setState(() {
      _permissionsGranted = hasPermission;
    });

    // If still denied, open app settings
    if (!hasPermission) {
      final shouldOpen = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permissions Required'),
          content: const Text('This app needs access to your videos and photos to process planetary images. Please grant permissions in Settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (shouldOpen == true) {
        await openAppSettings();
      }
    }
  }

  // Step 1: Video
  String? _videoPath;
  String? _videoName;
  VideoInfo? _videoInfo;
  String? _previewFramePath;

  // Step 2: Frame Selection
  AnalysisResult? _analysisResult;
  double _selectBestPercent = 50.0;
  int _rangeStart = 0;
  int _rangeEnd = 100;
  bool _usePercentMode = true;

  // Step 3: Alignment
  Offset? _alignmentPoint;
  int _alignmentBoxSize = 128;
  List<AlignmentResult>? _trackingTestResults;
  List<String>? _trackingFramePaths;
  int _trackingPreviewIndex = 0;
  bool _trackingTestPassed = false;

  // Step 4: Stacking
  String? _stackedImagePath;
  double _upscaleFactor = 1.0; // 1.0, 1.5, 2.0, 3.0

  // Step 5: Sharpening
  List<double> _waveletStrengths = [0.8, 1.5, 2.0, 1.8, 1.2];
  String? _finalImagePath;
  Timer? _sharpenDebounce;

  // Processing state
  bool _isProcessing = false;
  bool _isCancelled = false;
  int _progress = 0;
  String _statusMessage = '';

  final _stacker = PlanetaryStacker();

  // Zoom controller for image preview
  final TransformationController _transformController = TransformationController();

  @override
  void dispose() {
    _sharpenDebounce?.cancel();
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181B),
        title: const Text('Planetary Stacker', style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          if (_isProcessing)
            TextButton.icon(
              onPressed: () => setState(() => _isCancelled = true),
              icon: const Icon(Icons.cancel, color: Colors.redAccent),
              label: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Start Over',
            onPressed: _isProcessing ? null : _resetAll,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
          Expanded(
            child: _isProcessing ? _buildProcessingView() : _buildCurrentStep(),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['Video', 'Frames', 'Align', 'Stack', 'Sharpen'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      color: const Color(0xFF18181B),
      child: Row(
        children: List.generate(steps.length, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;
          final isEnabled = index <= _currentStep;

          return Expanded(
            child: GestureDetector(
              onTap: isEnabled && !_isProcessing ? () => setState(() => _currentStep = index) : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? const Color(0xFF6366F1)
                          : isCompleted
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF3F3F46),
                    ),
                    child: Center(
                      child: isCompleted
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: isActive ? Colors.white : Colors.grey[400],
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    steps[index],
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive ? Colors.white : Colors.grey[500],
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildVideoStep();
      case 1:
        return _buildFrameSelectionStep();
      case 2:
        return _buildAlignmentStep();
      case 3:
        return _buildStackingStep();
      case 4:
        return _buildSharpeningStep();
      default:
        return const SizedBox();
    }
  }

  // ============ STEP 1: VIDEO ============
  Widget _buildVideoStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Select Video', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Choose a planetary video captured through your telescope',
              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          const SizedBox(height: 20),

          if (_videoPath == null)
            _buildPrimaryButton(
              icon: Icons.video_library,
              label: 'Select Video File',
              onPressed: _pickVideo,
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF22C55E), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _videoName ?? 'Video selected',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (_videoInfo != null) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow('Resolution', '${_videoInfo!.width} x ${_videoInfo!.height}'),
                    _buildInfoRow('Frames', '${_videoInfo!.frameCount}'),
                    _buildInfoRow('FPS', '${_videoInfo!.frameRate.toStringAsFixed(1)}'),
                    _buildInfoRow('Duration', '${(_videoInfo!.durationMs / 1000).toStringAsFixed(1)}s'),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _pickVideo,
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Change Video'),
                    ),
                  ),
                ],
              ),
            ),
            if (_previewFramePath != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(_previewFramePath!), fit: BoxFit.contain, height: 180),
              ),
            ],
          ],

          const SizedBox(height: 24),

          if (_videoPath != null)
            _buildPrimaryButton(
              icon: Icons.arrow_forward,
              label: 'Next: Analyze Frames',
              onPressed: () => _goToStep(1),
            ),
        ],
      ),
    );
  }

  // ============ STEP 2: FRAME SELECTION ============
  Widget _buildFrameSelectionStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Frame Selection', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Analyze and select the sharpest frames', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          const SizedBox(height: 20),

          if (_analysisResult == null)
            _buildPrimaryButton(
              icon: Icons.analytics,
              label: 'Analyze Video Quality',
              onPressed: _analyzeVideo,
            )
          else ...[
            // Results summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 20),
                      const SizedBox(width: 8),
                      Text('${_analysisResult!.scores.length} frames analyzed',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow('Best', _analysisResult!.stats.max.toStringAsFixed(3)),
                  _buildInfoRow('Average', _analysisResult!.stats.mean.toStringAsFixed(3)),
                  _buildInfoRow('Worst', _analysisResult!.stats.min.toStringAsFixed(3)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Selection mode
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Selection Mode', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildModeButton('Best %', _usePercentMode, () => setState(() => _usePercentMode = true))),
                      const SizedBox(width: 8),
                      Expanded(child: _buildModeButton('Range', !_usePercentMode, () => setState(() => _usePercentMode = false))),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_usePercentMode) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Use best frames:'),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text('${_selectBestPercent.round()}%',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    Slider(
                      value: _selectBestPercent,
                      min: 10,
                      max: 100,
                      divisions: 18,
                      onChanged: (v) => setState(() => _selectBestPercent = v),
                    ),
                    Text('${_getSelectedFrameCount()} frames will be stacked',
                        style: TextStyle(color: Colors.grey[400])),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Frame range:'),
                        Text('$_rangeStart - $_rangeEnd',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6366F1))),
                      ],
                    ),
                    RangeSlider(
                      values: RangeValues(_rangeStart.toDouble(), _rangeEnd.toDouble()),
                      min: 0,
                      max: (_analysisResult?.totalFrames ?? 100).toDouble(),
                      divisions: _analysisResult?.totalFrames ?? 100,
                      onChanged: (v) => setState(() {
                        _rangeStart = v.start.round();
                        _rangeEnd = v.end.round();
                      }),
                    ),
                    Text('${_rangeEnd - _rangeStart} frames selected', style: TextStyle(color: Colors.grey[400])),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Histogram
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Quality Distribution', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 60,
                    child: CustomPaint(
                      size: const Size(double.infinity, 60),
                      painter: QualityHistogramPainter(
                        scores: _analysisResult!.scores.map((s) => s.qualityScore).toList(),
                        selectedPercent: _usePercentMode ? _selectBestPercent / 100 : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          if (_analysisResult != null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _goToStep(0),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _buildPrimaryButton(
                    icon: Icons.arrow_forward,
                    label: 'Next: Alignment',
                    onPressed: () => _goToStep(2),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ============ STEP 3: ALIGNMENT ============
  Widget _buildAlignmentStep() {
    final hasTrackingResults = _trackingTestResults != null && _trackingFramePaths != null;

    return Column(
      children: [
        // Image preview with tracking box - takes most of screen
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onTapDown: !hasTrackingResults ? (details) {
                      setState(() => _alignmentPoint = details.localPosition);
                    } : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Show current tracking frame or preview
                        if (hasTrackingResults && _trackingFramePaths!.isNotEmpty)
                          InteractiveViewer(
                            transformationController: _transformController,
                            minScale: 0.5,
                            maxScale: 5.0,
                            child: Image.file(
                              File(_trackingFramePaths![_trackingPreviewIndex]),
                              fit: BoxFit.contain,
                              key: ValueKey(_trackingFramePaths![_trackingPreviewIndex]),
                              gaplessPlayback: true,
                              cacheWidth: null,
                              cacheHeight: null,
                            ),
                          )
                        else if (_previewFramePath != null)
                          InteractiveViewer(
                            transformationController: _transformController,
                            minScale: 0.5,
                            maxScale: 5.0,
                            child: Image.file(
                              File(_previewFramePath!),
                              fit: BoxFit.contain,
                            ),
                          ),

                        // Alignment point selection box (before tracking)
                        if (!hasTrackingResults && _alignmentPoint != null)
                          Positioned(
                            left: _alignmentPoint!.dx - _alignmentBoxSize / 2,
                            top: _alignmentPoint!.dy - _alignmentBoxSize / 2,
                            child: Container(
                              width: _alignmentBoxSize.toDouble(),
                              height: _alignmentBoxSize.toDouble(),
                              decoration: BoxDecoration(
                                border: Border.all(color: const Color(0xFF22C55E), width: 2),
                                color: const Color(0xFF22C55E).withOpacity(0.15),
                              ),
                              child: const Center(
                                child: Icon(Icons.add, color: Color(0xFF22C55E), size: 32),
                              ),
                            ),
                          ),

                        // Tracked position box (after tracking) - FIXED position since frames are aligned
                        if (hasTrackingResults && _alignmentPoint != null && _trackingPreviewIndex < _trackingTestResults!.length)
                          Builder(builder: (context) {
                            final result = _trackingTestResults![_trackingPreviewIndex];
                            // Box stays at ORIGINAL position - the FRAME is shifted to keep object here
                            return Positioned(
                              left: _alignmentPoint!.dx - _alignmentBoxSize / 2,
                              top: _alignmentPoint!.dy - _alignmentBoxSize / 2,
                              child: Container(
                                width: _alignmentBoxSize.toDouble(),
                                height: _alignmentBoxSize.toDouble(),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: result.confidence > 0.1 ? const Color(0xFF22C55E) : Colors.orange,
                                    width: 2,
                                  ),
                                  color: (result.confidence > 0.1 ? const Color(0xFF22C55E) : Colors.orange).withOpacity(0.15),
                                ),
                                child: Center(
                                  child: Icon(
                                    result.confidence > 0.1 ? Icons.check : Icons.warning,
                                    color: result.confidence > 0.1 ? const Color(0xFF22C55E) : Colors.orange,
                                    size: 28,
                                  ),
                                ),
                              ),
                            );
                          }),

                        // Instructions overlay
                        Positioned(
                          top: 8,
                          left: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  hasTrackingResults ? Icons.check_circle : Icons.touch_app,
                                  size: 16,
                                  color: hasTrackingResults ? const Color(0xFF22C55E) : Colors.white70,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    hasTrackingResults
                                        ? 'Frame ${_trackingPreviewIndex + 1}/${_trackingFramePaths!.length} - Planet should stay centered'
                                        : _alignmentPoint == null
                                            ? 'Tap on the planet to set tracking region'
                                            : 'Region set - tap Test Tracking',
                                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                                  ),
                                ),
                                if (hasTrackingResults) ...[
                                  Text(
                                    'Corrected: ${_trackingTestResults![_trackingPreviewIndex].shiftX.toStringAsFixed(1)}, ${_trackingTestResults![_trackingPreviewIndex].shiftY.toStringAsFixed(1)}px',
                                    style: const TextStyle(fontSize: 10, color: Colors.white54, fontFamily: 'monospace'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // Zoom reset button
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.zoom_out_map, color: Colors.white70),
                            onPressed: () => _transformController.value = Matrix4.identity(),
                            tooltip: 'Reset zoom',
                            style: IconButton.styleFrom(backgroundColor: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // Controls at bottom
        Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Frame slider (only when tracking results exist)
              if (hasTrackingResults) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            _trackingTestPassed ? Icons.check_circle : Icons.warning,
                            color: _trackingTestPassed ? const Color(0xFF22C55E) : Colors.orange,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _trackingTestPassed ? 'Tracking OK' : 'Check tracking',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _trackingTestPassed ? const Color(0xFF22C55E) : Colors.orange,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => setState(() {
                              _trackingTestResults = null;
                              _trackingFramePaths = null;
                              _trackingPreviewIndex = 0;
                            }),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Reset'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.grey[400],
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('Frame:', style: TextStyle(fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: _trackingPreviewIndex.toDouble(),
                              min: 0,
                              max: (_trackingFramePaths!.length - 1).toDouble(),
                              divisions: _trackingFramePaths!.length - 1,
                              onChanged: (v) => setState(() => _trackingPreviewIndex = v.round()),
                            ),
                          ),
                          SizedBox(
                            width: 40,
                            child: Text(
                              '${_trackingPreviewIndex + 1}/${_trackingFramePaths!.length}',
                              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Box size selector (only before tracking)
              if (!hasTrackingResults) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Text('Box Size:', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 12),
                      ...[64, 128, 256].map((size) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text('$size', style: const TextStyle(fontSize: 12)),
                              selected: _alignmentBoxSize == size,
                              onSelected: (v) => setState(() => _alignmentBoxSize = size),
                              selectedColor: const Color(0xFF6366F1),
                              visualDensity: VisualDensity.compact,
                            ),
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _goToStep(1),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!hasTrackingResults)
                    Expanded(
                      flex: 2,
                      child: _buildPrimaryButton(
                        icon: Icons.track_changes,
                        label: 'Test Tracking',
                        onPressed: _alignmentPoint != null ? _testTracking : null,
                      ),
                    )
                  else
                    Expanded(
                      flex: 2,
                      child: _buildPrimaryButton(
                        icon: Icons.arrow_forward,
                        label: 'Next: Stack',
                        onPressed: () => _goToStep(3),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============ STEP 4: STACKING ============
  Widget _buildStackingStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Stack Frames', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Align and combine selected frames', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
          const SizedBox(height: 16),

          // Settings
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Settings', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _buildInfoRow('Frames', '${_getSelectedFrameCount()}'),
                _buildInfoRow('Method', 'Sigma-clipped average'),
                const SizedBox(height: 12),
                const Text('Output Scale (Drizzle)', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Row(
                  children: [1.0, 1.5, 2.0, 3.0].map((scale) {
                    final isSelected = _upscaleFactor == scale;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: ChoiceChip(
                          label: Text('${scale}x'),
                          selected: isSelected,
                          onSelected: (v) => setState(() => _upscaleFactor = scale),
                          selectedColor: const Color(0xFF6366F1),
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey[300],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (_stackedImagePath == null)
            _buildPrimaryButton(
              icon: Icons.layers,
              label: 'Start Stacking',
              onPressed: _runStacking,
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF22C55E)),
              ),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 20),
                      SizedBox(width: 8),
                      Text('Stacking Complete!', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(_stackedImagePath!), fit: BoxFit.contain, height: 180),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: () => _goToStep(2), child: const Text('Back'))),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildPrimaryButton(
                  icon: Icons.arrow_forward,
                  label: 'Next: Sharpen',
                  onPressed: _stackedImagePath != null ? () => _goToStep(4) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============ STEP 5: SHARPENING ============
  Widget _buildSharpeningStep() {
    return Column(
      children: [
        // Zoomable image at top
        Expanded(
          flex: 2,
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF18181B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  if (_stackedImagePath != null)
                    InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 0.5,
                      maxScale: 8.0,
                      child: Image.file(
                        File(_finalImagePath ?? _stackedImagePath!),
                        fit: BoxFit.contain,
                        key: ValueKey(_finalImagePath ?? _stackedImagePath),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.pinch, size: 14, color: Colors.white70),
                          SizedBox(width: 4),
                          Text('Pinch to zoom', style: TextStyle(fontSize: 11, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: IconButton(
                      icon: const Icon(Icons.zoom_out_map, color: Colors.white70),
                      onPressed: () => _transformController.value = Matrix4.identity(),
                      tooltip: 'Reset zoom',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Controls at bottom
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Presets
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Presets', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildPresetChip('None', [1.0, 1.0, 1.0, 1.0, 1.0]),
                          _buildPresetChip('Light', [0.5, 1.2, 1.5, 1.3, 1.0]),
                          _buildPresetChip('Medium', [0.8, 1.5, 2.0, 1.8, 1.2]),
                          _buildPresetChip('Strong', [0.6, 2.0, 2.5, 2.2, 1.5]),
                          _buildPresetChip('Jupiter', [0.7, 1.8, 2.2, 1.8, 1.3]),
                          _buildPresetChip('Moon', [0.6, 1.3, 1.8, 1.5, 1.2]),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Layer sliders
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Wavelet Layers', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Release slider to update preview', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                      const SizedBox(height: 8),
                      ...List.generate(5, (i) => _buildWaveletSlider(i)),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Export buttons
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Export', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _saveToGallery,
                              icon: const Icon(Icons.photo_library, size: 18),
                              label: const Text('Gallery'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF22C55E),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _saveResult,
                              icon: const Icon(Icons.save_alt, size: 18),
                              label: const Text('Files'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _shareResult,
                              icon: const Icon(Icons.share, size: 18),
                              label: const Text('Share'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3B82F6),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => _goToStep(3), child: const Text('Back to Stacking')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaveletSlider(int index) {
    final labels = ['L1 (fine)', 'L2', 'L3', 'L4', 'L5 (coarse)'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 70, child: Text(labels[index], style: const TextStyle(fontSize: 12))),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: _waveletStrengths[index],
                min: 0.0,
                max: 4.0,
                onChanged: (v) => setState(() => _waveletStrengths[index] = v),
                onChangeEnd: (v) => _debouncedSharpen(),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              _waveletStrengths[index].toStringAsFixed(1),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String name, List<double> values) {
    return ActionChip(
      label: Text(name, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        setState(() => _waveletStrengths = List.from(values));
        _debouncedSharpen();
      },
      backgroundColor: const Color(0xFF27272A),
      side: BorderSide.none,
    );
  }

  void _debouncedSharpen() {
    _sharpenDebounce?.cancel();
    _sharpenDebounce = Timer(const Duration(milliseconds: 300), () {
      _applySharpening();
    });
  }

  // ============ PROCESSING VIEW ============
  Widget _buildProcessingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      value: _progress / 100,
                      strokeWidth: 6,
                      backgroundColor: Colors.grey[800],
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                  Text('$_progress%', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(_statusMessage, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => setState(() => _isCancelled = true),
              icon: const Icon(Icons.cancel, color: Colors.redAccent, size: 18),
              label: const Text('Cancel', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
  }

  // ============ HELPER WIDGETS ============
  Widget _buildPrimaryButton({
    required IconData icon,
    required String label,
    VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildModeButton(String label, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? const Color(0xFF6366F1) : Colors.grey[600]!),
        ),
        child: Center(
          child: Text(label, style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }

  // ============ ACTIONS ============
  void _goToStep(int step) => setState(() => _currentStep = step);

  void _resetAll() {
    setState(() {
      _currentStep = 0;
      _videoPath = null;
      _videoName = null;
      _videoInfo = null;
      _previewFramePath = null;
      _analysisResult = null;
      _alignmentPoint = null;
      _trackingTestResults = null;
      _trackingFramePaths = null;
      _trackingPreviewIndex = 0;
      _trackingTestPassed = false;
      _stackedImagePath = null;
      _finalImagePath = null;
      _selectBestPercent = 50.0;
      _upscaleFactor = 1.0;
      _waveletStrengths = [0.8, 1.5, 2.0, 1.8, 1.2];
    });
  }

  int _getSelectedFrameCount() {
    if (_analysisResult == null) return 0;
    if (_usePercentMode) {
      return (_analysisResult!.scores.length * _selectBestPercent / 100).round();
    }
    return _rangeEnd - _rangeStart;
  }

  List<int> _getSelectedFrameIndices() {
    if (_analysisResult == null) return [];

    if (_usePercentMode) {
      // Sort frames by quality and take top percentage
      final sortedScores = List<FrameScore>.from(_analysisResult!.scores);
      sortedScores.sort((a, b) => b.qualityScore.compareTo(a.qualityScore)); // Descending
      final count = (_analysisResult!.scores.length * _selectBestPercent / 100).round();
      return sortedScores.take(count).map((s) => s.frameIndex).toList()..sort();
    } else {
      // Range mode - just return frame indices in range
      return List.generate(_rangeEnd - _rangeStart, (i) => _rangeStart + i);
    }
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video, allowMultiple: false);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _videoPath = result.files.first.path!;
        _videoName = result.files.first.name;
        _analysisResult = null;
        _stackedImagePath = null;
        _finalImagePath = null;
      });
      _loadVideoInfo();
    }
  }

  Future<void> _loadVideoInfo() async {
    if (_videoPath == null) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Loading video...';
      _progress = 0;
    });

    try {
      final extractor = FrameExtractor();
      final info = await extractor.getVideoInfo(_videoPath!);
      final frames = await extractor.extractFrames(videoPath: _videoPath!, frameIndices: [0]);

      setState(() {
        _videoInfo = info;
        _rangeEnd = info.frameCount;
        if (frames.isNotEmpty) _previewFramePath = frames.first;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('Failed to load video: $e');
    }
  }

  Future<void> _analyzeVideo() async {
    if (_videoPath == null) return;
    setState(() {
      _isProcessing = true;
      _isCancelled = false;
      _progress = 0;
      _statusMessage = 'Analyzing frames...';
    });

    try {
      final result = await _stacker.analyzeVideo(
        videoPath: _videoPath!,
        onProgress: (progress, message) {
          if (_isCancelled) return;
          setState(() {
            _progress = progress;
            _statusMessage = message;
          });
        },
      );

      if (!_isCancelled) {
        setState(() {
          _analysisResult = result;
          _isProcessing = false;
        });
      } else {
        setState(() => _isProcessing = false);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('Analysis failed: $e');
    }
  }

  Future<void> _testTracking() async {
    if (_videoPath == null || _alignmentPoint == null || _analysisResult == null) return;

    setState(() {
      _isProcessing = true;
      _isCancelled = false;
      _progress = 0;
      _statusMessage = 'Extracting test frames...';
    });

    try {
      final extractor = FrameExtractor();

      // Use the SELECTED best frames from step 2, not random frames
      final selectedFrames = _getSelectedFrameIndices();

      // Take up to 10 evenly spaced from the selected frames for preview
      final testCount = selectedFrames.length > 10 ? 10 : selectedFrames.length;
      final step = selectedFrames.length ~/ testCount;
      final indices = List.generate(testCount, (i) => selectedFrames[i * step]);

      setState(() {
        _progress = 20;
        _statusMessage = 'Extracting $testCount test frames...';
      });

      final framePaths = await extractor.extractFrames(
        videoPath: _videoPath!,
        frameIndices: indices,
      );

      if (framePaths.length < 2) {
        throw Exception('Not enough frames extracted');
      }

      setState(() {
        _progress = 40;
        _statusMessage = 'Testing phase correlation...';
      });

      // Load frames and test alignment
      final correlator = PhaseCorrelator();
      final referenceFrame = cv.imread(framePaths.first, flags: cv.IMREAD_COLOR);
      final results = <AlignmentResult>[];
      final alignedPaths = <String>[];

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < framePaths.length; i++) {
        final targetFrame = cv.imread(framePaths[i], flags: cv.IMREAD_COLOR);
        final result = await correlator.alignFrame(
          referenceFrame: referenceFrame,
          targetFrame: targetFrame,
        );

        results.add(AlignmentResult(
          alignedFrame: cv.Mat.empty(),
          shiftX: result.shiftX,
          shiftY: result.shiftY,
          confidence: result.confidence,
        ));

        // Save the ALIGNED frame with unique timestamp to avoid caching issues
        final alignedPath = p.join(tempDir.path, 'aligned_${timestamp}_$i.png');
        cv.imwrite(alignedPath, result.alignedFrame);
        alignedPaths.add(alignedPath);

        result.alignedFrame.dispose();
        targetFrame.dispose();

        setState(() {
          _progress = 40 + ((i + 1) * 60 ~/ framePaths.length);
          _statusMessage = 'Aligning frame ${i + 1}/${framePaths.length}...';
        });
      }

      referenceFrame.dispose();

      // Analyze results - check if tracking looks reasonable
      final maxShift = results.fold<double>(0, (max, r) =>
          [max, r.shiftX.abs(), r.shiftY.abs()].reduce((a, b) => a > b ? a : b));
      final avgConfidence = results.fold<double>(0, (sum, r) => sum + r.confidence) / results.length;

      // Tracking is considered good if:
      // - Max shift is less than 50 pixels (reasonable for atmospheric seeing)
      // - Average confidence is above 0.1
      final passed = maxShift < 50 && avgConfidence > 0.1;

      setState(() {
        _trackingTestResults = results;
        _trackingFramePaths = alignedPaths; // Use ALIGNED frames for preview
        _trackingPreviewIndex = 0;
        _trackingTestPassed = passed;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('Tracking test failed: $e');
    }
  }

  Future<void> _runStacking() async {
    if (_videoPath == null || _analysisResult == null) return;

    setState(() {
      _isProcessing = true;
      _isCancelled = false;
      _progress = 0;
      _statusMessage = 'Preparing...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath = p.join(tempDir.path, 'stacked_${DateTime.now().millisecondsSinceEpoch}.png');

      final result = await _stacker.processVideo(
        videoPath: _videoPath!,
        outputPath: outputPath,
        params: ProcessingParams(
          keepPercentage: _usePercentMode ? _selectBestPercent / 100 : 0.5,
          waveletLayers: const WaveletLayers(layer0: 1.0, layer1: 1.0, layer2: 1.0, layer3: 1.0, layer4: 1.0),
        ),
        onProgress: (progress, message) {
          if (_isCancelled) return;
          setState(() {
            _progress = progress;
            _statusMessage = message;
          });
        },
      );

      if (!_isCancelled && result != null) {
        setState(() {
          _stackedImagePath = result;
          _isProcessing = false;
        });
      } else {
        setState(() => _isProcessing = false);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('Stacking failed: $e');
    }
  }

  Future<void> _applySharpening() async {
    if (_stackedImagePath == null) return;

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _statusMessage = 'Sharpening...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final outputPath = p.join(tempDir.path, 'sharp_${DateTime.now().millisecondsSinceEpoch}.png');

      final sharpener = WaveletSharpener();
      final inputImage = cv.imread(_stackedImagePath!, flags: cv.IMREAD_COLOR);

      final sharpened = await sharpener.sharpen(
        image: inputImage,
        layerStrengths: _waveletStrengths,
        onProgress: (progress, message) {
          setState(() {
            _progress = progress;
            _statusMessage = message;
          });
        },
      );

      cv.imwrite(outputPath, sharpened);
      inputImage.dispose();
      sharpened.dispose();

      setState(() {
        _finalImagePath = outputPath;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() => _isProcessing = false);
      _showError('Sharpening failed: $e');
    }
  }

  Future<void> _saveResult() async {
    final imagePath = _finalImagePath ?? _stackedImagePath;
    if (imagePath == null) return;

    try {
      // Read the image bytes
      final bytes = await File(imagePath).readAsBytes();

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Image',
        fileName: 'planetary_${DateTime.now().millisecondsSinceEpoch}.png',
        bytes: bytes,
      );

      if (result != null) {
        _showSuccess('Saved to ${p.basename(result)}');
      }
    } catch (e) {
      _showError('Save failed: $e');
    }
  }

  Future<void> _saveToGallery() async {
    final imagePath = _finalImagePath ?? _stackedImagePath;
    if (imagePath == null) return;

    try {
      // Request storage permission
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) {
          // Try photos permission on newer Android
          status = await Permission.photos.request();
        }
      }

      // Get download/pictures directory
      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Pictures/PlanetaryStacker');
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final outputPath = p.join(dir.path, 'planetary_${DateTime.now().millisecondsSinceEpoch}.png');
      await File(imagePath).copy(outputPath);

      _showSuccess('Saved to Pictures/PlanetaryStacker');
    } catch (e) {
      _showError('Save failed: $e');
    }
  }

  Future<void> _shareResult() async {
    final imagePath = _finalImagePath ?? _stackedImagePath;
    if (imagePath == null) return;

    try {
      await Share.shareXFiles([XFile(imagePath)], text: 'Planetary image');
    } catch (e) {
      _showError('Share failed: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF22C55E)),
    );
  }
}

class QualityHistogramPainter extends CustomPainter {
  final List<double> scores;
  final double? selectedPercent;

  QualityHistogramPainter({required this.scores, this.selectedPercent});

  @override
  void paint(Canvas canvas, Size size) {
    if (scores.isEmpty) return;

    const binCount = 30;
    final bins = List.filled(binCount, 0);
    final minScore = scores.reduce((a, b) => a < b ? a : b);
    final maxScore = scores.reduce((a, b) => a > b ? a : b);
    final range = maxScore - minScore;

    if (range < 0.001) return;

    for (final score in scores) {
      final binIndex = ((score - minScore) / range * (binCount - 1)).round().clamp(0, binCount - 1);
      bins[binIndex]++;
    }

    final maxBin = bins.reduce((a, b) => a > b ? a : b);
    if (maxBin == 0) return;

    final barWidth = size.width / binCount;

    for (int i = 0; i < binCount; i++) {
      final barHeight = (bins[i] / maxBin) * size.height;
      final isSelected = selectedPercent != null && i >= binCount * (1 - selectedPercent!);

      canvas.drawRect(
        Rect.fromLTWH(i * barWidth, size.height - barHeight, barWidth - 1, barHeight),
        Paint()..color = isSelected ? const Color(0xFF22C55E) : const Color(0xFF6366F1).withOpacity(0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class ShiftVisualizerPainter extends CustomPainter {
  final List<AlignmentResult> results;

  ShiftVisualizerPainter({required this.results});

  @override
  void paint(Canvas canvas, Size size) {
    if (results.isEmpty) return;

    // Find max shift for scaling
    double maxShift = 1.0;
    for (final r in results) {
      maxShift = [maxShift, r.shiftX.abs(), r.shiftY.abs()].reduce((a, b) => a > b ? a : b);
    }

    final centerY = size.height / 2;
    final scale = (size.height / 2 - 10) / maxShift;
    final barWidth = size.width / results.length;

    // Draw zero line
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      Paint()
        ..color = Colors.grey[600]!
        ..strokeWidth = 1,
    );

    // Draw bars for each frame
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      final x = i * barWidth + barWidth / 4;
      final halfBarWidth = barWidth / 4 - 2;

      // X shift bar (purple)
      final xHeight = r.shiftX * scale;
      canvas.drawRect(
        Rect.fromLTWH(x, centerY - (xHeight > 0 ? xHeight : 0), halfBarWidth, xHeight.abs()),
        Paint()..color = const Color(0xFF6366F1),
      );

      // Y shift bar (green)
      final yHeight = r.shiftY * scale;
      canvas.drawRect(
        Rect.fromLTWH(x + halfBarWidth + 2, centerY - (yHeight > 0 ? yHeight : 0), halfBarWidth, yHeight.abs()),
        Paint()..color = const Color(0xFF22C55E),
      );
    }

    // Draw scale labels
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.right,
    );

    textPainter.text = TextSpan(
      text: '+${maxShift.toStringAsFixed(0)}px',
      style: TextStyle(color: Colors.grey[500], fontSize: 9),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 2, 2));

    textPainter.text = TextSpan(
      text: '-${maxShift.toStringAsFixed(0)}px',
      style: TextStyle(color: Colors.grey[500], fontSize: 9),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - textPainter.width - 2, size.height - 12));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
