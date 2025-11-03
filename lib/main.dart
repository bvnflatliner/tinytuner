import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mic_stream/mic_stream.dart';

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
  StreamSubscription<List<int>>? _audioSubscription;
  
  final List<String> _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  @override
  void initState() {
    super.initState();
    _requestPermissionAndStart();
  }

  Future<void> _requestPermissionAndStart() async {
    if (Platform.isIOS || Platform.isAndroid) {
      final status = await Permission.microphone.status;
      if (!status.isGranted) {
        await Permission.microphone.request();
      }
      if (status.isGranted) {
        _startListening();
      }
    } else {
      _startListening();
    }
  }

  void _startListening() {
    try {
      final stream = MicStream.microphone(
        audioSource: AudioSource.DEFAULT,
        sampleRate: 44100,
        channelConfig: ChannelConfig.CHANNEL_IN_MONO,
        audioFormat: AudioFormat.ENCODING_PCM_16BIT,
      );

      setState(() {
        _isListening = true;
      });

      _audioSubscription = stream.listen((samples) {
        _processAudio(samples);
      });
    } catch (e) {
      debugPrint('Помилка запуску мікрофона: $e');
    }
  }

  void _stopListening() {
    _audioSubscription?.cancel();
    setState(() {
      _isListening = false;
      _frequency = 0.0;
      _note = '--';
      _octave = 0;
    });
  }

  void _processAudio(List<int> samples) {
    // Конвертуємо 16-бітні семпли в double
    List<double> audioData = [];
    for (int i = 0; i < samples.length - 1; i += 2) {
      int sample = samples[i] | (samples[i + 1] << 8);
      if (sample > 32767) sample -= 65536;
      audioData.add(sample / 32768.0);
    }

    // Визначаємо частоту через автокореляцію
    double detectedFreq = _detectFrequency(audioData, 44100);
    
    if (detectedFreq > 0) {
      setState(() {
        _frequency = detectedFreq;
        _updateNote(detectedFreq);
      });
    }
  }

  double _detectFrequency(List<double> samples, int sampleRate) {
    if (samples.length < 1024) return 0.0;

    // Автокореляція для визначення періоду
    int minPeriod = (sampleRate / 1000).round(); // ~1000 Hz max
    int maxPeriod = (sampleRate / 80).round();   // ~80 Hz min

    double bestCorrelation = 0.0;
    int bestPeriod = 0;

    for (int period = minPeriod; period < maxPeriod && period < samples.length ~/ 2; period++) {
      double correlation = 0.0;
      for (int i = 0; i < samples.length - period; i++) {
        correlation += samples[i] * samples[i + period];
      }

      if (correlation > bestCorrelation) {
        bestCorrelation = correlation;
        bestPeriod = period;
      }
    }

    if (bestPeriod > 0 && bestCorrelation > 0.1) {
      return sampleRate / bestPeriod;
    }

    return 0.0;
  }

  void _updateNote(double frequency) {
    if (frequency < 20) return;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiny Tuner'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${_frequency.toStringAsFixed(1)} Hz',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 40),
            Text(
              _note,
              style: TextStyle(
                fontSize: 120,
                fontWeight: FontWeight.bold,
                color: _isListening ? Colors.blue : Colors.grey,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Октава: $_octave',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 60),
            ElevatedButton(
              onPressed: _isListening ? _stopListening : _startListening,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 20,
                ),
              ),
              child: Text(
                _isListening ? 'Зупинити' : 'Почати',
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
