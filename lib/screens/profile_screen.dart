import 'package:flutter/material.dart';

import '../app_text.dart';
import '../models/steam_models.dart';

class ProfileScreen extends StatelessWidget {
  final SteamProfile profile;
  final ProfileStats stats;
  final AppText text;

  const ProfileScreen({super.key, required this.profile, required this.stats, required this.text});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final subtleText = dark ? Colors.white60 : const Color(0xFF64748B);
    return Scaffold(
      appBar: AppBar(title: Text(text.profileStats)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CircleAvatar(radius: 34, backgroundImage: profile.avatarUrl.isEmpty ? null : NetworkImage(profile.avatarUrl)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.personaName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                    Text(profile.steamId64, style: TextStyle(color: subtleText, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _stat(context, text.totalPlaytime, '${stats.totalPlaytimeHours.toStringAsFixed(1)} h'),
          _stat(context, text.totalGames, '${stats.totalGames}'),
          _stat(context, text.completedGames, '${stats.completedGames}'),
          _stat(context, text.perfectAchievements, '${stats.perfectGameAchievements}'),
          _stat(context, text.knownAchievements, '${stats.totalAchievements}'),
          _stat(context, text.scannedGames, '${stats.loadedGames}'),
          const SizedBox(height: 14),
          Text(text.statsNote, style: TextStyle(color: subtleText)),
          const SizedBox(height: 10),
          Text(text.steamProfileSyncWarning, style: TextStyle(color: subtleText, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF111827) : Colors.white;
    final borderColor = dark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);
    final subtleText = dark ? Colors.white70 : const Color(0xFF475569);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: subtleText))),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
