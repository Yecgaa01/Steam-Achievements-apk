import 'package:flutter/material.dart';

class TrophyProgressBar extends StatelessWidget {
  final double value;
  final double height;
  final Color? valueColor;

  const TrophyProgressBar({super.key, required this.value, this.height = 8, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        minHeight: height,
        value: value.clamp(0, 1),
        backgroundColor: const Color(0xFF1F2937),
        valueColor: AlwaysStoppedAnimation(valueColor ?? const Color(0xFF2563EB)),
      ),
    );
  }
}
