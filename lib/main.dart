import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';

void main() => runApp(const MatrixApp());

class MatrixConfig {
  static const double fontSize = 14.0;
  static const int streamLength = 20;
  static const Duration messageDelay = Duration(seconds: 3);
  static const Duration typingInterval = Duration(milliseconds: 110);
  static const String letters =
      'アァイィウヴエカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  static const List<String> messages = [
    'Wake up, Neo...',
    'The Matrix has you...',
    'Follow the white rabbit.',
    'Knock, knock, Neo.',
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
  List<double>? _positions;
  List<double>? _speeds;

  String _currentMessage = '';
  int _messageIndex = 0;
  int _charIndex = 0;
  bool _showCursor = true;

  Ticker? _animationTicker;
  Timer? _typingTimer;
  Timer? _cursorTimer;
  Duration _lastElapsed = Duration.zero;

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAudioInitialized = false;

  final Map<String, ui.TextPainter> _textPainterCache = {};

  @override
  void initState() {
    super.initState();
    _initAudio();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMatrixData();
      _startAnimation();
      _startCursorBlinking();
      Future<void>.delayed(MatrixConfig.messageDelay, _typeNextMessage);
    });
  }

  Future<void> _initAudio() async {
    try {
      await _audioPlayer.setAsset('assets/matrix.mp3'); # <-- поменяли здесь
      await _audioPlayer.setLoopMode(LoopMode.one);
      _isAudioInitialized = true;
    } catch (e) {
      debugPrint("Не удалось запустить аудио: $e. Приложение продолжит работу без звука.");
    }
  }

  void _initializeMatrixData() {
    final screenWidth = MediaQuery.of(context).size.width;
    final columns = (screenWidth / MatrixConfig.fontSize).floor();
    final random = Random();

    setState(() {
      _streams = List<List<int>>.generate(columns, (_) {
        return List<int>.generate(MatrixConfig.streamLength, (_) {
          return MatrixConfig.letters.codeUnitAt(random.nextInt(MatrixConfig.letters.length));
        });
      });
      _positions = List<double>.generate(
        columns,
        (_) => -random.nextInt(MatrixConfig.streamLength * 3).toDouble(),
      );
      _speeds = List<double>.generate(
        columns,
        (_) => 0.15 + random.nextDouble() * 0.25,
      );
    });
  }

  void _startAnimation() {
    _animationTicker = createTicker(_onAnimationTick)..start();
  }

  void _startCursorBlinking() {
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          _showCursor = !_showCursor;
        });
      }
    });
  }

  void _onAnimationTick(Duration elapsed) {
    if (!mounted) return;
    
    final double dt = (elapsed.inMilliseconds - _lastElapsed.inMilliseconds) / 16.0; 
    _lastElapsed = elapsed;

    if (_streams == null || _positions == null || _speeds == null) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final random = Random();

    for (int i = 0; i < _positions!.length; i++) {
      _positions![i] += _speeds![i] * dt;

      if (random.nextDouble() < 0.05) {
        final changeIdx = random.nextInt(MatrixConfig.streamLength);
        _streams![i][changeIdx] = MatrixConfig.letters.codeUnitAt(
          random.nextInt(MatrixConfig.letters.length),
        );
      }

      final tailY = (_positions![i] - MatrixConfig.streamLength) * MatrixConfig.fontSize;
      if (tailY > screenHeight) {
        _positions![i] = -random.nextInt(MatrixConfig.streamLength).toDouble();
        _speeds![i] = 0.15 + random.nextDouble() * 0.25;
      }
    }

    setState(() {});
  }

  void _typeNextMessage() {
    if (!mounted) return;
    _currentMessage = '';
    _charIndex = 0;
    final fullText = MatrixConfig.messages[_messageIndex];

    if (_isAudioInitialized) {
      _audioPlayer.play();
    }

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
        
        if (_isAudioInitialized) {
          _audioPlayer.pause();
        }

        Future<void>.delayed(const Duration(seconds: 3), () {
          if (!mounted) return;
          setState(() => _currentMessage = '');
          _messageIndex = (_messageIndex + 1) % MatrixConfig.messages.length;
          Future<void>.delayed(const Duration(seconds: 1), _typeNextMessage);
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
            fontWeight: FontWeight.bold,
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomPaint(
        painter: MatrixPainter(
          streams: _streams!,
          positions: _positions!,
          fontSize: MatrixConfig.fontSize,
          message: _currentMessage,
          showCursor: _showCursor,
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
    _cursorTimer?.cancel();
    _audioPlayer.dispose();
    for (final tp in _textPainterCache.values) {
      tp.dispose();
    }
    super.dispose();
  }
}

class MatrixPainter extends CustomPainter {
  final List<List<int>> streams;
  final List<double> positions;
  final double fontSize;
  final String message;
  final bool showCursor;
  final ui.TextPainter Function(int, Color) getCachedPainter;

  const MatrixPainter({
    required this.streams,
    required this.positions,
    required this.fontSize,
    required this.message,
    required this.showCursor,
    required this.getCachedPainter,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    for (int i = 0; i < streams.length; i++) {
      final double headPosition = positions[i];
      final List<int> stream = streams[i];

      for (int j = 0; j < stream.length; j++) {
        final double y = (headPosition - j) * fontSize;
        if (y < -fontSize || y > size.height + fontSize) continue;

        Color color;
        if (j == 0) {
          color = const Color(0xFFE0F7FA); 
        } else {
          final double opacity = (1.0 - (j / stream.length)).clamp(0.0, 1.0);
          color = Colors.green.withOpacity(opacity);
        }

        final painter = getCachedPainter(stream[j], color);
        painter.paint(canvas, Offset(i * fontSize, y));
      }
    }

    if (message.isNotEmpty) {
      final displayText = showCursor ? '$message█' : message;
      final messagePainter = ui.TextPainter(
        text: ui.TextSpan(
          text: displayText,
          style: const TextStyle(
            color: Color(0xFF39FF14), 
            fontSize: 24,
            fontFamily: 'monospace',
            shadows: [
              Shadow(
                blurRadius: 10.0,
                color: Color(0xFF39FF14),
                offset: Offset(0, 0),
              ),
            ],
          ),
        ),
        textAlign: TextAlign.left,
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: size.width - 40);

      messagePainter.paint(
        canvas,
        Offset(
          (size.width - messagePainter.width) / 2,
          size.height / 2.2,
        ),
      );
      messagePainter.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant MatrixPainter oldDelegate) => true;
}
