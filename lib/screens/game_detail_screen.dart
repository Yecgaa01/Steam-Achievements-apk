import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_text.dart';
import '../models/steam_models.dart';
import '../services/cache_store.dart';
import '../services/pp_guide_service.dart';
import '../services/steam_api.dart';
import '../widgets/achievement_tile.dart';
import '../widgets/progress_bar.dart';

enum AchievementSortMode {
  original,
  alphabeticalAsc,
  alphabeticalDesc,
  unlockDateDesc,
  unlockDateAsc
}

AchievementSortMode _achievementSortModeFromName(String value) {
  if (value == 'alphabetical') return AchievementSortMode.alphabeticalAsc;
  if (value == 'unlockDate') return AchievementSortMode.unlockDateDesc;
  return AchievementSortMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => AchievementSortMode.original,
  );
}

class _AchievementGroupHeader {
  final String title;
  final bool isDlc;
  final bool showCounter;
  final int unlocked;
  final int total;

  const _AchievementGroupHeader({
    required this.title,
    required this.isDlc,
    required this.showCounter,
    required this.unlocked,
    required this.total,
  });
}

class GameDetailScreen extends StatefulWidget {
  final SteamConfig config;
  final SteamGame game;

  final Future<void> Function() onRenewSteamSession;

  const GameDetailScreen({
    super.key,
    required this.config,
    required this.game,
    required this.onRenewSteamSession,
  });

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  final _api = SteamApi();
  final _cache = CacheStore();
  final _guideService = PpGuideService.instance;
  final _searchController = TextEditingController();
  late Future<List<SteamAchievement>> _future;
  bool _showingOfflineCache = false;
  String _filter = 'all';
  AchievementSortMode _sortMode = AchievementSortMode.original;
  Set<String> _pinnedAchievementIds = {};
  late bool _showHiddenLocal;
  SteamGame? _updatedGame;
  AppText get t => AppText(widget.config.languageCode == 'en'
      ? AppLanguage.english
      : AppLanguage.portuguese);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _showHiddenLocal = false;
    _future = _loadAchievements();
    _loadPinnedAchievements();
    _loadSavedViewPreferences();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _showAchievementHelpOnce());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showAchievementHelpOnce() async {
    if (await _cache.loadAchievementHelpShown()) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.achievementHelpTitle),
        content: Text(t.achievementHelpBody),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.gotIt),
          ),
        ],
      ),
    );
    await _cache.saveAchievementHelpShown();
  }

  Future<void> _updateGameSummaryFromAchievements(
      List<SteamAchievement> achievements) async {
    final unlocked =
        achievements.where((achievement) => achievement.achieved).length;
    final latestUnlock = _lastAchievementUnlockTime(achievements);
    final updated = widget.game.copyWith(
      unlocked: unlocked,
      total: achievements.length,
      latestAchievementUnix: latestUnlock,
      progressLoaded: true,
      hasAchievements: achievements.isNotEmpty,
    );
    _updatedGame = updated;
    final steamId = widget.config.normalizedSteamId64;
    final games = await _cache.loadCachedGames(steamId);
    if (games.isEmpty) return;
    final nextGames = games
        .map((game) => game.appId == updated.appId ? updated : game)
        .toList();
    await _cache.saveCachedGames(steamId, nextGames);
  }

  Future<void> _loadSavedViewPreferences() async {
    final steamId = widget.config.normalizedSteamId64;
    final appId = widget.game.appId;
    final savedSort =
        await _cache.loadAchievementSortModeForGame(steamId, appId);
    final savedFilter =
        await _cache.loadAchievementFilterForGame(steamId, appId);
    final savedShowHidden =
        await _cache.loadAchievementShowHiddenLocalForGame(steamId, appId);
    if (!mounted) return;
    setState(() {
      _sortMode = _achievementSortModeFromName(savedSort);
      if (const {'all', 'unlocked', 'missing', 'hidden', 'visible'}
          .contains(savedFilter)) {
        _filter = savedFilter;
      }
      if (savedShowHidden != null) _showHiddenLocal = savedShowHidden;
    });
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

  Future<void> _showSessionExpiredNotice() async {
    if (!mounted || widget.config.loginMode != 'steamSession') return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.steamSessionExpired,
            style: const TextStyle(fontSize: 13, height: 1.1)),
        behavior: SnackBarBehavior.floating,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        action: SnackBarAction(
          label: t.steamSessionLogin,
          onPressed: () async {
            await widget.onRenewSteamSession();
            if (!mounted) return;
            setState(() => _future = _loadAchievementsFromNetwork());
          },
        ),
      ),
    );
  }

  Future<List<SteamAchievement>> _loadAchievements() async {
    final cached = await _cache.loadCachedAchievements(
        widget.config.normalizedSteamId64, widget.game.appId,
        languageCode: widget.config.languageCode);
    if (cached.isNotEmpty) {
      if (mounted) setState(() => _showingOfflineCache = false);
      _refreshAchievementsInBackground();
      return cached;
    }
    return _loadAchievementsFromNetwork();
  }

  Future<List<SteamAchievement>> _loadAchievementsFromNetwork() async {
    try {
      final achievements =
          await _api.getAchievementsForGame(widget.config, widget.game);
      if (achievements.isNotEmpty) {
        await _cache.saveCachedAchievements(
            widget.config.normalizedSteamId64, widget.game.appId, achievements,
            languageCode: widget.config.languageCode);
        await _updateGameSummaryFromAchievements(achievements);
      }
      if (mounted) setState(() => _showingOfflineCache = false);
      return achievements;
    } catch (error) {
      if (error is SteamSessionExpiredException) {
        _showSessionExpiredNotice();
      }
      final cached = await _cache.loadCachedAchievements(
          widget.config.normalizedSteamId64, widget.game.appId,
          languageCode: widget.config.languageCode);
      if (cached.isNotEmpty) {
        if (mounted) setState(() => _showingOfflineCache = true);
        return cached;
      }
      rethrow;
    }
  }

  Future<void> _refreshAchievementsInBackground() async {
    try {
      final achievements = await _loadAchievementsFromNetwork();
      if (!mounted || achievements.isEmpty) return;
      setState(() => _future = Future.value(achievements));
    } catch (_) {}
  }

  Future<void> _openGuideUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showGuideSheet() async {
    final baseFuture =
        _guideService.findBaseGuides(widget.game.name, widget.game.appId);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _GuideSheet(
        gameName: widget.game.name,
        isPt: t.isPt,
        baseFuture: baseFuture,
        loadDlc: () =>
            _guideService.findDlcGuides(widget.game.name, widget.game.appId),
        openUrl: _openGuideUrl,
      ),
    );
  }

  Widget _ppGuideButton() {
    return IconButton(
      tooltip: 'PP Guide',
      onPressed: _showGuideSheet,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.30)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const _PpGuideIcon(size: 22),
    );
  }

  Future<void> _refreshAchievements() async {
    setState(() => _future = _loadAchievementsFromNetwork());
    await _future;
  }

  Future<void> _showAchievementOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.sortAchievements,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _sortChipForSheet(AchievementSortMode.original,
                        t.originalOrder, setSheetState),
                    _sortChipForSheet(AchievementSortMode.alphabeticalAsc,
                        'A-Z', setSheetState),
                    _sortChipForSheet(AchievementSortMode.alphabeticalDesc,
                        'Z-A', setSheetState),
                    _sortChipForSheet(
                        AchievementSortMode.unlockDateDesc,
                        t.isPt ? 'Mais recentes' : 'Newest first',
                        setSheetState),
                    _sortChipForSheet(
                        AchievementSortMode.unlockDateAsc,
                        t.isPt ? 'Mais antigas' : 'Oldest first',
                        setSheetState),
                  ],
                ),
                const SizedBox(height: 18),
                Text(t.visibility,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.showHidden),
                  value: _showHiddenLocal,
                  secondary: const Icon(Icons.visibility_off),
                  onChanged: (value) {
                    setState(() => _showHiddenLocal = value);
                    setSheetState(() {});
                    _cache.saveAchievementShowHiddenLocalForGame(
                        widget.config.normalizedSteamId64,
                        widget.game.appId,
                        value);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<SteamAchievement> _sortAchievements(
      List<SteamAchievement> achievements) {
    final sorted = [...achievements];
    switch (_sortMode) {
      case AchievementSortMode.original:
        return sorted;
      case AchievementSortMode.alphabeticalAsc:
        sorted.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        return sorted;
      case AchievementSortMode.alphabeticalDesc:
        sorted.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        return sorted;
      case AchievementSortMode.unlockDateDesc:
        sorted.sort((a, b) {
          final aTime = a.achieved ? a.unlockTime : 0;
          final bTime = b.achieved ? b.unlockTime : 0;
          final timeCompare = bTime.compareTo(aTime);
          if (timeCompare != 0) return timeCompare;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return sorted;
      case AchievementSortMode.unlockDateAsc:
        sorted.sort((a, b) {
          final aTime = a.achieved ? a.unlockTime : 0;
          final bTime = b.achieved ? b.unlockTime : 0;
          final aSortTime = aTime == 0 ? 1 << 62 : aTime;
          final bSortTime = bTime == 0 ? 1 << 62 : bTime;
          final timeCompare = aSortTime.compareTo(bSortTime);
          if (timeCompare != 0) return timeCompare;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return sorted;
    }
  }

  List<SteamAchievement> _applyFilter(List<SteamAchievement> achievements) {
    final query = _searchController.text.trim().toLowerCase();
    return achievements.where((achievement) {
      if (_filter == 'unlocked' && !achievement.achieved) return false;
      if (_filter == 'missing' && achievement.achieved) return false;
      if (_filter == 'hidden' && !achievement.hidden) return false;
      if (_filter == 'visible' && achievement.hidden) return false;
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

  String _formatPlaytime(int minutes) {
    if (minutes <= 0) return t.unavailableShort;
    final hours = minutes / 60;
    if (hours < 1) {
      return t.isPt ? '$minutes min' : '$minutes min';
    }
    if (hours < 10) {
      return t.isPt
          ? '${hours.toStringAsFixed(1)} h'
          : '${hours.toStringAsFixed(1)} h';
    }
    return '${hours.round()} h';
  }

  Widget _infoLine(String label, String value) {
    return Text(
      '$label: $value',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
          color: Colors.white70,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          shadows: [Shadow(color: Colors.black87, blurRadius: 8)]),
    );
  }

  Widget _dateLine(String label, int unixSeconds) {
    return _infoLine(label, _formatUnixDate(unixSeconds));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_updatedGame);
      },
      child: Scaffold(
        body: FutureBuilder<List<SteamAchievement>>(
          future: _future,
          builder: (context, snapshot) {
            final achievements = snapshot.data ?? const <SteamAchievement>[];
            final unlocked = achievements
                .where((achievement) => achievement.achieved)
                .length;
            final total = achievements.length;
            final progress = total == 0 ? 0.0 : unlocked / total;
            final firstAchievementUnlockTime =
                _firstAchievementUnlockTime(achievements);
            final lastAchievementUnlockTime =
                _lastAchievementUnlockTime(achievements);
            final visibleAchievements =
                _sortAchievements(_applyFilter(achievements));

            return RefreshIndicator(
              onRefresh: _refreshAchievements,
              child: CustomScrollView(
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
                              imageUrl: widget.game.headerUrl,
                              fit: BoxFit.cover),
                          Container(
                              color: Colors.black.withValues(alpha: 0.55)),
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 16,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TrophyProgressBar(
                                    value: progress,
                                    height: 10,
                                    valueColor:
                                        widget.config.goldPerfectGames &&
                                                progress >= 1
                                            ? const Color(0xFFFACC15)
                                            : null),
                                const SizedBox(height: 8),
                                Text(
                                    '${t.achievementsProgress(unlocked, total)} • ${(progress * 100).round()}%',
                                    style:
                                        const TextStyle(color: Colors.white70)),
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
                                _dateLine(t.firstAchievement,
                                    firstAchievementUnlockTime),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _dateLine(t.lastAchievement,
                                              lastAchievementUnlockTime),
                                          const SizedBox(height: 3),
                                          _dateLine(t.lastPlayed,
                                              widget.game.lastPlayedUnix),
                                          const SizedBox(height: 3),
                                          _infoLine(
                                              t.timePlayed,
                                              _formatPlaytime(
                                                  widget.game.playtimeForever)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    _ppGuideButton(),
                                  ],
                                ),
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
                          suffixIcon: IconButton(
                            tooltip: t.sortBy.replaceAll(':', ''),
                            icon: const Icon(Icons.tune),
                            onPressed: _showAchievementOptions,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 46,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                        scrollDirection: Axis.horizontal,
                        children: [
                          _chip('all', t.all),
                          _chip('unlocked', t.isPt ? 'Feitas' : 'Done'),
                          _chip('missing', t.isPt ? 'Faltam' : 'Missing'),
                          _chip('hidden', t.isPt ? 'Ocultas' : 'Hidden'),
                          _chip('visible', t.isPt ? 'Visíveis' : 'Visible'),
                        ],
                      ),
                    ),
                  ),
                  if (snapshot.connectionState != ConnectionState.done)
                    const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()))
                  else if (snapshot.hasError)
                    SliverFillRemaining(
                        child: _error(snapshot.error.toString()))
                  else if (visibleAchievements.isEmpty)
                    SliverFillRemaining(
                        child: Center(child: Text(t.noAchievementForFilter)))
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final items =
                              _buildAchievementRows(visibleAchievements);
                          final item = items[index];
                          if (item is _AchievementGroupHeader) {
                            return _groupHeader(item);
                          }
                          final achievement = item as SteamAchievement;
                          return AchievementTile(
                            achievement: achievement,
                            text: t,
                            revealHiddenByDefault: _showHiddenLocal,
                            showObtainabilityBadge:
                                widget.config.showObtainabilityBadges,
                            isPinned: _pinnedAchievementIds
                                .contains(achievement.apiName),
                            onTogglePinned: () =>
                                _togglePinnedAchievement(achievement),
                          );
                        },
                        childCount:
                            _buildAchievementRows(visibleAchievements).length,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
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
        achievements.any((achievement) => achievement.groupName.isNotEmpty);
    final rows = <Object>[];
    if (pinned.isNotEmpty) {
      rows.add(_groupHeaderData(t.pinnedAchievements, pinned, false, true));
      rows.addAll(pinned);
    }
    if (!hasGroups) {
      rows.addAll(remaining);
      return rows;
    }

    final allBaseGame = <SteamAchievement>[];
    final allGrouped = <String, List<SteamAchievement>>{};
    for (final achievement in achievements) {
      if (achievement.groupName.isEmpty) {
        allBaseGame.add(achievement);
      } else {
        allGrouped
            .putIfAbsent(achievement.groupName, () => [])
            .add(achievement);
      }
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
      rows.add(_groupHeaderData(t.baseGame, allBaseGame, false, true));
      rows.addAll(baseGame);
    }
    for (final entry in grouped.entries) {
      rows.add(_groupHeaderData(
          entry.key, allGrouped[entry.key] ?? entry.value, true, true));
      rows.addAll(entry.value);
    }
    return rows;
  }

  _AchievementGroupHeader _groupHeaderData(String title,
      List<SteamAchievement> achievements, bool isDlc, bool showCounter) {
    return _AchievementGroupHeader(
      title: title,
      isDlc: isDlc,
      showCounter: showCounter,
      unlocked:
          achievements.where((achievement) => achievement.achieved).length,
      total: achievements.length,
    );
  }

  Widget _groupHeader(_AchievementGroupHeader group) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final textColor = dark ? Colors.white : const Color(0xFF475569);
    final subtleColor = dark ? Colors.white38 : const Color(0xFF94A3B8);
    final dividerColor = dark
        ? Colors.white.withValues(alpha: group.isDlc ? 0.09 : 0.12)
        : const Color(0xFFE2E8F0);
    final icon = group.title == t.pinnedAchievements
        ? Icons.push_pin
        : group.isDlc
            ? Icons.extension
            : Icons.sports_esports;
    final iconColor = group.title == t.pinnedAchievements
        ? const Color(0xFFFFD700)
        : group.isDlc
            ? const Color(0xFF38BDF8)
            : (dark ? Colors.lightBlueAccent : const Color(0xFF0284C7));

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: dividerColor)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                group.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5),
              ),
            ),
            if (group.showCounter)
              Text(
                group.title == t.pinnedAchievements
                    ? '${group.total}'
                    : '${group.unlocked}/${group.total}',
                style: TextStyle(
                    color: subtleColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String value, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        selected: _filter == value,
        onSelected: (_) {
          setState(() => _filter = value);
          _cache.saveAchievementFilterForGame(
              widget.config.normalizedSteamId64, widget.game.appId, value);
        },
      ),
    );
  }

  Widget _sortChipForSheet(AchievementSortMode value, String label,
      void Function(void Function()) setSheetState) {
    return ChoiceChip(
      label: Text(label),
      selected: _sortMode == value,
      onSelected: (_) {
        setState(() => _sortMode = value);
        setSheetState(() {});
        _cache.saveAchievementSortModeForGame(
            widget.config.normalizedSteamId64, widget.game.appId, value.name);
      },
    );
  }

  String _shortErrorCode(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('timeoutexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('network') ||
        lower.contains('connection')) {
      return t.offlineAchievementsNoCache;
    }
    final status = RegExp(r'\b(\d{3})\b').firstMatch(error)?.group(1);
    if (status != null) return 'Erro $status';
    if (lower.contains('session')) return 'Erro sessão';
    return 'Erro';
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
            Text(_shortErrorCode(error),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _PpGuideIcon extends StatelessWidget {
  final double size;
  const _PpGuideIcon({this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
          painter:
              _PpGuideIconPainter(IconTheme.of(context).color ?? Colors.white)),
    );
  }
}

class _PpGuideIconPainter extends CustomPainter {
  final Color color;
  const _PpGuideIconPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final left = Path()
      ..moveTo(size.width * .5, size.height * .26)
      ..cubicTo(size.width * .38, size.height * .16, size.width * .22,
          size.height * .14, size.width * .12, size.height * .18)
      ..lineTo(size.width * .12, size.height * .78)
      ..cubicTo(size.width * .28, size.height * .74, size.width * .40,
          size.height * .77, size.width * .5, size.height * .88)
      ..close();
    final right = Path()
      ..moveTo(size.width * .5, size.height * .26)
      ..cubicTo(size.width * .62, size.height * .16, size.width * .78,
          size.height * .14, size.width * .88, size.height * .18)
      ..lineTo(size.width * .88, size.height * .78)
      ..cubicTo(size.width * .72, size.height * .74, size.width * .60,
          size.height * .77, size.width * .5, size.height * .88)
      ..close();
    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint);
    for (final y in [.37, .5, .63]) {
      canvas.drawLine(Offset(size.width * .22, size.height * y),
          Offset(size.width * .42, size.height * y), paint);
      canvas.drawLine(Offset(size.width * .58, size.height * y),
          Offset(size.width * .78, size.height * y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GuideSheet extends StatefulWidget {
  final String gameName;
  final bool isPt;
  final Future<GuideResult> baseFuture;
  final Future<List<GuideItem>> Function() loadDlc;
  final void Function(String url) openUrl;

  const _GuideSheet({
    required this.gameName,
    required this.isPt,
    required this.baseFuture,
    required this.loadDlc,
    required this.openUrl,
  });

  @override
  State<_GuideSheet> createState() => _GuideSheetState();
}

class _GuideSheetState extends State<_GuideSheet> {
  Future<List<GuideItem>>? _dlcFuture;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: FutureBuilder<GuideResult>(
          future: widget.baseFuture,
          builder: (context, snapshot) {
            final result = snapshot.data;
            if (result != null && result.canLoadDlc && _dlcFuture == null) {
              _dlcFuture = widget.loadDlc();
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
                  child: Row(
                    children: [
                      const _PpGuideIcon(size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.isPt ? 'Guias' : 'Guides',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w900)),
                            Text(widget.gameName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12)),
                            Text(
                              widget.isPt
                                  ? 'Nem todos os jogos terão guia. Guias apenas em inglês; use o tradutor do navegador se precisar.'
                                  : 'Not every game will have a guide. Guides are in English; use your browser translator if needed.',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Text(
                    'PP = PowerPyx • PSNP = PSNProfiles • PST = PlayStationTrophies',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
                    children: [
                      if (snapshot.connectionState != ConnectionState.done)
                        const Padding(
                          padding: EdgeInsets.all(18),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (result == null || result.base.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Text(
                            widget.isPt
                                ? 'Nenhum guia encontrado.'
                                : 'No guides found.',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        )
                      else ...[
                        _section(
                            context, widget.isPt ? 'Jogo base' : 'Base game'),
                        ..._groupedRows(result.base),
                        if (result.canLoadDlc) ...[
                          _section(
                              context,
                              widget.isPt
                                  ? 'DLC / Expansões'
                                  : 'DLC / Expansions'),
                          FutureBuilder<List<GuideItem>>(
                            future: _dlcFuture,
                            builder: (context, dlcSnapshot) {
                              if (dlcSnapshot.connectionState !=
                                  ConnectionState.done) {
                                return _loadingRow(
                                    context,
                                    widget.isPt
                                        ? 'Carregando DLCs...'
                                        : 'Loading DLCs...');
                              }
                              final dlcs = dlcSnapshot.data ?? const [];
                              if (dlcs.isEmpty) return const SizedBox.shrink();
                              return Column(children: _groupedRows(dlcs));
                            },
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 7),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: .7)),
    );
  }

  Widget _loadingRow(BuildContext context, String label) {
    return Card(
      child: ListTile(
        leading: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text(label),
      ),
    );
  }

  List<Widget> _groupedRows(List<GuideItem> items) {
    final grouped = <String, List<GuideItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.label, () => []).add(item);
    }
    return grouped.entries
        .map((entry) => Card(
              child: ListTile(
                title: Text(entry.key,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: entry.value
                      .map((item) => ActionChip(
                            label: Text(_sourceShort(item.source)),
                            onPressed: () => widget.openUrl(item.url),
                          ))
                      .toList(),
                ),
              ),
            ))
        .toList();
  }

  String _sourceShort(String source) {
    switch (source) {
      case 'pp':
        return 'PP';
      case 'pst':
        return 'PST';
      case 'psnp':
        return 'PSNP';
      default:
        return source.toUpperCase();
    }
  }
}
