import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/services/wake_word_service.dart';
import 'core/services/speech_service.dart';
import 'core/services/gemini_ai_service.dart';
import 'core/services/tts_service.dart';
import 'features/assistant/domain/entities/assistant_state.dart';
import 'features/assistant/presentation/controllers/assistant_controller.dart';
import 'features/assistant/presentation/widgets/assistant_edge_glow.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  runApp(const En1gmaApp());
}

class En1gmaApp extends StatelessWidget {
  const En1gmaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'EN1GMA',
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF62E6FF),
      scaffoldBackgroundColor: const Color(0xFF05080C),
    ),
    home: const AssistantPage(),
  );
}

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  late final AssistantController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AssistantController(
      NativeWakeWordService(),
      NativeSpeechService(),
      GeminiAIService(),
      NativeTtsService(),
    );
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ValueListenableBuilder<AssistantState>(
      valueListenable: _controller.state,
      builder: (context, state, _) => Stack(
        fit: StackFit.expand,
        children: [
          AssistantEdgeGlow(state: state),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'EN1GMA',
                    style: TextStyle(fontSize: 30, letterSpacing: 8),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ambient Voice Assistant',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state == AssistantState.sleeping
                        ? 'Sleeping'
                        : state == AssistantState.thinking
                        ? 'Thinking…'
                        : state == AssistantState.speaking
                        ? 'Speaking…'
                        : 'Listening…',
                    style: TextStyle(
                      color:
                          state == AssistantState.listening ||
                              state == AssistantState.thinking ||
                              state == AssistantState.speaking
                          ? const Color(0xFF62E6FF)
                          : Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sample Android Prototype',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: _controller.currentTranscript,
                    builder: (context, transcript, _) => transcript.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              '“$transcript”',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: _controller.currentResponse,
                    builder: (context, response, _) => response.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 20),
                            child: Text(
                              response,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFFB5F4FF)),
                            ),
                          ),
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: _controller.errorMessage,
                    builder: (context, error, _) => error == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(error, textAlign: TextAlign.center),
                          ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 36),
                    Wrap(
                      spacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: _controller.onWakeWordDetected,
                          child: const Text('Simulate Wake Word'),
                        ),
                        OutlinedButton(
                          onPressed: _controller.goToSleep,
                          child: const Text('Sleep'),
                        ),
                        OutlinedButton(
                          onPressed: _controller.startSpeechListening,
                          child: const Text('Start STT'),
                        ),
                        OutlinedButton(
                          onPressed: _controller.stopSpeechListening,
                          child: const Text('Stop STT'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
