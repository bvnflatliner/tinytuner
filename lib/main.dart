import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

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
  String _note = '--';
  int _octave = 0;
  bool _isListening = false;
  
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSubscription;
  final List<double> _audioBuffer = [];
  final List<double> _recentFrequencies = [];

  final List<String> _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

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
          debugPrint('Помилка потоку аудіо: $error');
          _stopListening();
        });
      } else {
        debugPrint('Немає дозволу на використання мікрофона');
      }
    } catch (e) {
      debugPrint('Помилка запуску мікрофона: $e');
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
      _note = '--';
      _octave = 0;
      _audioBuffer.clear();
      _recentFrequencies.clear();
    });
  }

  void _processAudio(Uint8List bytes) {
    // Конвертуємо байти в 16-бітні PCM семпли
    List<double> samples = [];
    for (int i = 0; i < bytes.length - 1; i += 2) {
      int sample = bytes[i] | (bytes[i + 1] << 8);
      if (sample > 32767) sample -= 65536;
      samples.add(sample / 32768.0);
    }

    // Додаємо до буфера
    _audioBuffer.addAll(samples);

    // Обробляємо, коли маємо достатньо даних
    if (_audioBuffer.length >= 4096) {
      // Застосовуємо Hann-вікно для зменшення гармонік
      List<double> windowed = _applyHannWindow(_audioBuffer);

      double detectedFreq = _yinPitch(windowed, 44100);
      detectedFreq = _postprocessFrequency(detectedFreq);

      if (detectedFreq > 0) {
        setState(() {
          _frequency = detectedFreq;
          _updateNote(detectedFreq);
        });
      }

      // Очищуємо буфер, залишаючи трохи для перекриття
      if (_audioBuffer.length > 8192) {
        _audioBuffer.removeRange(0, _audioBuffer.length - 2048);
      }
    }
  }

  // --- Покращений алгоритм визначення частоти (YIN) ---
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

    // 1️⃣ медіанне згладжування
    _recentFrequencies.add(freq);
    if (_recentFrequencies.length > 5) {
      _recentFrequencies.removeAt(0);
    }
    List<double> sorted = List.from(_recentFrequencies)..sort();
    freq = sorted[sorted.length ~/ 2];

    // 2️⃣ корекція октав (якщо фаза подвоєна або половинна)
    if (_lastFrequency > 0) {
      if ((freq * 2 - _lastFrequency).abs() < 5) freq *= 2;
      if ((freq / 2 - _lastFrequency).abs() < 5) freq /= 2;
    }

    _lastFrequency = freq;
    return freq;
  }

  void _updateNote(double frequency) {
    if (frequency < 20 || frequency > 4200) return;

    // Формула: n = 12 * log2(f/440) + 69 (де 69 - це A4)
    double n = 12 * log(frequency / 440) / log(2) + 69;
    int midiNote = n.round();

    _octave = (midiNote ~/ 12) - 1;
    int noteIndex = midiNote % 12;
    _note = _noteNames[noteIndex];
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
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${_frequency.toStringAsFixed(1)} Hz',
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 60),
              Text(
                _note,
                style: TextStyle(
                  fontSize: 140,
                  fontWeight: FontWeight.bold,
                  color: _isListening ? Colors.blue : Colors.grey,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Октава: $_octave',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 80),
              ElevatedButton.icon(
                onPressed: _isListening ? _stopListening : _startListening,
                icon: Icon(_isListening ? Icons.stop : Icons.mic),
                label: Text(
                  _isListening ? 'Зупинити' : 'Почати',
                  style: const TextStyle(fontSize: 20),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 20,
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
