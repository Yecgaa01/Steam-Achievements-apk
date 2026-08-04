import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_text.dart';
import '../models/steam_models.dart';
import '../services/cache_store.dart';
import '../services/steam_api.dart';

class ProfileScreen extends StatefulWidget {
  final SteamProfile profile;
  final ProfileStats stats;
  final AppText text;
  final SteamConfig config;
  final List<SteamGame> games;

  const ProfileScreen({
    super.key,
    required this.profile,
    required this.stats,
    required this.text,
    required this.config,
    required this.games,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _cache = CacheStore();
  final _api = SteamApi();
  late ProfileStats _stats;
  List<_RareAchievement> _rareAchievements = [];
  bool _loadingRareAchievements = true;

  AppText get text => widget.text;

  @override
  void initState() {
    super.initState();
    _stats = widget.stats;
    _loadRareAchievements();
  }

  Future<void> _loadRareAchievements() async {
    setState(() => _loadingRareAchievements = true);
    final cachedGames = await _cache.loadCachedGames(
      widget.config.normalizedSteamId64,
    );
    final games = cachedGames.isNotEmpty ? cachedGames : widget.games;
    final cached = await _rareAchievementsFromCache(games);
    if (!mounted) return;
    setState(() {
      _stats = ProfileStats.fromGames(games);
      _rareAchievements = cached;
      _loadingRareAchievements = false;
    });
  }

  Future<void> _refreshProfileStats() async {
    final currentAppIds = _rareAchievements.map((item) => item.game.appId).toSet();
    final cachedGames = await _cache.loadCachedGames(
      widget.config.normalizedSteamId64,
    );
    final games = cachedGames.isNotEmpty ? cachedGames : widget.games;
    if (!mounted) return;
    setState(() {
      _loadingRareAchievements = true;
    });
    await _refreshShowcaseCandidates(games, currentAppIds: currentAppIds);
    await _loadRareAchievements();
  }

  Future<void> _refreshShowcaseCandidates(List<SteamGame> games,
      {Set<int> currentAppIds = const {}}) async {
    final candidates = games.where((game) => game.hasAchievements).toList()
      ..sort((a, b) {
        final currentA = currentAppIds.contains(a.appId) ? 0 : 1;
        final currentB = currentAppIds.contains(b.appId) ? 0 : 1;
        final currentCompare = currentA.compareTo(currentB);
        if (currentCompare != 0) return currentCompare;
        final playedCompare = b.lastPlayedUnix.compareTo(a.lastPlayedUnix);
        if (playedCompare != 0) return playedCompare;
        final recentCompare = b.playtime2Weeks.compareTo(a.playtime2Weeks);
        if (recentCompare != 0) return recentCompare;
        return b.playtimeForever.compareTo(a.playtimeForever);
      });

    for (final game in candidates.take(30)) {
      try {
        final achievements = await _api.getAchievementsForGame(
          widget.config,
          game,
        );
        await _cache.saveCachedAchievements(
          widget.config.normalizedSteamId64,
          game.appId,
          achievements,
          languageCode: widget.config.languageCode,
        );
      } catch (_) {}
    }
  }

  Future<List<_RareAchievement>> _rareAchievementsFromCache(
      List<SteamGame> games) async {
    final items = <_RareAchievement>[];
    for (final game in games.where((game) => game.hasAchievements)) {
      final achievements = await _cache.loadCachedAchievements(
        widget.config.normalizedSteamId64,
        game.appId,
        languageCode: widget.config.languageCode,
      );
      items.addAll(_rareUnlockedForGame(game, achievements));
    }
    return _topRareAchievements(items);
  }

  List<_RareAchievement> _rareUnlockedForGame(
    SteamGame game,
    List<SteamAchievement> achievements,
  ) {
    return achievements
        .where((achievement) =>
            achievement.achieved &&
            achievement.globalPercent != null &&
            achievement.globalPercent! > 0)
        .map((achievement) =>
            _RareAchievement(game: game, achievement: achievement))
        .toList();
  }

  List<_RareAchievement> _topRareAchievements(List<_RareAchievement> items) {
    final unique = <String, _RareAchievement>{};
    for (final item in items) {
      final key = '${item.game.appId}:${item.achievement.apiName}';
      final existing = unique[key];
      if (existing == null ||
          item.achievement.globalPercent! < existing.achievement.globalPercent!) {
        unique[key] = item;
      }
    }
    final sorted = unique.values.toList()
      ..sort((a, b) {
        final rarity = a.achievement.globalPercent!
            .compareTo(b.achievement.globalPercent!);
        if (rarity != 0) return rarity;
        final game = a.game.name.compareTo(b.game.name);
        if (game != 0) return game;
        return a.achievement.name.compareTo(b.achievement.name);
      });
    return sorted.take(5).toList();
  }

  String _rarityText(double percent) {
    final decimals = percent < 1 ? 2 : 1;
    var value = percent.toStringAsFixed(decimals);
    while (value.contains('.') && value.endsWith('0')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }
    return '$value%';
  }

  String _achievementIconUrl(SteamAchievement achievement) {
    final icon = achievement.icon.trim();
    if (icon.isNotEmpty) return icon;
    return achievement.iconGray.trim();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final subtleText = dark ? Colors.white60 : const Color(0xFF64748B);
    return Scaffold(
      appBar: AppBar(title: Text(text.profileStats)),
      body: RefreshIndicator(
        onRefresh: _refreshProfileStats,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
          children: [
            _profileCard(context),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _rareShowcase(context),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _summaryPanel(context),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(text.statsNote, style: TextStyle(color: subtleText)),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(text.steamProfileSyncWarning,
                  style: TextStyle(color: subtleText, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardColor = scheme.surface;
    final backgroundPath = widget.config.profileBackgroundPath.trim();
    final backgroundFile = backgroundPath.isEmpty ? null : File(backgroundPath);
    final hasBackground = backgroundFile != null && backgroundFile.existsSync();
    return SizedBox(
      height: 136,
      width: double.infinity,
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 4, 0, 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        image: hasBackground
            ? DecorationImage(
                image: FileImage(backgroundFile),
                fit: BoxFit.cover,
                alignment: Alignment.center)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: hasBackground
            ? BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.66),
                    Colors.black.withValues(alpha: 0.32),
                  ],
                ),
              )
            : null,
        child: Row(
          children: [
            CircleAvatar(
              radius: 43.5,
              backgroundImage: widget.profile.avatarUrl.isEmpty
                  ? null
                  : CachedNetworkImageProvider(widget.profile.avatarUrl),
              child: widget.profile.avatarUrl.isEmpty
                  ? const Icon(Icons.person, size: 36)
                  : null,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.profile.personaName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: hasBackground ? Colors.white : null,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'monospace',
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }

  Widget _rareShowcase(BuildContext context) {
    final items = _rareAchievements;
    final scheme = Theme.of(context).colorScheme;
    final cardColors = [scheme.surface, scheme.surface.withValues(alpha: 0.88)];
    final titleColor = scheme.onSurface;
    final subtleColor = scheme.onSurfaceVariant;
    final borderColor = Colors.white.withValues(alpha: 0.05);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: cardColors,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  text.isPt ? 'Conquistas mais raras' : 'Rarest achievements',
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            SizedBox(
              height: 62,
              child: Center(
                child: _loadingRareAchievements
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        text.isPt
                            ? 'Faça o scan completo para montar o showcase.'
                            : 'Run a full scan to build the showcase.',
                        style: TextStyle(
                            color: subtleColor, fontSize: 12),
                      ),
              ),
            )
          else
            Stack(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: items
                      .map((item) => _rareAchievementIcon(context, item))
                      .toList(),
                ),
                if (_loadingRareAchievements)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1220).withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              text.isPt ? 'Carregando...' : 'Loading...',
                              style: const TextStyle(
                                color: Color(0xFFE0F2FE),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _rareAchievementIcon(BuildContext context, _RareAchievement item) {
    final percent = item.achievement.globalPercent ?? 0;
    final glowColor = percent < 1
        ? const Color(0xFFC084FC)
        : percent < 5
            ? const Color(0xFF38BDF8)
            : const Color(0xFF22C55E);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final iconBackground = dark ? const Color(0xFF172033) : const Color(0xFFFFFFFF);
    final borderColor = dark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFB6D7F5).withValues(alpha: 0.78);
    return GestureDetector(
      onTap: () => _showRareAchievementDetails(item),
      child: Container(
        width: 62,
        height: 62,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: iconBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.36),
              blurRadius: 24,
            ),
          ],
          border: Border.all(color: borderColor),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: CachedNetworkImage(
                imageUrl: _achievementIconUrl(item.achievement),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorWidget: (_, __, ___) => Container(
                  color: const Color(0xFF1F2937),
                  child: const Icon(Icons.emoji_events,
                      color: Colors.white70, size: 26),
                ),
              ),
            ),
            Positioned(
              right: -7,
              bottom: -9,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF38BDF8)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.42),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Text(
                  _rarityText(percent),
                  style: const TextStyle(
                    color: Color(0xFFE0F2FE),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatUnlockDateTime(BuildContext context, int unixSeconds) {
    final date =
        DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true)
            .toLocal();
    final localizations = MaterialLocalizations.of(context);
    final dateText = localizations.formatShortDate(date);
    final timeText = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(date),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '$dateText $timeText';
  }

  void _showRareAchievementDetails(_RareAchievement item) {
    final percent = item.achievement.globalPercent;
    final unlockDate = item.achievement.unlockTime > 0
        ? _formatUnlockDateTime(context, item.achievement.unlockTime)
        : '';
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 300,
          height: 206,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.50),
                  blurRadius: 46,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: item.game.headerUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF111827), Color(0xFF0B1220)],
                      ),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.82),
                        Colors.black.withValues(alpha: 0.45),
                        Colors.black.withValues(alpha: 0.70),
                      ],
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.12),
                        Colors.black.withValues(alpha: 0.92),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF172033)
                                  .withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.42),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: _achievementIconUrl(item.achievement),
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: const Color(0xFF1F2937),
                                  child: const Icon(Icons.emoji_events,
                                      color: Colors.white70, size: 24),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.game.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF7DD3FC),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.achievement.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    height: 1.05,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        item.achievement.description.isEmpty
                            ? (text.isPt
                                ? 'Sem descrição disponível.'
                                : 'No description available.')
                            : item.achievement.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFE2E8F0),
                          fontSize: 12,
                          height: 1.30,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          if (percent != null || unlockDate.isNotEmpty)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (unlockDate.isNotEmpty)
                                    Text(
                                      text.isPt
                                          ? 'Desbloqueada em $unlockDate'
                                          : 'Unlocked $unlockDate',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFBAE6FD),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  if (percent != null)
                                    Text(
                                      text.isPt
                                          ? '${_rarityText(percent)} dos jogadores desbloquearam'
                                          : '${_rarityText(percent)} of players unlocked this',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFE0F2FE),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                ],
                              ),
                            )
                          else
                            const Spacer(),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 34),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(text.isPt ? 'Fechar' : 'Close'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [scheme.surface, scheme.surface.withValues(alpha: 0.88)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            color: Colors.white.withValues(alpha: 0.02),
            child: Row(
              children: [
                Expanded(
                  child: _bigStat(context, text.totalPlaytime,
                      '${_stats.totalPlaytimeHours.toStringAsFixed(1)} h',
                      Icons.timer_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _bigStat(context, text.totalGames,
                      '${_stats.totalGames}', Icons.grid_view_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Column(
              children: [
                _summaryLine(
                    context, text.completedGames, '${_stats.completedGames}'),
                _summaryLine(context, text.perfectAchievements,
                    '${_stats.perfectGameAchievements}'),
                _summaryLine(context, text.knownAchievements,
                    '${_stats.totalAchievements}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigStat(
      BuildContext context, String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            child: Icon(icon,
                color: scheme.onSurface.withValues(alpha: 0.12), size: 28),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    maxLines: 1,
                    style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 10),
              Container(
                height: 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF38BDF8), Color(0xFFC084FC)],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(color: scheme.onSurfaceVariant))),
          Text(value,
              style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _RareAchievement {
  final SteamGame game;
  final SteamAchievement achievement;

  const _RareAchievement({required this.game, required this.achievement});
}
