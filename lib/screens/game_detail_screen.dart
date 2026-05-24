import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_text.dart';
import '../models/steam_models.dart';
import '../services/cache_store.dart';
import '../services/steam_api.dart';
import '../widgets/achievement_tile.dart';
import '../widgets/progress_bar.dart';

class GameDetailScreen extends StatefulWidget {
  final SteamConfig config;
  final SteamGame game;

  const GameDetailScreen({super.key, required this.config, required this.game});

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  final _api = SteamApi();
  final _cache = CacheStore();
  final _searchController = TextEditingController();
  late Future<List<SteamAchievement>> _future;
  bool _showingOfflineCache = false;
  bool _refreshingCachedAchievements = false;
  String _filter = 'all';
  Set<String> _pinnedAchievementIds = {};
  late bool _showHiddenLocal;
  AppText get t => AppText(widget.config.languageCode == 'en'
      ? AppLanguage.english
      : AppLanguage.portuguese);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _showHiddenLocal = widget.config.showHidden;
    _future = _loadAchievements();
    _loadPinnedAchievements();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPinnedAchievements() async {
    final pinned = await _cache.loadPinnedAchievementIds(
        widget.config.normalizedSteamId64, widget.game.appId);
    if (!mounted) return;
    setState(() => _pinnedAchievementIds = pinned);
  }

