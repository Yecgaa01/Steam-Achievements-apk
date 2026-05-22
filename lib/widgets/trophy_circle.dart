import 'package:flutter/material.dart';

import '../models/steam_models.dart';

class TrophyProgressCircle extends StatelessWidget {
  final double value;
  final double size;
  final double strokeWidth;
  final String label;
  final Color? valueColor;

  const TrophyProgressCircle({
    super.key,
    required this.value,
    required this.label,
    this.size = 58,
    this.strokeWidth = 5,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: value.clamp(0, 1),
              strokeWidth: strokeWidth,
              strokeCap: StrokeCap.round,
              backgroundColor: const Color(0xFF172554),
              valueColor: AlwaysStoppedAnimation(valueColor ?? const Color(0xFF2563EB)),
            ),
          ),
          Text(label, style: TextStyle(fontSize: size * 0.23, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class TrophyCircle extends StatelessWidget {
  final TrophySummary summary;
  final double size;
  final double strokeWidth;

  const TrophyCircle({super.key, required this.summary, this.size = 72, this.strokeWidth = 6});

  @override
  Widget build(BuildContext context) {
    return TrophyProgressCircle(
      value: summary.progress,
      label: '${summary.percent}%',
      size: size,
      strokeWidth: strokeWidth,
    );
  }
}
