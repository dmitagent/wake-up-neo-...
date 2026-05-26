import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'; // ✅ listEquals
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

void main() => runApp(const MatrixApp());

class MatrixConfig {
  static const double fontSize = 12.0;
  static const int streamLength = 20;
  static const Duration messageDelay = Duration(seconds: 7);
  static const Duration typingInterval = Duration(milliseconds: 150);
  static const String letters =
      'アァイィウヴエカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン';

  static const List<String> messages = [
    'Wake up, Neo...',
    'The Matrix has you...',
    'Follow the white rabbit.',
  ];
}

class MatrixApp extends StatelessWidget {
  const MatrixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wake up, Neo...',
      home: const MatrixScreen(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: false),
    );
  }
}

class MatrixScreen extends StatefulWidget {
  const MatrixScreen({super.key});

  @override
  State<MatrixScreen> createState() => _MatrixScreenState();
}

class _MatrixScreenState extends State<MatrixScreen>
    with TickerProviderStateMixin {
  List<List<int>>? _streams;
  List<int>? _positions;

  String _currentMessage = '';
  int _messageIndex = 0;
  int _charIndex = 0;

  Ticker? _animationTicker;
  Timer? _typingTimer;

  // ✅ Throttle: обновляем логику не чаще ~30 раз/сек
  Duration _lastUpdate = Duration.zero;
  static const Duration _updateInterval =
      Duration(milliseconds: 33); // ~30 FPS

  final Map<String, ui.TextPainter> _textPainterCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMatrixData();
      _startAnimation();
      Future<void>.delayed(MatrixConfig.messageDelay, _typeNextMessage);
    });
  }

  void _initializeMatrixData() {
    final screenWidth = MediaQuery.of(context).size.width;
    final columns = (screenWidth / MatrixConfig.fontSize).floor();
    setState(() {
      _streams = List<List<int>>.generate(columns, (_) => <int>[]);
      _positions = List<int>.generate(
        columns,
        (_) => -Random().nextInt(MatrixConfig.streamLength * 2),
      );
    });
  }

  void _startAnimation() {
    _animationTicker = createTicker(_onAnimationTick)..start();
  }

  void _onAnimationTick(Duration elapsed) {
    if (!mounted) return;
    // ✅ Throttle — не каждый кадр
    if (elapsed - _lastUpdate < _updateInterval) return;
    _lastUpdate = elapsed;
    setState(_updateStreams);
  }

  void _updateStreams() {
    if (_streams == null || _positions == null) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final random = Random();

    for (int i = 0; i < _streams!.length; i++) {
      _streams![i].insert(
        0,
        MatrixConfig.letters
            .codeUnitAt(random.nextInt(MatrixConfig.letters.length)),
      );
      if (_streams![i].length > MatrixConfig.streamLength) {
        _streams![i].removeLast();
      }
      _positions![i] += 1;

      final tailY = (_positions![i] - (_streams![i].length - 1)) *
          MatrixConfig.fontSize;
      if (tailY > screenHeight) {
        _positions![i] = -(MatrixConfig.streamLength +
            random.nextInt(MatrixConfig.streamLength ~/ 2));
      }
    }
  }

  void _typeNextMessage() {
    if (!mounted) return;
    _currentMessage = '';
    _charIndex = 0;
    final fullText = MatrixConfig.messages[_messageIndex];

    _typingTimer = Timer.periodic(MatrixConfig.typingInterval, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_charIndex < fullText.length) {
        setState(() {
          _currentMessage += fullText[_charIndex];
          _charIndex++;
        });
      } else {
        timer.cancel();
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          setState(() => _currentMessage = '');
          _messageIndex =
              (_messageIndex + 1) % MatrixConfig.messages.length;
          Future<void>.delayed(
              const Duration(seconds: 1), _typeNextMessage);
        });
      }
    });
  }

  ui.TextPainter _getCachedPainter(int charCode, Color color) {
    final char = String.fromCharCode(charCode);
    final key = '$char#${color.value}';
    return _textPainterCache.putIfAbsent(key, () {
      return ui.TextPainter(
        text: ui.TextSpan(
          text: char,
          style: TextStyle(
            color: color,
            fontSize: MatrixConfig.fontSize,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_streams == null || _positions == null) {
      return const Scaffold(body: ColoredBox(color: Colors.black));
    }
    return Container(
      color: Colors.black,
      child: CustomPaint(
        painter: MatrixPainter(
          streams: _streams!,
          positions: _positions!,
          fontSize: MatrixConfig.fontSize,
          message: _currentMessage,
          getCachedPainter: _getCachedPainter,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  @override
  void dispose() {
    _animationTicker?.dispose();
    _typingTimer?.cancel();
    for (final tp in _textPainterCache.values) {
      tp.dispose();
    }
    super.dispose();
  }
}

class MatrixPainter extends CustomPainter {
  final List<List<int>> streams;
  final List<int> positions;
  final double fontSize;
  final String message;
  final ui.TextPainter Function(int, Color) getCachedPainter;

  const MatrixPainter({
    required this.streams,
    required this.positions,
    required this.fontSize,
    required this.message,
    required this.getCachedPainter,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    final fadePaint = Paint()
      ..color = Colors.black.withAlpha((255 * 0.05).round());
    canvas.drawRect(Offset.zero & size, fadePaint);

    for (int i = 0; i < streams.length; i++) {
      for (int j = 0; j < streams[i].length; j++) {
        final y = (positions[i] - j) * fontSize;
        if (y < -fontSize || y > size.height) continue;

        final color = j == 0
            ? Colors.greenAccent
            : Color.fromARGB(255, 0, (180 - j * 8).clamp(0, 255), 0);

        final painter = getCachedPainter(streams[i][j], color);
        painter.paint(canvas, Offset(i * fontSize, y));
      }
    }

    if (message.isNotEmpty) {
      final messagePainter = ui.TextPainter(
        text: ui.TextSpan(
          text: message,
          style: const TextStyle(
            color: Colors.greenAccent,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: size.width);

      messagePainter.paint(
        canvas,
        Offset(
            (size.width - messagePainter.width) / 2, size.height / 2),
      );
      messagePainter.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant MatrixPainter old) {
    return !listEquals(old.streams, streams) ||
        !listEquals(old.positions, positions) ||
        old.message != message;
  }
}
