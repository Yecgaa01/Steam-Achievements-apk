import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/steam_models.dart';
import 'progress_bar.dart';
import 'trophy_circle.dart';

class GameCard extends StatelessWidget {
  final SteamGame game;
  final VoidCallback onTap;
  final String tapToLoad;
  final String noAchievements;
  final VoidCallback? onLongPress;
  final String? tierLabel;
  final bool goldPerfect;

  const GameCard({super.key, required this.game, required this.onTap, required this.tapToLoad, required this.noAchievements, this.onLongPress, this.tierLabel, this.goldPerfect = false});

  @override
  Widget build(BuildContext context) {
    final percent = (game.progress * 100).round();
    final perfectGold = goldPerfect && game.progressLoaded && game.hasAchievements && game.progress >= 1;
    final hours = game.playtimeForever / 60;
    final hoursText = hours >= 1 ? '${hours.toStringAsFixed(1)} h' : '${game.playtimeForever} min';
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF111827) : Colors.white;
    final subtleText = dark ? Colors.white60 : const Color(0xFF64748B);
    final tierTextColor = perfectGold ? const Color(0xFFD97706) : (dark ? Colors.white70 : const Color(0xFF334155));
    final placeholderColor = dark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);
    final placeholderIconColor = dark ? Colors.white54 : const Color(0xFF64748B);
    Color tierColor() {
      final label = tierLabel ?? '';
      if (label.contains('promoção') || label.contains('sale')) return dark ? const Color(0xFF9CA3AF) : const Color(0xFF64748B);
      if (label == 'Bronze') return const Color(0xFFCD7F32);
      if (label == 'Prata' || label == 'Silver') return dark ? const Color(0xFFC0C0C0) : const Color(0xFF8A8F98);
      if (label == 'Ouro' || label == 'Gold') return dark ? const Color(0xFFFFD700) : const Color(0xFFB8860B);
      if (label.contains('Perfei') || label.contains('Perfect')) return dark ? const Color(0xFFB9F2FF) : const Color(0xFF64748B);
      return tierTextColor;
    }

    final progressText = !game.progressLoaded
        ? '$tapToLoad • $hoursText'
        : (!game.hasAchievements ? '$noAchievements • $hoursText' : '${game.unlocked}/${game.total} achievements • $hoursText');
    final tierText = tierLabel;

    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: game.headerUrl,
                  width: 112,
                  height: 52,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 112,
                    height: 52,
                    color: placeholderColor,
                    child: Icon(Icons.sports_esports, color: placeholderIconColor),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(game.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    TrophyProgressBar(value: game.progress, valueColor: perfectGold ? const Color(0xFFFACC15) : null),
                    const SizedBox(height: 6),
                    Text(progressText, style: TextStyle(color: game.hasAchievements ? subtleText : Colors.amber.shade700, fontSize: 12)),
                    if (tierLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(tierText!, style: TextStyle(color: tierColor(), fontSize: 12, fontWeight: FontWeight.w900)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (!game.progressLoaded)
                SizedBox(width: 46, height: 46, child: CircularProgressIndicator(strokeWidth: 4, color: Colors.blue.shade500, backgroundColor: const Color(0xFF172554)))
              else if (game.hasAchievements)
                TrophyProgressCircle(value: game.progress, label: '$percent%', size: 54, strokeWidth: 5, valueColor: perfectGold ? const Color(0xFFFACC15) : null)
              else
                const Icon(Icons.block, color: Colors.amberAccent),
            ],
          ),
        ),
      ),
    );
  }
}
