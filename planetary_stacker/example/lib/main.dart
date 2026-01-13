import 'package:flutter/material.dart';
import 'package:planetary_stacker/planetary_stacker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Planetary Stacker Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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
  int _progress = 0;
  String _status = 'Ready';
  AnalysisResult? _analysisResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Planetary Stacker Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Library Version: ${stacker.version}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Status: $_status'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _progress / 100),
                    Text('Progress: $_progress%'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_analysisResult != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Analysis Results',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Total frames: ${_analysisResult!.totalFrames}'),
                      Text('Analyzed frames: ${_analysisResult!.scores.length}'),
                      Text('Quality stats: ${_analysisResult!.stats}'),
                      const SizedBox(height: 8),
                      Text(
                        'Top 10 frames:',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      ...(_analysisResult!.scores.take(10).map((score) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Text(
                            '  Frame ${score.frameIndex}: ${score.qualityScore.toStringAsFixed(3)}',
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        );
                      })),
                    ],
                  ),
                ),
              ),
            ],
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _progress == 0 ? _runAnalysis : null,
              icon: const Icon(Icons.analytics),
              label: const Text('Test Frame Analysis'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _progress == 0 ? _runFullProcessing : null,
              icon: const Icon(Icons.video_library),
              label: const Text('Test Full Processing'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runAnalysis() async {
    setState(() {
      _progress = 0;
      _status = 'Starting analysis...';
      _analysisResult = null;
    });

    final result = await stacker.analyzeVideo(
      videoPath: '/path/to/test/video.mp4',
      onProgress: (progress, message) {
        setState(() {
          _progress = progress;
          _status = message;
        });
      },
    );

    setState(() {
      _analysisResult = result;
      _status = 'Analysis complete';
      _progress = 0;
    });
  }

  Future<void> _runFullProcessing() async {
    setState(() {
      _progress = 0;
      _status = 'Starting processing...';
    });

    final params = ProcessingParams.forJupiterSaturn();

    final success = await stacker.processVideo(
      videoPath: '/path/to/test/video.mp4',
      outputPath: '/path/to/output.png',
      params: params,
      onProgress: (progress, message) {
        setState(() {
          _progress = progress;
          _status = message;
        });
      },
    );

    setState(() {
      _status = success ? 'Processing complete!' : 'Processing failed';
      _progress = 0;
    });
  }
}
