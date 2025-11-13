import 'package:flutter/material.dart';
import 'dart:math';

class NoteScrollBar extends StatefulWidget {
  final double frequency;
  final Duration animationDuration;

  const NoteScrollBar({
    super.key,
    required this.frequency,
    this.animationDuration = const Duration(milliseconds: 150),
  });

  @override
  State<NoteScrollBar> createState() => _NoteScrollBarState();
}

class _NoteScrollBarState extends State<NoteScrollBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  double _currentCents = 0.0;
  double _targetCents = 0.0;

  final List<String> _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );

    _animation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() {
          _currentCents = _animation.value;
        });
      });

    if (widget.frequency > 0) {
      _currentCents = _frequencyToCents(widget.frequency);
      _targetCents = _currentCents;
    }
  }

  @override
  void didUpdateWidget(NoteScrollBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.frequency != oldWidget.frequency && widget.frequency > 0) {
      _updateFrequency(widget.frequency);
    }
  }

  void _updateFrequency(double frequency) {
    double newCents = _frequencyToCents(frequency);
    
    // Handling cyclicity: if the difference is greater than 600 cents (half an octave),
    // it means we’ve crossed the cycle boundary
    double diff = newCents - _currentCents;
    if (diff.abs() > 600) {
      if (diff > 0) {
        _currentCents += 1200; // add an octave
      } else {
        _currentCents -= 1200; // subtract an octave
      }
    }

    _targetCents = newCents;

    _animation = Tween<double>(
      begin: _currentCents,
      end: _targetCents,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward(from: 0);
  }

  // Converts frequency to cents relative to A4 (440 Hz)
  double _frequencyToCents(double frequency) {
    if (frequency <= 0) return 0;
    return 1200 * log(frequency / 440) / ln2;
  }

  // Gets the nearest note and deviation in cents
  Map<String, dynamic> _getNoteInfo(double cents) {
    // Normalizes cents to the range [0, 1200)
    double normalizedCents = cents % 1200;
    if (normalizedCents < 0) normalizedCents += 1200;

    // Find the nearest semitone (100 cents = 1 semitone)
    int semitone = (normalizedCents / 100).round();

    // Deviation from the nearest note
    double deviation = normalizedCents - (semitone * 100);
    if (deviation > 50) deviation -= 100;
    if (deviation < -50) deviation += 100;

    // Determine the octave (A4 = 440 Hz is 0 cents, octave 4)
    int octave = 4 + ((cents + 900) / 1200).floor();
    
    // Adjusting the note relative to A
    int noteIndex = (semitone + 9) % 12; // A=0, A#=1, ..., G#=11

    return {
      'note': _noteNames[noteIndex],
      'octave': octave,
      'deviation': deviation,
      'semitone': semitone,
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool isListening = widget.frequency > 0;
    double frequency = isListening ? widget.frequency : 0.0;

    Map<String, dynamic> noteInfo = _getNoteInfo(_currentCents);
    double deviation = noteInfo['deviation'];
    bool isInTune = deviation.abs() <= 10;

    return SizedBox(
      height: 300,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Indicator of frequency and deviation
                Text(
                  '${frequency.toStringAsFixed(1)} Hz',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${deviation >= 0 ? '+' : ''}${deviation.toStringAsFixed(0)} ¢',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isInTune ? Colors.green : Colors.orange,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Scrollable note scale with pointer
          Expanded(
            child: Stack(
              children: [
                // Scrollable note scale
                CustomPaint(
                  size: Size.infinite,
                  painter: _NoteScalePainter(
                    cents: _currentCents,
                    noteInfo: noteInfo,
                  ),
                ),
                
                // Pointer
                Center(
                  child: CustomPaint(
                    size: const Size(20, 40),
                    painter: _PointerPainter(isInTune: isInTune),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Displaying the current note and octave
                Text(
                  noteInfo['note'],
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    color: isListening ? Colors.blue : Colors.grey,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  noteInfo['octave'].toString(),
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            )
          ),
        ],
      ),
    );
  }
}

class _NoteScalePainter extends CustomPainter {
  final double cents;
  final Map<String, dynamic> noteInfo;
  final double centsPerPixel = 1.0;

  final List<String> _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  _NoteScalePainter({
    required this.cents,
    required this.noteInfo,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Draw background
    final bgPaint = Paint()..color = Colors.grey[200]!;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw center line
    final centerLinePaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(centerX, 0),
      Offset(centerX, size.height),
      centerLinePaint,
    );

    // Get the range of cents to draw
    double startCents = cents - (centerX * centsPerPixel);
    double endCents = cents + (centerX * centsPerPixel);

    // Draw ticks and note names
    for (double c = (startCents / 25).floor() * 25;
        c <= endCents;
        c += 25) {
      double x = centerX + (c - cents) / centsPerPixel;

      if (x < 0 || x > size.width) continue;

      // Determine if it is a main note (100 cents)
      bool isMainNote = (c % 100).abs() < 0.1;
      
      // Determine deviation from the current note
      double currentNoteCents = noteInfo['semitone'] * 100.0;
      double normalizedC = c % 1200;
      if (normalizedC < 0) normalizedC += 1200;
      double distanceToCurrentNote = (normalizedC - currentNoteCents).abs();
      if (distanceToCurrentNote > 600) distanceToCurrentNote = 1200 - distanceToCurrentNote;
      
      // Determine if it is exactly the current note (deviation within ±10 cents)
      bool isCurrentNote = distanceToCurrentNote < 5 && noteInfo['deviation'].abs() <= 10;

      // Draw tick
      final tickPaint = Paint()
        ..color = isCurrentNote ? Colors.green : (isMainNote ? Colors.black : Colors.grey[600]!)
        ..strokeWidth = isMainNote ? 2 : 1;

      double tickHeight = isMainNote ? 25 : 15;
      canvas.drawLine(
        Offset(x, centerY - tickHeight / 2),
        Offset(x, centerY + tickHeight / 2),
        tickPaint,
      );

      // Draw note names for main notes
      if (isMainNote) {
        int semitone = ((normalizedC / 100).round()) % 12;
        int noteIndex = (semitone + 9) % 12;
        String noteName = _noteNames[noteIndex];

        final textSpan = TextSpan(
          text: noteName,
          style: TextStyle(
            color: isCurrentNote ? Colors.green : Colors.black,
            fontSize: 32,
            fontWeight: isCurrentNote ? FontWeight.bold : FontWeight.normal,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(x - textPainter.width / 2, centerY + 20),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_NoteScalePainter oldDelegate) {
    return cents != oldDelegate.cents;
  }
}

class _PointerPainter extends CustomPainter {
  final bool isInTune;

  _PointerPainter({required this.isInTune});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isInTune ? Colors.green : Colors.red
      ..style = PaintingStyle.fill;

    // Draw triangle pointer
    final path = Path();
    path.moveTo(size.width / 2, 0); // Top point
    path.lineTo(0, size.height); // Left bottom corner
    path.lineTo(size.width, size.height); // Right bottom corner
    path.close();

    canvas.drawPath(path, paint);

    // Stroke
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(_PointerPainter oldDelegate) {
    return isInTune != oldDelegate.isInTune;
  }
}