  Future<void> _togglePinnedAchievement(SteamAchievement achievement) async {
    final next = {..._pinnedAchievementIds};
    final pinned = next.remove(achievement.apiName);
    if (!pinned) next.add(achievement.apiName);
    setState(() => _pinnedAchievementIds = next);
    await _cache.savePinnedAchievementIds(
        widget.config.normalizedSteamId64, widget.game.appId, next);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pinned ? t.achievementUnpinned : t.achievementPinned)));
  }

  Future<List<SteamAchievement>> _loadAchievements() async {
    try {
      final fresh =
          await _api.getAchievementsForGame(widget.config, widget.game);
      if (fresh.isNotEmpty) {
        await _cache.saveCachedAchievements(
            widget.config.normalizedSteamId64, widget.game.appId, fresh);
        if (mounted) setState(() => _showingOfflineCache = false);
        return fresh;
      }
    } catch (_) {
      // Fall back to cache below.
    }

    final cached = await _cache.loadCachedAchievements(
        widget.config.normalizedSteamId64, widget.game.appId);
    if (cached.isNotEmpty) {
      if (mounted) setState(() => _showingOfflineCache = true);
      _refreshAchievementsInBackground();
      return cached;
    }
    final achievements =
        await _api.getAchievementsForGame(widget.config, widget.game);
    if (achievements.isNotEmpty) {
      await _cache.saveCachedAchievements(
          widget.config.normalizedSteamId64, widget.game.appId, achievements);
    }
    if (mounted) setState(() => _showingOfflineCache = false);
    return achievements;
  }

  Future<void> _refreshAchievementsInBackground() async {
    if (_refreshingCachedAchievements) return;
    _refreshingCachedAchievements = true;
    try {
      final achievements =
          await _api.getAchievementsForGame(widget.config, widget.game);
      if (achievements.isEmpty) return;
      await _cache.saveCachedAchievements(
          widget.config.normalizedSteamId64, widget.game.appId, achievements);
      if (!mounted) return;
      setState(() {
        _showingOfflineCache = false;
        _future = Future.value(achievements);
      });
    } catch (_) {
      // Keep the existing cached achievements on transient network/API failures.
    } finally {
      _refreshingCachedAchievements = false;
    }
  }

  List<SteamAchievement> _applyFilter(List<SteamAchievement> achievements) {
    final query = _searchController.text.trim().toLowerCase();
    return achievements.where((achievement) {
      if (_filter == 'unlocked' && !achievement.achieved) return false;
      if (_filter == 'missing' && achievement.achieved) return false;
      if (_filter == 'hidden' && !achievement.hidden) return false;
      if (query.isEmpty) return true;
      return achievement.name.toLowerCase().contains(query) ||
          achievement.description.toLowerCase().contains(query) ||
          achievement.apiName.toLowerCase().contains(query);
    }).toList();
  }

  int _firstAchievementUnlockTime(List<SteamAchievement> achievements) {
    final unlockTimes = achievements
        .where(
            (achievement) => achievement.achieved && achievement.unlockTime > 0)
        .map((achievement) => achievement.unlockTime)
        .toList();
    if (unlockTimes.isEmpty) return 0;
    unlockTimes.sort();
    return unlockTimes.first;
  }

  int _lastAchievementUnlockTime(List<SteamAchievement> achievements) {
    final unlockTimes = achievements
        .where(
            (achievement) => achievement.achieved && achievement.unlockTime > 0)
        .map((achievement) => achievement.unlockTime)
        .toList();
    if (unlockTimes.isEmpty) return 0;
    unlockTimes.sort();
    return unlockTimes.last;
  }

  String _formatUnixDate(int unixSeconds) {
    if (unixSeconds <= 0) return t.unavailableShort;
    final date =
        DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true)
            .toLocal();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    if (t.isPt) return '$day/$month/${date.year}';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String? _progressTierLabel() {
    if (!widget.config.showProgressTiers ||
        !widget.game.progressLoaded ||
        !widget.game.hasAchievements) {
      return null;
    }
    final percent = (widget.game.progress * 100).round();
    if (percent <= 0) {
      return '🛒 ${t.tierBoughtOnSale}';
    }
    if (percent <= 33) {
      return t.tierBronze;
    }
    if (percent <= 66) {
      return t.tierSilver;
    }
    if (percent < 100) {
      return t.tierGold;
    }
    return '🏅 ${t.tierPerfect}';
  }

  Color _progressTierColor(String label) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (label.contains('promoção') || label.contains('sale')) {
      return dark ? const Color(0xFF9CA3AF) : const Color(0xFF64748B);
    }
    if (label == t.tierBronze) return const Color(0xFFCD7F32);
    if (label == t.tierSilver) {
      return dark ? const Color(0xFFC0C0C0) : const Color(0xFF8A8F98);
    }
    if (label == t.tierGold) {
      return dark ? const Color(0xFFFFD700) : const Color(0xFFB8860B);
    }
    if (label.contains(t.tierPerfect)) {
      return dark ? const Color(0xFFB9F2FF) : const Color(0xFF64748B);
    }
    return Colors.white70;
  }

  Widget _dateLine(String label, int unixSeconds) {
    return Text(
      '$label: ${_formatUnixDate(unixSeconds)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
          color: Colors.white70,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(color: Colors.black87, blurRadius: 8)]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<SteamAchievement>>(
        future: _future,
        builder: (context, snapshot) {
          final achievements = snapshot.data ?? const <SteamAchievement>[];
          final unlocked =
              achievements.where((achievement) => achievement.achieved).length;
          final total = achievements.length;
          final progress = total == 0 ? 0.0 : unlocked / total;
          final firstAchievementUnlockTime =
              _firstAchievementUnlockTime(achievements);
          final lastAchievementUnlockTime =
              _lastAchievementUnlockTime(achievements);
          final visibleAchievements = _applyFilter(achievements);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 225,
                pinned: true,
                title: Text(widget.game.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                          imageUrl: widget.game.headerUrl, fit: BoxFit.cover),
                      Container(color: Colors.black.withValues(alpha: 0.55)),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.game.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 8),
                            TrophyProgressBar(
                                value: progress,
                                height: 10,
                                valueColor: widget.config.goldPerfectGames &&
                                        progress >= 1
                                    ? const Color(0xFFFACC15)
                                    : null),
                            const SizedBox(height: 8),
                            Text(
                                '${t.achievementsProgress(unlocked, total)} • ${(progress * 100).round()}%',
                                style: const TextStyle(color: Colors.white70)),
                            if (_progressTierLabel() != null) ...[
                              const SizedBox(height: 3),
                              Builder(builder: (context) {
                                final tier = _progressTierLabel()!;
                                return Text(tier,
                                    style: TextStyle(
                                        color: _progressTierColor(tier),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w900,
                                        shadows: const [
                                          Shadow(
                                              color: Colors.black87,
                                              blurRadius: 8)
                                        ]));
                              }),
                            ],
                            const SizedBox(height: 6),
                            _dateLine(
                                t.firstAchievement, firstAchievementUnlockTime),
                            const SizedBox(height: 3),
                            _dateLine(
                                t.lastAchievement, lastAchievementUnlockTime),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showingOfflineCache)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: Text(t.offlineAchievementsCache,
                        style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12)),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: t.searchAchievement,
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chip('all', t.all),
                      _chip('unlocked', t.unlocked),
                      _chip('missing', t.missing),
                      _chip('hidden', t.hidden),
                      FilterChip(
                        label: Text(t.showHidden),
                        selected: _showHiddenLocal,
                        avatar: const Icon(Icons.visibility_off, size: 16),
                        onSelected: (value) =>
                            setState(() => _showHiddenLocal = value),
                      ),
                    ],
                  ),
                ),
              ),
              if (snapshot.connectionState != ConnectionState.done)
                const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()))
              else if (snapshot.hasError)
                SliverFillRemaining(child: _error(snapshot.error.toString()))
              else if (visibleAchievements.isEmpty)
                SliverFillRemaining(
                    child: Center(child: Text(t.noAchievementForFilter)))
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final items = _buildAchievementRows(visibleAchievements);
                      final item = items[index];
                      if (item is String) return _groupHeader(item);
                      final achievement = item as SteamAchievement;
                      return AchievementTile(
                        achievement: achievement,
                        text: t,
                        revealHiddenByDefault: _showHiddenLocal,
                        showRarityTier: widget.config.showRarityTiers,
                        showObtainabilityBadge:
                            widget.config.showObtainabilityBadges,
                        isPinned:
                            _pinnedAchievementIds.contains(achievement.apiName),
                        onTogglePinned: () =>
                            _togglePinnedAchievement(achievement),
                      );
                    },
                    childCount:
                        _buildAchievementRows(visibleAchievements).length,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<Object> _buildAchievementRows(List<SteamAchievement> achievements) {
    final pinned = achievements
        .where((achievement) =>
            _pinnedAchievementIds.contains(achievement.apiName))
        .toList();
    final remaining = achievements
        .where((achievement) =>
            !_pinnedAchievementIds.contains(achievement.apiName))
        .toList();
    final hasGroups = widget.config.separateDlcAchievements &&
        remaining.any((achievement) => achievement.groupName.isNotEmpty);
    final rows = <Object>[];
    if (pinned.isNotEmpty) {
      rows.add(t.pinnedAchievements);
      rows.addAll(pinned);
    }
    if (!hasGroups) {
      rows.addAll(remaining);
      return rows;
    }

    final baseGame = <SteamAchievement>[];
    final grouped = <String, List<SteamAchievement>>{};
    for (final achievement in remaining) {
      if (achievement.groupName.isEmpty) {
        baseGame.add(achievement);
      } else {
        grouped.putIfAbsent(achievement.groupName, () => []).add(achievement);
      }
    }

    if (baseGame.isNotEmpty) {
      rows.add(t.baseGame);
      rows.addAll(baseGame);
    }
    for (final entry in grouped.entries) {
      rows.add(entry.key);
      rows.addAll(entry.value);
    }
    return rows;
  }

  Widget _groupHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          const Icon(Icons.extension, size: 18, color: Colors.lightBlueAccent),
          const SizedBox(width: 8),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15))),
        ],
      ),
    );
  }

  Widget _chip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _error(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(t.loadAchievementsFailed,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
