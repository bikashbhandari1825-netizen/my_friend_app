// widgets/chat_waveform.dart
// Messenger/WhatsApp-शैली voice-note waveform — bar-chart। एउटै widget
// recording (live, दायाँतिर बढ्दै) र पूरा भइसकेको (static preview) दुवैमा
// प्रयोग हुन्छ — फरक यति मात्र हो कि live मा पछिल्लो bar highlight/pulse हुन्छ।
import 'package:flutter/material.dart';

class ChatWaveform extends StatelessWidget {
  /// प्रत्येक bar को उचाइ, 0.0–1.0 सामान्यीकृत। सबैभन्दा पछिल्लो sample
  /// list को अन्त्यमा हुन्छ (list जति लामो भयो, त्यति नै bar देखिन्छन्)।
  final List<double> levels;
  final Color color;
  final bool live;

  const ChatWaveform({
    super.key,
    required this.levels,
    required this.color,
    this.live = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const barWidth = 3.0;
        const gap = 2.5;
        final maxBars = (constraints.maxWidth / (barWidth + gap)).floor();
        final shown = levels.length > maxBars
            ? levels.sublist(levels.length - maxBars)
            : levels;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              _bar(shown[i], isLast: live && i == shown.length - 1),
              if (i != shown.length - 1) const SizedBox(width: gap),
            ],
          ],
        );
      },
    );
  }

  Widget _bar(double level, {required bool isLast}) {
    final h = 4.0 + level.clamp(0.0, 1.0) * 20.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      width: 3,
      height: h,
      decoration: BoxDecoration(
        color: isLast ? color : color.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
