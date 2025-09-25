import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(MatrixApp());

class MatrixApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          return Scaffold(body: MatrixScreen());
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MatrixScreen extends StatefulWidget {
  @override
  _MatrixScreenState createState() => _MatrixScreenState();
}

class _MatrixScreenState extends State<MatrixScreen> {
  final double fontSize = 12.0;
  final int streamLength = 20; // Max length of a visible falling stream
  final String letters = 'アァイィウヴエカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン';
  final Random random = Random();

  List<List<String>>? streams;
  List<int>? positions; // Represents the 'head' row index for each stream
  String currentMessage = '';
  int messageIndex = 0;
  int charIndex = 0;
  Timer? _timer;
  Timer? _typingTimer;
  final List<String> messages = <String>[
    'Wake up, Neo...',
    'The Matrix has you...',
    'Follow the white rabbit.',
  ];

  // Audio controllers
  VideoPlayerController? _backgroundAudioController;
  VideoPlayerController? _typingAudioController;

  // Placeholder URLs for audio files. In a real application, you would host your own.
  // Using SoundHelix.com examples for demonstration purposes.
  final String _backgroundAudioUrl =
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3'; // An ambient-like track
  final String _typingAudioUrl =
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3'; // A shorter track for typing effect

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeMatrixData();
      _initializeAudio(); // Initialize audio after matrix data is set up
      _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted) return;
        setState(() {
          updateStreams();
        });
      });
      Future<void>.delayed(const Duration(seconds: 7), typeNextMessage);
    });
  }

  void _initializeMatrixData() {
    final double screenWidth = MediaQuery.of(context).size.width;
    final int columns = (screenWidth / fontSize).floor();
    setState(() {
      streams = List<List<String>>.generate(columns, (_) => <String>[]);
      // Initialize positions with negative values to make streams appear to flow in from above
      positions = List<int>.generate(
        columns,
        (_) => -random.nextInt(streamLength * 2),
      );
    });
  }

  /// Initializes and configures the audio players.
  Future<void> _initializeAudio() async {
    _backgroundAudioController = VideoPlayerController.networkUrl(
      Uri.parse(_backgroundAudioUrl),
    );
    _typingAudioController = VideoPlayerController.networkUrl(
      Uri.parse(_typingAudioUrl),
    );

    try {
      // Initialize both controllers concurrently
      await Future.wait<void>(<Future<void>>[
        _backgroundAudioController!.initialize(),
        _typingAudioController!.initialize(),
      ]);

      if (mounted) {
        // Configure and play background audio
        _backgroundAudioController!.setLooping(true);
        _backgroundAudioController!.setVolume(
          0.3,
        ); // Set a lower volume for background ambience
        _backgroundAudioController!.play();

        // Configure typing audio (don't play yet)
        _typingAudioController!.setVolume(
          0.7,
        ); // Typing sound should be more noticeable
        _typingAudioController!.pause(); // Ensure it's paused initially
      }
    } catch (e) {
      // Log any errors during audio initialization
      // In a production app, you might display an error to the user or retry.
      print('Error initializing audio: $e');
    }
  }

  void typeNextMessage() {
    if (!mounted) return;

    currentMessage = '';
    charIndex = 0;
    final String fullText = messages[messageIndex];
    _typingTimer = Timer.periodic(const Duration(milliseconds: 150), (
      Timer timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (charIndex < fullText.length) {
        setState(() {
          currentMessage += fullText[charIndex];
          charIndex++;
        });
        // Play typing sound for each character
        if (_typingAudioController != null &&
            _typingAudioController!.value.isInitialized) {
          // Seek to start and play to simulate a distinct 'click' sound for each character.
          // Note: If the actual audio file is long, this will cut it off and restart.
          // For true 'typing' effect with multiple short sounds, a dedicated audio pooling library might be better.
          _typingAudioController!.seekTo(Duration.zero);
          _typingAudioController!.play();
        }
      } else {
        timer.cancel();
        // Pause typing sound once the message is complete
        _typingAudioController?.pause();
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          setState(() {
            currentMessage = '';
          });
          messageIndex++;
          if (messageIndex < messages.length) {
            Future<void>.delayed(const Duration(seconds: 1), typeNextMessage);
          } else {
            messageIndex = 0; // Loop messages
            Future<void>.delayed(const Duration(seconds: 1), typeNextMessage);
          }
        });
      }
    });
  }

  void updateStreams() {
    if (streams == null || positions == null) {
      return;
    }

    final double screenHeight = MediaQuery.of(context).size.height;

    for (int i = 0; i < streams!.length; i++) {
      streams![i].insert(0, letters[random.nextInt(letters.length)]);
      if (streams![i].length > streamLength) {
        streams![i].removeLast();
      }

      positions![i] += 1; // Move stream down by one row

      // Calculate the y-coordinate of the last character in the stream.
      // If this character has moved completely off-screen (below the bottom edge),
      // reset the stream's position to start above the top edge, ensuring continuity.
      final int tailCharRowIndex = positions![i] - (streams![i].length - 1);
      if (tailCharRowIndex * fontSize > screenHeight) {
        // Reset the head's position to be above the screen.
        // Start it with a negative offset related to its length, plus some randomness
        // to prevent all streams from starting at the exact same 'y' coordinate.
        positions![i] = -(streamLength + random.nextInt(streamLength ~/ 2));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (streams == null || positions == null) {
      return Container(color: Colors.black);
    }

    return Container(
      color: Colors.black,
      child: CustomPaint(
        painter: MatrixPainter(streams!, positions!, fontSize, currentMessage),
        child: Container(),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _typingTimer?.cancel();
    _backgroundAudioController
        ?.dispose(); // Dispose background audio controller
    _typingAudioController?.dispose(); // Dispose typing audio controller
    super.dispose();
  }
}

class MatrixPainter extends CustomPainter {
  final List<List<String>> streams;
  final List<int> positions;
  final double fontSize;
  final String message;

  MatrixPainter(this.streams, this.positions, this.fontSize, this.message);

  @override
  void paint(Canvas canvas, Size size) {
    // This creates a subtle fade-out effect for previous frames, giving the impression of movement.
    final Paint fadePaint = Paint()
      ..color = Colors.black.withAlpha((255 * 0.05).round());
    canvas.drawRect(Offset.zero & size, fadePaint);

    for (int i = 0; i < streams.length; i++) {
      for (int j = 0; j < streams[i].length; j++) {
        // Calculate y-position: 'positions[i]' is the head, 'j' is the offset from the head.
        final double y = (positions[i] - j) * fontSize;

        // Skip drawing characters far off-screen for performance
        if (y < -fontSize || y > size.height) continue;

        final String char = streams[i][j];
        // Color changes to create a fading trail effect: head is bright, tail fades to darker green.
        final Color color = j == 0
            ? Colors
                  .greenAccent // Head of the stream is bright green
            : Color.fromARGB(
                255,
                0,
                (180 - j * 8).clamp(0, 255),
                0,
              ); // Fades to darker green
        final TextStyle textStyle = TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: 'monospace',
        );
        final TextPainter tp = TextPainter(
          text: TextSpan(text: char, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(i * fontSize, y));
      }
    }

    if (message.isNotEmpty) {
      final TextStyle centerStyle = TextStyle(
        color: Colors.greenAccent,
        fontSize: 28,
        fontWeight: FontWeight.bold,
        fontFamily: 'monospace',
      );
      final TextPainter tp = TextPainter(
        text: TextSpan(text: message, style: centerStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant MatrixPainter oldDelegate) => true;
}
