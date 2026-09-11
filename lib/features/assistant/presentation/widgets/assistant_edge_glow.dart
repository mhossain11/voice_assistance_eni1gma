import 'package:flutter/material.dart';

import '../../domain/entities/assistant_state.dart';

class AssistantEdgeGlow extends StatelessWidget {
  const AssistantEdgeGlow({super.key, required this.state});

  final AssistantState state;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: _AssistantGlow(state: state));
  }
}

class _AssistantGlow extends StatefulWidget {
  const _AssistantGlow({required this.state});

  final AssistantState state;

  @override
  State<_AssistantGlow> createState() => _AssistantGlowState();
}

class _AssistantGlowState extends State<_AssistantGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final (baseIntensity, pulse, color) = switch (widget.state) {
          AssistantState.sleeping => (0.08, 0.04, const Color(0xFF7D8A96)),
          AssistantState.listening => (0.35, 0.35, const Color(0xFF62E6FF)),
          AssistantState.thinking => (0.24, 0.48, const Color(0xFFA88CFF)),
          AssistantState.speaking => (0.32, 0.40, const Color(0xFF67F5C5)),
        };
        final intensity = baseIntensity + (_controller.value * pulse);
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: color.withValues(alpha: intensity),
              width: 1.3,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: intensity * 0.40),
                blurRadius: 12 + (_controller.value * 16),
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    ),
  );
}
