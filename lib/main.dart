
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
  String _note = '--';
  int _octave = 0;
  bool _isListening = false;
  
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioSubscription;
  final List<double> _audioBuffer = [];
  
  final List<String> _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    if (await _audioRecorder.hasPermission()) {
      // Дозвіл надано
    } else {
      // Для Android потрібен permission_handler
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
      double detectedFreq = _detectFrequency(_audioBuffer, 44100);
      
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

  double _detectFrequency(List<double> samples, int sampleRate) {
    if (samples.length < 2048) return 0.0;

    // Обчислюємо RMS для перевірки рівня сигналу
    double rms = 0.0;
    for (var sample in samples) {
      rms += sample * sample;
    }
    rms = sqrt(rms / samples.length);

    // Ігноруємо тихі сигнали
    if (rms < 0.01) return 0.0;

    // Автокореляція для визначення періоду
    int minPeriod = (sampleRate / 1000).round(); // ~1000 Hz max
    int maxPeriod = (sampleRate / 60).round();   // ~60 Hz min

    double bestCorrelation = 0.0;
    int bestPeriod = 0;

    // Нормалізуємо семпли
    double sum = 0.0;
    for (var sample in samples) {
      sum += sample;
    }
    double mean = sum / samples.length;

    List<double> normalized = samples.map((s) => s - mean).toList();

    for (int period = minPeriod; period < maxPeriod && period < samples.length ~/ 2; period++) {
      double correlation = 0.0;
      double norm1 = 0.0;
      double norm2 = 0.0;

      for (int i = 0; i < samples.length - period; i++) {
        correlation += normalized[i] * normalized[i + period];
        norm1 += normalized[i] * normalized[i];
        norm2 += normalized[i + period] * normalized[i + period];
      }

      if (norm1 > 0 && norm2 > 0) {
        correlation = correlation / sqrt(norm1 * norm2);
      }

      if (correlation > bestCorrelation) {
        bestCorrelation = correlation;
        bestPeriod = period;
      }
    }

    // Потрібна висока кореляція для надійного визначення
    if (bestPeriod > 0 && bestCorrelation > 0.5) {
      return sampleRate / bestPeriod;
    }

    return 0.0;
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
              // Частота
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
              
              // Нота
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
              
              // Октава
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
              
              // Кнопка
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