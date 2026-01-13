import 'package:flutter/material.dart';
import 'package:planetary_stacker/planetary_stacker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Planetary Stacker',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: Colors.deepPurple,
          secondary: Colors.purpleAccent,
          surface: const Color(0xFF1E1E1E),
          background: const Color(0xFF121212),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final stacker = PlanetaryStacker();

  String? _selectedVideoPath;
  String? _selectedVideoName;
  int _progress = 0;
  String _status = 'Select a planetary video to begin';
  AnalysisResult? _analysisResult;
  bool _isProcessing = false;
  ProcessingParams _selectedPreset = ProcessingParams.forJupiterSaturn();
  String _presetName = 'Jupiter/Saturn';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.nightlight_round, color: Colors.purpleAccent),
            SizedBox(width: 8),
            Text('Planetary Stacker'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Video Selection Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.video_library, color: Colors.purpleAccent, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          'Video Source',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_selectedVideoPath == null)
                      ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _pickVideo,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Select Video File'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.deepPurple,
                        ),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedVideoName ?? 'Video selected',
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _isProcessing ? null : _pickVideo,
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: const Text('Change Video'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.purpleAccent,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Processing Preset Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune, color: Colors.purpleAccent, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          'Processing Preset',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildPresetChip('Jupiter/Saturn', ProcessingParams.forJupiterSaturn()),
                        _buildPresetChip('Mars', ProcessingParams.forMars()),
                        _buildPresetChip('Moon', ProcessingParams.forMoon()),
                        _buildPresetChip('Sun', ProcessingParams.forSun()),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Status Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isProcessing ? Icons.hourglass_empty : Icons.info_outline,
                          color: _isProcessing ? Colors.orangeAccent : Colors.blueAccent,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Status',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _status,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _progress / 100,
                      backgroundColor: Colors.grey[800],
                      color: Colors.purpleAccent,
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_progress%',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Results Card
            if (_analysisResult != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.analytics, color: Colors.greenAccent, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            'Analysis Results',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildResultRow('Total Frames', '${_analysisResult!.totalFrames}'),
                      _buildResultRow('Analyzed', '${_analysisResult!.scores.length}'),
                      _buildResultRow('Quality Range', _analysisResult!.stats.toString()),
                      const SizedBox(height: 16),
                      Text(
                        'Top 10 Sharpest Frames:',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.purpleAccent,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...(_analysisResult!.scores.take(10).map((score) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              Container(
                                width: 60,
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.deepPurple.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '#${score.frameIndex}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: score.qualityScore,
                                  backgroundColor: Colors.grey[800],
                                  color: Colors.greenAccent,
                                  minHeight: 6,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                score.qualityScore.toStringAsFixed(3),
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      })),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action Buttons
            if (_selectedVideoPath != null && !_isProcessing) ...[
              ElevatedButton.icon(
                onPressed: _runAnalysis,
                icon: const Icon(Icons.search),
                label: const Text('Analyze Video'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.deepPurple,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              if (_analysisResult != null)
                ElevatedButton.icon(
                  onPressed: _runFullProcessing,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Stack & Sharpen'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green.shade700,
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String name, ProcessingParams params) {
    final isSelected = _presetName == name;
    return ChoiceChip(
      label: Text(name),
      selected: isSelected,
      onSelected: _isProcessing ? null : (selected) {
        if (selected) {
          setState(() {
            _presetName = name;
            _selectedPreset = params;
          });
        }
      },
      selectedColor: Colors.deepPurple,
      backgroundColor: Colors.grey[800],
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey[300],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.grey[400]),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedVideoPath = result.files.first.path;
        _selectedVideoName = result.files.first.name;
        _status = 'Video selected. Ready to analyze.';
        _analysisResult = null;
      });
    }
  }

  Future<void> _runAnalysis() async {
    if (_selectedVideoPath == null) return;

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _status = 'Starting analysis...';
      _analysisResult = null;
    });

    try {
      final result = await stacker.analyzeVideo(
        videoPath: _selectedVideoPath!,
        onProgress: (progress, message) {
          setState(() {
            _progress = progress;
            _status = message;
          });
        },
      );

      setState(() {
        _analysisResult = result;
        _status = 'Analysis complete! Found ${result.scores.length} quality frames.';
        _progress = 0;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Analysis failed: $e';
        _progress = 0;
        _isProcessing = false;
      });
    }
  }

  Future<void> _runFullProcessing() async {
    if (_selectedVideoPath == null) return;

    setState(() {
      _isProcessing = true;
      _progress = 0;
      _status = 'Starting processing...';
    });

    try {
      final success = await stacker.processVideo(
        videoPath: _selectedVideoPath!,
        outputPath: '/storage/emulated/0/Download/stacked_output.png',
        params: _selectedPreset,
        onProgress: (progress, message) {
          setState(() {
            _progress = progress;
            _status = message;
          });
        },
      );

      setState(() {
        _status = success
            ? 'Processing complete! Output saved to Downloads.'
            : 'Processing failed';
        _progress = 0;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Processing failed: $e';
        _progress = 0;
        _isProcessing = false;
      });
    }
  }
}
