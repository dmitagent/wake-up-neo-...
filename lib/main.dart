import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:just_audio/just_audio.dart';

void main() => runApp(const MatrixApp());

// ============================================================================
// 🎨 КОНФИГУРАЦИЯ (вынесено для гибкости)
// ============================================================================
class MatrixConfig {
  static const double fontSize = 12.0;
  static const int streamLength = 20;
  static const int animationFps = 60; // Целевая частота кадров
  static const Duration messageDelay = Duration(seconds: 7);
  static const Duration typingInterval = Duration(milliseconds: 150);
  static const String letters = 'アァイィウヴエカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン';
  
  // Аудио
  static const double backgroundVolume = 0.3;
  static const double typingVolume = 0.7;
  static const String backgroundAudioUrl = 
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3';
  static const String typingAudioUrl = 
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3';
  
  static const List<String> messages = [
    'Wake up, Neo...',
    'The Matrix has you...',
    'Follow the white rabbit.',
  ];
}

// ============================================================================
// 🚀 ПРИЛОЖЕНИЕ
// ============================================================================
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

// ============================================================================
// 🖥️ ЭКРАН: Управление состоянием и логикой
// ============================================================================
class MatrixScreen extends StatefulWidget {
  const MatrixScreen({super.key});

  @override
  State<MatrixScreen> createState() => _MatrixScreenState();
}

class _MatrixScreenState extends State<MatrixScreen> with TickerProviderStateMixin {
  // Данные анимации
  List<List<int>>? _streams; // ✅ Храним коды символов (int), а не String
  List<int>? _positions;
  
  // Сообщения
  String _currentMessage = '';
  int _messageIndex = 0;
  int _charIndex = 0;
  
  // Анимация
  Ticker? _animationTicker;
  Timer? _typingTimer;
  
  // Аудио (just_audio)
  AudioPlayer? _backgroundAudio;
  AudioPlayer? _typingAudio;
  
  // Кэш для отрисовки (ключ: "char#colorValue")
  final Map<String, ui.TextPainter> _textPainterCache = {};
  
  // Цвета для градиента потока
  static const Color _headColor = Colors.greenAccent;
  static const Color _tailBaseColor = Color.fromARGB(255, 0, 180, 0);

