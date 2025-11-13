import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'note_scroll_bar.dart';

void main() {
  runApp(const TinyTunerApp());
}

class TinyTunerApp extends StatelessWidget {
  const TinyTunerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tiny Tuner',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const TunerScreen(),
    );
  }
}

class TunerScreen extends StatefulWidget {
  const TunerScreen({super.key});

  @override
  State<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends State<TunerScreen> {
  double _frequency = 0.0;
  double _lastFrequency = 0.0;
  bool _isListening = false;
  
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSubscription;
  final List<double> _audioBuffer = [];
  final List<double> _recentFrequencies = [];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    if (!await _audioRecorder.hasPermission()) {
      await Permission.microphone.request();
    }
  }

  Future<void> _startListening() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final stream = await _audioRecorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 44100,
            numChannels: 1,
          ),
        );

        setState(() {
          _isListening = true;
        });

        _audioSubscription = stream.listen((data) {
          _processAudio(data);
        }, onError: (error) {
          debugPrint('Audio stream error: $error');
          _stopListening();
        });
      } else {
        debugPrint('Permission denied for microphone access.');
      }
    } catch (e) {
      debugPrint('Microphone initialization error: $e');
      setState(() {
        _isListening = false;
      });
    }
  }

  Future<void> _stopListening() async {
    await _audioSubscription?.cancel();
    await _audioRecorder.stop();
    setState(() {
      _isListening = false;
      _frequency = 0.0;
      _audioBuffer.clear();
      _recentFrequencies.clear();
    });
  }

  void _processAudio(Uint8List bytes) {
    // Convert bytes to 16-bits PCM samples
    List<double> samples = [];
    for (int i = 0; i < bytes.length - 1; i += 2) {
      int sample = bytes[i] | (bytes[i + 1] << 8);
      if (sample > 32767) sample -= 65536;
      samples.add(sample / 32768.0);
    }

    _audioBuffer.addAll(samples);

    // Handle buffer when enough samples are collected
    if (_audioBuffer.length >= 4096) {
      // Apply Hann window to reduce harmonics
      List<double> windowed = _applyHannWindow(_audioBuffer);

      double detectedFreq = _yinPitch(windowed, 44100);
      detectedFreq = _postprocessFrequency(detectedFreq);

      if (detectedFreq > 0) {
        setState(() {
          _frequency = detectedFreq;
        });
      }

      // Cleanup buffer keeping last 2048 samples for overlap
      if (_audioBuffer.length > 8192) {
        _audioBuffer.removeRange(0, _audioBuffer.length - 2048);
      }
    }
  }

  // --- Improved frequency detection algorithm (YIN) ---
  double _yinPitch(List<double> samples, int sampleRate) {
    int tauMax = samples.length ~/ 2;
    List<double> diff = List.filled(tauMax, 0.0);

    for (int tau = 1; tau < tauMax; tau++) {
      double sum = 0;
      for (int i = 0; i < tauMax; i++) {
        double delta = samples[i] - samples[i + tau];
        sum += delta * delta;
      }
      diff[tau] = sum;
    }

    List<double> cmnd = List.filled(tauMax, 0.0);
    cmnd[0] = 1;
    double runningSum = 0;
    for (int tau = 1; tau < tauMax; tau++) {
      runningSum += diff[tau];
      cmnd[tau] = diff[tau] * tau / runningSum;
    }

    const threshold = 0.1;
    for (int tau = 2; tau < tauMax; tau++) {
      if (cmnd[tau] < threshold) {
        int tau0 = tau - 1;
        int tau2 = tau + 1;
        if (tau2 >= cmnd.length) break;
        double betterTau = tau +
            (cmnd[tau2] - cmnd[tau0]) /
                (2 * (2 * cmnd[tau] - cmnd[tau2] - cmnd[tau0]));
        return sampleRate / betterTau;
      }
    }
    return 0.0;
  }

  List<double> _applyHannWindow(List<double> samples) {
    final length = samples.length;
    return List.generate(length, (i) {
      double w = 0.5 * (1 - cos(2 * pi * i / (length - 1)));
      return samples[i] * w;
    });
  }

  double _postprocessFrequency(double freq) {
    if (freq <= 0) return 0.0;

    // Median smoothing over recent frequencies
    _recentFrequencies.add(freq);
    if (_recentFrequencies.length > 5) {
      _recentFrequencies.removeAt(0);
    }
    List<double> sorted = List.from(_recentFrequencies)..sort();
    freq = sorted[sorted.length ~/ 2];

    // Octave correction (if the phase is doubled or halved)
    if (_lastFrequency > 0) {
      if ((freq * 2 - _lastFrequency).abs() < 5) freq *= 2;
      if ((freq / 2 - _lastFrequency).abs() < 5) freq /= 2;
    }

    _lastFrequency = freq;
  
    return freq;
  }

  @override
  void dispose() {
    _stopListening();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiny Tuner'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NoteScrollBar(frequency: _frequency),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: _isListening ? _stopListening : _startListening,
                icon: Icon(_isListening ? Icons.stop : Icons.mic),
                label: Text(
                  _isListening ? 'Stop' : 'Start',
                  style: const TextStyle(fontSize: 20),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 16,
                  ),
                  backgroundColor: _isListening ? Colors.red : Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