  @override
  void initState() {
    super.initState();
    // Инициализация после первого фрейма, когда известен размер экрана
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMatrixData();
      _initializeAudio();
      _startAnimation();
      Future<void>.delayed(MatrixConfig.messageDelay, _typeNextMessage);
    });
  }

  // --------------------------------------------------------------------------
  // 🔧 Инициализация данных матрицы
  // --------------------------------------------------------------------------
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

  // --------------------------------------------------------------------------
  // 🔊 Инициализация аудио (just_audio)
  // --------------------------------------------------------------------------
  Future<void> _initializeAudio() async {
    try {
      // Фоновая музыка
      _backgroundAudio = AudioPlayer();
      await _backgroundAudio?.setAudioSource(
        AudioSource.uri(Uri.parse(MatrixConfig.backgroundAudioUrl)),
      );
      _backgroundAudio?.setLoopMode(LoopMode.one);
      _backgroundAudio?.setVolume(MatrixConfig.backgroundVolume);
      await _backgroundAudio?.play();

      // Звук печати (короткий клик)
      _typingAudio = AudioPlayer();
      await _typingAudio?.setAudioSource(
        AudioSource.uri(Uri.parse(MatrixConfig.typingAudioUrl)),
      );
      _typingAudio?.setVolume(MatrixConfig.typingVolume);
      
    } on PlayerException catch (e) {
      debugPrint('❌ Audio error: ${e.message}');
      // Фолбэк: продолжаем без звука
    } catch (e) {
      debugPrint('❌ Unexpected audio error: $e');
    }
  }

  // --------------------------------------------------------------------------
  // 🎬 Анимация через Ticker (синхронизация с дисплеем)
  // --------------------------------------------------------------------------
  void _startAnimation() {
    _animationTicker = createTicker(_onAnimationTick)..start();
  }

  void _onAnimationTick(Duration elapsed) {
    if (!mounted) return;
    setState(_updateStreams);
  }

  // --------------------------------------------------------------------------
  // 🔄 Логика обновления потоков
  // --------------------------------------------------------------------------
  void _updateStreams() {
    if (_streams == null || _positions == null) return;
    
    final screenHeight = MediaQuery.of(context).size.height;
    final random = Random();
    
    for (int i = 0; i < _streams!.length; i++) {
      // Добавляем новый символ в начало (код символа, а не строку)
      _streams![i].insert(0, MatrixConfig.letters.codeUnitAt(
        random.nextInt(MatrixConfig.letters.length)
      ));
      
      // Обрезаем хвост
      if (_streams![i].length > MatrixConfig.streamLength) {
        _streams![i].removeLast();
      }

      // Сдвигаем поток вниз
      _positions![i] += 1;

      // Если поток полностью ушёл за экран — сбрасываем его вверх
      final tailRowIndex = _positions![i] - (_streams![i].length - 1);
      if (tailRowIndex * MatrixConfig.fontSize > screenHeight) {
        _positions![i] = -(MatrixConfig.streamLength + 
            random.nextInt(MatrixConfig.streamLength ~/ 2));
      }
    }
  }

  // --------------------------------------------------------------------------
  // ⌨️ Эффект печатания текста
  // --------------------------------------------------------------------------
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
        _playTypingSound();
      } else {
        timer.cancel();
        _typingAudio?.pause();
        
        // Пауза перед следующим сообщением
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          setState(() => _currentMessage = '');
          _messageIndex = (_messageIndex + 1) % MatrixConfig.messages.length;
          Future<void>.delayed(const Duration(seconds: 1), _typeNextMessage);
        });
      }
    });
  }

  void _playTypingSound() {
    if (_typingAudio != null) {
      // Перематываем и воспроизводим для эффекта "клика"
      _typingAudio?.seek(Duration.zero);
      _typingAudio?.play();
    }
  }

  // --------------------------------------------------------------------------
  // 🎨 Кэширование TextPainter (ключевая оптимизация!)
  // --------------------------------------------------------------------------
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

  // --------------------------------------------------------------------------
  // 🖼️ Отрисовка
  // --------------------------------------------------------------------------
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
          getCachedPainter: _getCachedPainter, // ✅ Передаём кэш-функцию
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 🧹 Очистка ресурсов
  // --------------------------------------------------------------------------
  @override
  void dispose() {
    _animationTicker?.dispose();
    _typingTimer?.cancel();
    
    _backgroundAudio?.dispose();
    _typingAudio?.dispose();
    
    _textPainterCache.values.forEach((tp) => tp.dispose());
    
    super.dispose();
  }
}

// ============================================================================
// 🖌️ PAINTER: Отрисовка на Canvas
// ============================================================================
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
    // Эффект затухания предыдущего кадра (шлейф)
    final fadePaint = Paint()
      ..color = Colors.black.withAlpha((255 * 0.05).round());
    canvas.drawRect(Offset.zero & size, fadePaint);

    // Отрисовка потоков
    for (int i = 0; i < streams.length; i++) {
      for (int j = 0; j < streams[i].length; j++) {
        final y = (positions[i] - j) * fontSize;
        
        // Пропускаем невидимые символы (оптимизация)
        if (y < -fontSize || y > size.height) continue;

        final charCode = streams[i][j];
        
        // Градиент: голова яркая, хвост тускнеет
        final color = j == 0 
            ? Colors.greenAccent 
            : Color.fromARGB(
                255,
                0,
                (180 - j * 8).clamp(0, 255),
                0,
              );
        
        // ✅ Используем кэшированный TextPainter
        final painter = getCachedPainter(charCode, color);
        painter.paint(canvas, Offset(i * fontSize, y));
      }
    }

    // Центральное сообщение
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
        Offset((size.width - messagePainter.width) / 2, size.height / 2),
      );
      messagePainter.dispose(); // ✅ Освобождаем ресурс
    }
  }

  @override
  // ✅ Перерисовываем только при изменении данных
  bool shouldRepaint(covariant MatrixPainter old) {
    return !listEquals(old.streams, streams) ||
           !listEquals(old.positions, positions) ||
           old.message != message;
  }
}
