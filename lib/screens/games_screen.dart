import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_text.dart';
import '../models/steam_models.dart';
import '../services/cache_store.dart';
import '../services/steam_api.dart';
import '../services/steam_session_service.dart';
import '../widgets/game_card.dart';
import '../widgets/trophy_circle.dart';
import 'game_detail_screen.dart';
import 'profile_screen.dart';

enum GameSortMode { alphabetical, recent, completion, playtime }

GameSortMode _gameSortModeFromName(String value) {
  return GameSortMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => GameSortMode.alphabetical,
  );
}

class GamesScreen extends StatefulWidget {
  final SteamConfig config;
  final Future<void> Function() onRenewSteamSession;
  final Future<String?> Function() onOpenSettings;

  const GamesScreen({
    super.key,
    required this.config,
    required this.onRenewSteamSession,
    required this.onOpenSettings,
  });

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> with WidgetsBindingObserver {
  static const _batchSize = 10;

  final _api = SteamApi();
  final _cache = CacheStore();
  final _sessionService = SteamSessionService();
  final _searchController = TextEditingController();
  final _manualGameController = TextEditingController();
  final _scrollController = ScrollController();

  SteamProfile? _profile;
  List<SteamGame> _games = [];
  List<_RecentAchievement> _recentAchievements = [];
  bool _initialLoading = true;
  bool _progressLoading = false;
  bool _typeLoading = false;
  String? _error;
  int _visibleCount = 25;
  GameSortMode _sortMode = GameSortMode.alphabetical;
  Set<int> _hiddenGameAppIds = {};
  bool _showOnlyHiddenGames = false;
  bool _sessionNoticeShown = false;
  DateTime? _lastAutoRefreshAt;
  bool _autoRefreshRunning = false;

  AppText get t => AppText(widget.config.languageCode == 'en'
      ? AppLanguage.english
      : AppLanguage.portuguese);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(() => setState(() {}));
    _scrollController.addListener(_onScroll);
    _loadSavedSortMode();
    _loadInitial();
    _checkSteamSessionProactively();
  }

  Future<void> _loadSavedSortMode() async {
    final saved = await _cache.loadGameSortMode();
    if (!mounted) return;
    setState(() => _sortMode = _gameSortModeFromName(saved));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _refreshOnResume();
      _checkSteamSessionProactively();
    }
  }

  Future<void> _refreshOnResume() async {
    if (!widget.config.isComplete || _initialLoading || _autoRefreshRunning) {
      return;
    }
    final now = DateTime.now();
    final last = _lastAutoRefreshAt;
    if (last != null && now.difference(last) < const Duration(minutes: 2)) {
      return;
    }
    _lastAutoRefreshAt = now;
    _autoRefreshRunning = true;
    try {
      await _loadInitial(showBlockingLoader: false, forceVisibleProgress: true);
    } finally {
      _autoRefreshRunning = false;
    }
  }

  @override
  void didUpdateWidget(covariant GamesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final profileChanged = oldWidget.config.normalizedSteamId64 !=
            widget.config.normalizedSteamId64 ||
        oldWidget.config.normalizedApiKey != widget.config.normalizedApiKey;
    final hideSoftwareChanged =
        oldWidget.config.hideSoftware != widget.config.hideSoftware;
    if (!profileChanged) {
      if (hideSoftwareChanged && widget.config.hideSoftware) {
        _loadVisibleAppTypes();
      }
      return;
    }
    setState(() {
      _profile = null;
      _games = [];
      _error = null;
      _initialLoading = true;
      _progressLoading = false;
      _typeLoading = false;
      _visibleCount = 40;
      _showOnlyHiddenGames = false;
    });
    _loadInitial();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _manualGameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkSteamSessionProactively() async {
    if (widget.config.loginMode != 'steamSession' || _sessionNoticeShown) return;
    final status = await _sessionService.checkSessionStatus();
    if (!mounted || status != SteamSessionStatus.expired) return;
    _sessionNoticeShown = true;
    _showSessionExpiredNotice();
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
            _sessionNoticeShown = false;
            if (!mounted) return;
            await _loadInitial(showBlockingLoader: false, forceVisibleProgress: true);
          },
        ),
      ),
    );
  }

  Future<void> _loadInitial(
      {bool showBlockingLoader = true,
      bool forceVisibleProgress = false}) async {
    if (!widget.config.isComplete) {
      setState(() => _initialLoading = false);
      return;
    }
    if (showBlockingLoader) {
      setState(() {
        _initialLoading = true;
        _error = null;
        _visibleCount = 25;
      });
    } else {
      setState(() {
        _error = null;
        _visibleCount = 25;
      });
    }
    final steamId = widget.config.normalizedSteamId64;
    try {
      final hiddenGameAppIds = await _cache.loadHiddenGameAppIds();
      final cachedProfile = await _cache.loadCachedProfile(steamId);
      final cachedGames = await _cache.loadCachedGames(steamId);
      if (cachedProfile != null || cachedGames.isNotEmpty) {
        setState(() {
          _hiddenGameAppIds = hiddenGameAppIds;
          if (cachedProfile != null) _profile = cachedProfile;
          if (cachedGames.isNotEmpty) {
            _games = cachedGames;
            _loadRecentAchievementsFromCache(cachedGames);
          }
          _initialLoading = false;
        });
      }

      final profile = await _api.getProfile(widget.config);
      final freshGames = await _api.getOwnedGames(widget.config);
      final recentlyPlayed = await _api
          .getRecentlyPlayedGames(widget.config)
          .catchError((_) => const <SteamGame>[]);
      final recentByApp = {for (final game in recentlyPlayed) game.appId: game};
      final recentOrder = {
        for (var index = 0; index < recentlyPlayed.length; index++)
          recentlyPlayed[index].appId: index
      };
      final cachedByApp = {for (final game in _games) game.appId: game};
      final freshAppIds = freshGames.map((game) => game.appId).toSet();
      final manualGames = cachedGames
          .where((game) =>
              (game.manuallyAdded || game.sourceUrl.isNotEmpty) &&
              !freshAppIds.contains(game.appId))
          .map((game) {
        final recent = recentByApp[game.appId];
        if (recent == null) return game;
        final fallbackRecentTime =
            DateTime.now().millisecondsSinceEpoch ~/ 1000 -
                (recentOrder[game.appId] ?? 0);
        return game.copyWith(
          playtimeForever: recent.playtimeForever > 0
              ? recent.playtimeForever
              : game.playtimeForever,
          playtime2Weeks: recent.playtime2Weeks > 0
              ? recent.playtime2Weeks
              : game.playtime2Weeks,
          lastPlayedUnix: recent.lastPlayedUnix > 0
              ? recent.lastPlayedUnix
              : fallbackRecentTime,
        );
      }).toList();
      final merged = [
        ...freshGames.map((game) {
          final cached = cachedByApp[game.appId];
          if (cached == null) return game;
          final cachedAppType = cached.appType;
          final cachedTypeLoaded = cached.typeLoaded;
          return game.copyWith(
            unlocked: cached.unlocked,
            total: cached.total,
            latestAchievementUnix: cached.latestAchievementUnix,
            progressLoaded: cached.progressLoaded,
            hasAchievements: cached.hasAchievements,
            appType: cachedAppType,
            typeLoaded: cachedTypeLoaded,
            manuallyAdded: cached.manuallyAdded,
            sourceUrl: cached.sourceUrl,
            storeHeaderUrl: cached.storeHeaderUrl.isNotEmpty
                ? cached.storeHeaderUrl
                : game.storeHeaderUrl,
          );
        }),
        ...manualGames,
      ];
      await _cache.saveCachedProfile(steamId, profile);
      await _cache.saveCachedGames(steamId, merged);
      setState(() {
        _profile = profile;
        _games = merged;
        _initialLoading = false;
      });
      _loadRecentAchievementsFromCache(merged);
      _loadStartupProgress(forceRecent: forceVisibleProgress);
      if (widget.config.hideSoftware) {
        _loadVisibleAppTypes();
      }
    } catch (error) {
      if (error is SteamSessionExpiredException) {
        _showSessionExpiredNotice();
      }
      if (_games.isEmpty && _profile == null) {
        setState(() {
          _error = error.toString();
          _initialLoading = false;
        });
      } else {
        setState(() => _initialLoading = false);
      }
    }
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 900) {
      if (_visibleCount < _games.length) {
        setState(() => _visibleCount =
            (_visibleCount + _batchSize).clamp(0, _games.length));
      }
      _loadVisibleAppTypes();
      _loadVisibleProgress();
    }
  }

  List<SteamGame> _visibleScanCandidates({
    required bool Function(SteamGame game) matches,
  }) {
    return _filteredAndSorted(_games, includeUnloadedNoAchievementGames: true)
        .take((_visibleCount + _batchSize).clamp(0, _games.length))
        .where(matches)
        .take(_batchSize)
        .toList();
  }

  Future<void> _loadVisibleAppTypes() async {
    if (_typeLoading || !widget.config.hideSoftware) return;
    final candidates = _visibleScanCandidates(
      matches: (game) => !game.typeLoaded || game.appType == 'unknown',
    );
    if (candidates.isEmpty) return;
    _typeLoading = true;
    final details =
        await _api.getAppDetails(candidates.map((game) => game.appId).toList());
    if (!mounted) return;
    setState(() {
      for (final game in candidates) {
        final detail = details[game.appId];
        final index = _games.indexWhere((item) => item.appId == game.appId);
        if (index >= 0) {
          final type = detail == null
              ? 'unknown'
              : detail.utility
                  ? 'utility'
                  : detail.type;
          _games[index] = _games[index].copyWith(
            appType: type,
            typeLoaded: type != 'unknown',
            storeHeaderUrl: detail?.headerImageUrl,
          );
        }
      }
    });
    await _cache.saveCachedGames(widget.config.normalizedSteamId64, _games);
    _typeLoading = false;
    if (mounted) setState(() {});
  }

  List<SteamGame> _recentAchievementCandidates(List<SteamGame> games,
      {int limit = 20}) {
    final candidates = games.where((game) => game.hasAchievements).toList()
      ..sort((a, b) {
        final lastPlayedCompare = b.lastPlayedUnix.compareTo(a.lastPlayedUnix);
        if (lastPlayedCompare != 0) return lastPlayedCompare;
        final recentCompare = b.playtime2Weeks.compareTo(a.playtime2Weeks);
        if (recentCompare != 0) return recentCompare;
        return b.playtimeForever.compareTo(a.playtimeForever);
      });
    return candidates.take(limit).toList();
  }

  Future<void> _cacheAchievementsForGames(List<SteamGame> games,
      {int? limit, bool updateGameProgress = false}) async {
    final candidates = limit == null
        ? games.where((game) => game.hasAchievements).toList()
        : _recentAchievementCandidates(games, limit: limit);
    var changedProgress = false;
    for (final game in candidates) {
      try {
        final achievements =
            await _api.getAchievementsForGame(widget.config, game);
        await _cache.saveCachedAchievements(
            widget.config.normalizedSteamId64, game.appId, achievements,
            languageCode: widget.config.languageCode);
        if (updateGameProgress) {
          final gameIndex = _games.indexWhere((item) => item.appId == game.appId);
          if (gameIndex >= 0) {
            final unlocked = achievements.where((item) => item.achieved).length;
            final total = achievements.length;
            final latestUnlock = achievements
                .where((item) => item.achieved)
                .fold<int>(0, (latest, item) =>
                    item.unlockTime > latest ? item.unlockTime : latest);
            final updated = _games[gameIndex].copyWith(
              unlocked: unlocked,
              total: total,
              progressLoaded: true,
              hasAchievements: total > 0,
              latestAchievementUnix: latestUnlock > 0
                  ? latestUnlock
                  : _games[gameIndex].latestAchievementUnix,
            );
            _games[gameIndex] = updated;
            changedProgress = true;
            if (mounted) setState(() {});
          }
        }
      } catch (error) {
        if (error is SteamSessionExpiredException) {
          _showSessionExpiredNotice();
          return;
        }
      }
    }
    if (changedProgress) {
      await _cache.saveCachedGames(widget.config.normalizedSteamId64, _games);
      await _loadRecentAchievementsFromCache(_games);
    }
  }

  Future<void> _loadRecentAchievementsFromCache(List<SteamGame> games) async {
    if (!widget.config.showRecentAchievementsStrip) {
      if (mounted) setState(() => _recentAchievements = []);
      return;
    }
    final items = <_RecentAchievement>[];
    final candidates = games.where((game) => game.hasAchievements).toList()
      ..sort((a, b) {
        final latest = b.latestAchievementUnix.compareTo(a.latestAchievementUnix);
        if (latest != 0) return latest;
        return b.lastPlayedUnix.compareTo(a.lastPlayedUnix);
      });
    for (final game in candidates.take(35)) {
      final achievements = await _cache.loadCachedAchievements(
        widget.config.normalizedSteamId64,
        game.appId,
        languageCode: widget.config.languageCode,
      );
      items.addAll(achievements
          .where((achievement) => achievement.achieved && achievement.unlockTime > 0)
          .map((achievement) => _RecentAchievement(game, achievement)));
    }
    items.sort((a, b) => b.achievement.unlockTime.compareTo(a.achievement.unlockTime));
    if (!mounted) return;
    setState(() => _recentAchievements = items.take(15).toList());
  }

  Future<void> _loadStartupProgress({bool forceRecent = false}) async {
    final preloadDone = await _cache.loadAchievementPreloadDone(
        widget.config.normalizedSteamId64, widget.config.languageCode);
    if (!preloadDone) {
      final completed = await _loadAllMissingProgress(
        includeZeroProgress: true,
        limit: null,
      );
      if (!completed) return;
      await _cacheAchievementsForGames(_games, updateGameProgress: true);
      await _cache.saveAchievementPreloadDone(
          widget.config.normalizedSteamId64, widget.config.languageCode);
    } else {
      await _loadAllMissingProgress(
        includeZeroProgress: forceRecent,
        limit: forceRecent ? 20 : 15,
      );
      await _cacheAchievementsForGames(_games,
          limit: forceRecent ? 20 : 15, updateGameProgress: true);
    }
  }

  Future<bool> _loadAllMissingProgress(
      {bool includeZeroProgress = false, int? limit}) async {
    if (_progressLoading) return false;
    final allCandidates = _games.where((game) {
      if (!game.progressLoaded) return true;
      return includeZeroProgress && game.hasAchievements && game.total == 0;
    });
    final candidates = limit == null
        ? allCandidates.toList()
        : allCandidates.take(limit).toList();
    if (candidates.isEmpty) return true;
    _progressLoading = true;
    for (var index = 0; index < candidates.length; index += 3) {
      final chunk =
          candidates.sublist(index, (index + 3).clamp(0, candidates.length));
      late final List<SteamGame> hydratedGames;
      try {
        hydratedGames = await Future.wait(chunk.map((game) =>
            _api.hydrateGameProgress(widget.config, game,
                allowPublicFallback:
                    game.manuallyAdded || game.sourceUrl.isNotEmpty)));
      } catch (error) {
        _progressLoading = false;
        if (error is SteamSessionExpiredException) {
          _showSessionExpiredNotice();
        }
        if (mounted) setState(() {});
        return false;
      }
      if (!mounted) return false;
      setState(() {
        for (final hydrated in hydratedGames) {
          final gameIndex =
              _games.indexWhere((item) => item.appId == hydrated.appId);
          if (gameIndex >= 0) _games[gameIndex] = hydrated;
        }
      });
      await _cache.saveCachedGames(widget.config.normalizedSteamId64, _games);
    }
    _progressLoading = false;
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _loadVisibleProgress() async {
    if (_progressLoading) return;
    final visibleCandidates = _visibleScanCandidates(
      matches: (game) => !game.progressLoaded,
    );
    final manualCandidates = _games
        .where((game) =>
            game.manuallyAdded &&
            !game.progressLoaded &&
            !visibleCandidates.any((item) => item.appId == game.appId))
        .toList();
    final candidates = [...visibleCandidates, ...manualCandidates];
    if (candidates.isEmpty) return;
    _progressLoading = true;
    for (var index = 0; index < candidates.length; index += 3) {
      final chunk =
          candidates.sublist(index, (index + 3).clamp(0, candidates.length));
      late final List<SteamGame> hydratedGames;
      try {
        hydratedGames = await Future.wait(chunk.map((game) =>
            _api.hydrateGameProgress(widget.config, game,
                allowPublicFallback:
                    game.manuallyAdded || game.sourceUrl.isNotEmpty)));
      } catch (error) {
        _progressLoading = false;
        if (error is SteamSessionExpiredException) {
          _showSessionExpiredNotice();
        }
        if (mounted) setState(() {});
        return;
      }
      if (!mounted) return;
      setState(() {
        for (final hydrated in hydratedGames) {
          final gameIndex =
              _games.indexWhere((item) => item.appId == hydrated.appId);
          if (gameIndex >= 0) _games[gameIndex] = hydrated;
        }
      });
    }
    await _cache.saveCachedGames(widget.config.normalizedSteamId64, _games);
    _progressLoading = false;
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await _loadInitial(showBlockingLoader: false, forceVisibleProgress: true);
  }

  Future<void> _showManualGameDialog() async {
    _manualGameController.clear();
    var results = <SteamStoreSearchResult>[];
    var searching = false;
    var addingAppId = 0;
    String? message;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> search() async {
            final query = _manualGameController.text.trim();
            if (query.isEmpty || searching) return;
            setSheetState(() {
              searching = true;
              message = null;
              results = const [];
            });
            try {
              final found = await _api.searchStore(query);
              if (!context.mounted) return;
              setSheetState(() {
                results = found;
                message = found.isEmpty ? t.noManualGameResults : null;
              });
            } catch (_) {
              if (!context.mounted) return;
              setSheetState(() => message = t.manualGameAddFailed);
            } finally {
              if (context.mounted) setSheetState(() => searching = false);
            }
          }

          Future<void> add(SteamStoreSearchResult result) async {
            final existingIndex =
                _games.indexWhere((game) => game.appId == result.appId);
            if (existingIndex >= 0) {
              final existing = _games[existingIndex];
              final updated = existing.copyWith(
                manuallyAdded:
                    existing.manuallyAdded || result.sourceUrl.isNotEmpty,
                sourceUrl: result.sourceUrl.isNotEmpty
                    ? result.sourceUrl
                    : existing.sourceUrl,
                progressLoaded: false,
                hasAchievements: true,
              );
              setState(() {
                _games[existingIndex] = updated;
                _hiddenGameAppIds = {..._hiddenGameAppIds}
                  ..remove(result.appId);
                _showOnlyHiddenGames = false;
                _visibleCount = (_visibleCount + 1).clamp(0, _games.length);
              });
              await _cache.saveCachedGames(
                  widget.config.normalizedSteamId64, _games);
              await _cache.saveHiddenGameAppIds(_hiddenGameAppIds);
              await _cache.clearCachedAchievements(
                  widget.config.normalizedSteamId64, result.appId);
              if (!mounted || !context.mounted) return;
              setSheetState(() {
                addingAppId = 0;
                results = const [];
                message = t.manualGameUpdated;
              });
              _manualGameController.clear();
              ScaffoldMessenger.of(this.context)
                  .showSnackBar(SnackBar(content: Text(t.manualGameUpdated)));
              _reloadGameProgress(updated);
              return;
            }
            setSheetState(() {
              addingAppId = result.appId;
              message = null;
            });
            final game = await _api.buildManualGame(widget.config, result);
            if (!mounted || !context.mounted) return;
            if (game == null) {
              setSheetState(() {
                addingAppId = 0;
                message = t.manualGameAddFailed;
              });
              return;
            }
            setState(() {
              _games = [..._games, game];
              _visibleCount = (_visibleCount + 1).clamp(0, _games.length);
            });
            await _cache.saveCachedGames(
                widget.config.normalizedSteamId64, _games);
            if (!mounted || !context.mounted) return;
            setSheetState(() {
              addingAppId = 0;
              results = const [];
              message = t.manualGameAdded;
            });
            _manualGameController.clear();
            ScaffoldMessenger.of(this.context)
                .showSnackBar(SnackBar(content: Text(t.manualGameAdded)));
            _reloadGameProgress(game);
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.addManualGameTitle,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(t.manualGameNote,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _manualGameController,
                    decoration: InputDecoration(
                      hintText: t.manualGameInputHint,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                            )
                          : IconButton(
                              onPressed: search,
                              icon: const Icon(Icons.arrow_forward)),
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => search(),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 10),
                    Text(message!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12)),
                  ],
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final result = results[index];
                        final adding = addingAppId == result.appId;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: result.imageUrl.isEmpty
                              ? const Icon(Icons.sports_esports)
                              : CachedNetworkImage(
                                  imageUrl: result.imageUrl,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover),
                          title: Text(result.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('AppID ${result.appId}'),
                          trailing: adding
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.add),
                          onTap: addingAppId == 0 ? () => add(result) : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _removeManualGame(SteamGame game) async {
    if (!game.manuallyAdded) return;
    setState(() {
      _games = _games.where((item) => item.appId != game.appId).toList();
      _hiddenGameAppIds = {..._hiddenGameAppIds}..remove(game.appId);
      _visibleCount = _visibleCount.clamp(0, _games.length);
    });
    await _cache.saveCachedGames(widget.config.normalizedSteamId64, _games);
    await _cache.saveHiddenGameAppIds(_hiddenGameAppIds);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t.manualGameRemoved)));
  }

  Future<void> _showGameActions(SteamGame game) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: Text(t.reloadGameProgress),
              onTap: () => Navigator.of(context).pop('reload'),
            ),
            ListTile(
              leading: Icon(_hiddenGameAppIds.contains(game.appId)
                  ? Icons.visibility
                  : Icons.visibility_off),
              title: Text(_hiddenGameAppIds.contains(game.appId)
                  ? t.showGame
                  : t.hideGame),
              onTap: () => Navigator.of(context).pop(
                  _hiddenGameAppIds.contains(game.appId) ? 'show' : 'hide'),
            ),
            if (game.manuallyAdded)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(t.removeManualGame),
                onTap: () => Navigator.of(context).pop('remove_manual'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'hide') await _hideGame(game);
    if (action == 'show') await _restoreGame(game.appId);
    if (action == 'reload') await _reloadGameProgress(game);
    if (action == 'remove_manual') await _removeManualGame(game);
  }

  Future<void> _reloadGameProgress(SteamGame game) async {
    setState(() {
      final index = _games.indexWhere((item) => item.appId == game.appId);
      if (index >= 0) {
        _games[index] = _games[index].copyWith(
            unlocked: 0,
            total: 0,
            progressLoaded: false);
      }
    });
    final index = _games.indexWhere((item) => item.appId == game.appId);
    if (index >= 0) {
      await _cache.clearCachedAchievements(
          widget.config.normalizedSteamId64, game.appId);
      final hydrated = await _api.hydrateGameProgress(
          widget.config, _games[index],
          allowPublicFallback: _games[index].manuallyAdded ||
              _games[index].sourceUrl.isNotEmpty);
      if (!mounted) return;
      setState(() => _games[index] = hydrated);
      await _cache.saveCachedGames(widget.config.normalizedSteamId64, _games);
    }
  }

  Future<void> _hideGame(SteamGame game) async {
    setState(() => _hiddenGameAppIds = {..._hiddenGameAppIds, game.appId});
    await _cache.saveHiddenGameAppIds(_hiddenGameAppIds);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.gameHidden),
        action: SnackBarAction(
            label: t.undo, onPressed: () => _restoreGame(game.appId)),
      ),
    );
  }

  Future<void> _restoreGame(int appId) async {
    setState(() => _hiddenGameAppIds = {..._hiddenGameAppIds}..remove(appId));
    await _cache.saveHiddenGameAppIds(_hiddenGameAppIds);
  }

  Future<void> _restoreGameList() async {
    final steamId = widget.config.normalizedSteamId64;
    await _cache.resetCachedGameProgress(steamId);
    if (!mounted) return;
    setState(() {
      _games = _games
          .map((game) => game.copyWith(
              unlocked: 0,
              total: 0,
              progressLoaded: false))
          .toList();
      _visibleCount = 40;
    });
    _loadVisibleAppTypes();
    _loadAllMissingProgress();
  }

  String? _progressTierLabel(SteamGame game) {
    if (!widget.config.showProgressTiers ||
        !game.progressLoaded ||
        !game.hasAchievements) {
      return null;
    }
    final percent = (game.progress * 100).round();
    if (percent <= 0) return '🛒 ${t.tierBoughtOnSale}';
    if (percent <= 33) return t.tierBronze;
    if (percent <= 66) return t.tierSilver;
    if (percent < 100) return t.tierGold;
    return '🏅 ${t.tierPerfect}';
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.config.isComplete) {
      return _emptyConfig();
    }
    if (_initialLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: SafeArea(child: _errorView(_error!)));
    }

    final profile = _profile ??
        SteamProfile(
            steamId64: widget.config.normalizedSteamId64,
            personaName: 'Steam',
            avatarUrl: '');
    final games = _filteredAndSorted(_games);
    final visibleGames = games.take(_visibleCount).toList();
    final summary = _summaryFromLoadedGames();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 14,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: 0.65,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.28),
                    width: 2,
                  ),
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: 7,
                    height: 3,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Steam Achievement Tracker',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                fontSize: 15,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          if (_hiddenGameAppIds.isNotEmpty)
            IconButton(
              onPressed: () =>
                  setState(() => _showOnlyHiddenGames = !_showOnlyHiddenGames),
              icon: Icon(_showOnlyHiddenGames
                  ? Icons.visibility_off
                  : Icons.visibility),
            ),
          IconButton(
            onPressed: () async {
              final action = await widget.onOpenSettings();
              if (action == 'add_manual_game' && mounted) {
                await _showManualGameDialog();
              }
            },
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      floatingActionButton: _games.isEmpty
          ? null
          : FloatingActionButton.small(
              onPressed: _scrollToTop,
              child: const Icon(Icons.keyboard_arrow_up),
            ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _profileHeader(profile, summary),
              if (widget.config.showRecentAchievementsStrip &&
                  _recentAchievements.isNotEmpty)
                _recentAchievementsStrip(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: t.searchGame),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: t.isPt ? 'Ordenar por' : 'Sort by',
                      child: PopupMenuButton<GameSortMode>(
                        initialValue: _sortMode,
                        icon: const Icon(Icons.sort),
                        onSelected: (value) {
                          setState(() => _sortMode = value);
                          _cache.saveGameSortMode(value.name);
                          _loadVisibleAppTypes();
                          _loadVisibleProgress();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                              value: GameSortMode.alphabetical,
                              child: Text('A-Z')),
                          PopupMenuItem(
                              value: GameSortMode.recent,
                              child: Text(t.isPt ? 'Recente' : 'Recent')),
                          PopupMenuItem(
                              value: GameSortMode.completion,
                              child: Text(t.isPt ? 'Conclusão' : 'Completion')),
                          PopupMenuItem(
                              value: GameSortMode.playtime,
                              child:
                                  Text(t.isPt ? 'Tempo jogado' : 'Playtime')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (visibleGames.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      children: [
                        Text(t.noGameFound, textAlign: TextAlign.center),
                        if (_games.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _restoreGameList,
                            icon: const Icon(Icons.restore),
                            label: Text(t.restoreList),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                ...visibleGames.map((game) => GameCard(
                      game: game,
                      tapToLoad: t.loadingProgress,
                      noAchievements: t.noAchievements,
                      tierLabel: _progressTierLabel(game),
                      goldPerfect: widget.config.goldPerfectGames,
                      onLongPress: () => _showGameActions(game),
                      onTap: () async {
                        final updated = await Navigator.of(context)
                            .push<SteamGame>(MaterialPageRoute(
                                builder: (_) => GameDetailScreen(
                                      config: widget.config,
                                      game: game,
                                      onRenewSteamSession:
                                          widget.onRenewSteamSession,
                                    )));
                        if (updated == null || !mounted) return;
                        setState(() {
                          final index = _games.indexWhere(
                              (item) => item.appId == updated.appId);
                          if (index >= 0) _games[index] = updated;
                        });
                        await _cache.saveCachedGames(
                            widget.config.normalizedSteamId64, _games);
                      },
                    )),
              if (_progressLoading)
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recentAchievementsStrip() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
        scrollDirection: Axis.horizontal,
        itemCount: _recentAchievements.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final item = _recentAchievements[index];
          return GestureDetector(
            onTap: () => _showRecentAchievementDetails(item),
            child: Container(
              width: 39,
              height: 39,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: _achievementIconUrl(item.achievement),
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const Icon(Icons.emoji_events,
                      color: Colors.white70, size: 20),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _achievementIconUrl(SteamAchievement achievement) {
    final icon = achievement.icon.trim();
    if (icon.isNotEmpty) return icon;
    return achievement.iconGray.trim();
  }

  String _rarityText(double percent) {
    var value = percent.toStringAsFixed(percent < 1 ? 2 : 1);
    while (value.contains('.') && value.endsWith('0')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith('.')) value = value.substring(0, value.length - 1);
    return '$value%';
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

  void _showRecentAchievementDetails(_RecentAchievement item) {
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
                                Text(item.game.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Color(0xFF7DD3FC),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900)),
                                const SizedBox(height: 3),
                                Text(item.achievement.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 17,
                                        height: 1.05,
                                        fontWeight: FontWeight.w900)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        item.achievement.description.isEmpty
                            ? (t.isPt
                                ? 'Sem descrição disponível.'
                                : 'No description available.')
                            : item.achievement.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFFE2E8F0),
                            fontSize: 12,
                            height: 1.30),
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
                                      t.isPt
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
                                      t.isPt
                                          ? '${_rarityText(percent)} dos jogadores desbloquearam'
                                          : '${_rarityText(percent)} of players unlocked this',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Color(0xFFE0F2FE),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900),
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
                            child: Text(t.isPt ? 'Fechar' : 'Close'),
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
  List<SteamGame> _filteredAndSorted(List<SteamGame> source,
      {bool includeUnloadedNoAchievementGames = false}) {
    final query = _searchController.text.toLowerCase().trim();
    final games = source.where((game) {
      final manuallyHidden = _hiddenGameAppIds.contains(game.appId);
      if (_showOnlyHiddenGames && !manuallyHidden) {
        return false;
      }
      if (!_showOnlyHiddenGames && manuallyHidden) {
        return false;
      }
      if (!_showOnlyHiddenGames &&
          !includeUnloadedNoAchievementGames &&
          widget.config.hideSoftware &&
          _isKnownNonGame(game)) {
        return false;
      }
      if (!_showOnlyHiddenGames &&
          !includeUnloadedNoAchievementGames &&
          game.progressLoaded &&
          !game.hasAchievements) {
        return false;
      }
      if (!_showOnlyHiddenGames &&
          !includeUnloadedNoAchievementGames &&
          widget.config.hideZeroPercentGames &&
          game.progressLoaded &&
          game.hasAchievements &&
          game.total > 0 &&
          game.unlocked == 0 &&
          !game.manuallyAdded &&
          game.sourceUrl.isEmpty) {
        return false;
      }
      return query.isEmpty ||
          game.name.toLowerCase().contains(query) ||
          '${game.appId}'.contains(query);
    }).toList();
    if (_sortMode == GameSortMode.recent) {
      games.sort((a, b) {
        final aRecentUnix = a.latestAchievementUnix > 0
            ? a.latestAchievementUnix
            : a.lastPlayedUnix;
        final bRecentUnix = b.latestAchievementUnix > 0
            ? b.latestAchievementUnix
            : b.lastPlayedUnix;
        final recentTimeCompare = bRecentUnix.compareTo(aRecentUnix);
        if (recentTimeCompare != 0) return recentTimeCompare;
        final recentCompare = b.playtime2Weeks.compareTo(a.playtime2Weeks);
        if (recentCompare != 0) return recentCompare;
        return b.playtimeForever.compareTo(a.playtimeForever);
      });
    } else if (_sortMode == GameSortMode.completion) {
      games.sort((a, b) {
        final loadedCompare =
            (b.progressLoaded ? 1 : 0).compareTo(a.progressLoaded ? 1 : 0);
        if (loadedCompare != 0) return loadedCompare;
        return b.progress.compareTo(a.progress);
      });
    } else if (_sortMode == GameSortMode.playtime) {
      games.sort((a, b) => b.playtimeForever.compareTo(a.playtimeForever));
    } else {
      games
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    if (_sortMode == GameSortMode.recent) {
      return games;
    }
    final manualGames = games.where((game) => game.manuallyAdded).toList();
    final regularGames = games.where((game) => !game.manuallyAdded).toList();
    return [...regularGames, ...manualGames];
  }

  bool _isKnownNonGame(SteamGame game) {
    final name = game.name.toLowerCase();
    final looksLikeUtility = name.contains('borderless gaming') ||
        name == '3dmark' ||
        name.startsWith('3dmark ') ||
        name.contains(' dedicated server') ||
        name.endsWith(' server') ||
        name.contains(' sdk') ||
        name.contains(' development kit') ||
        name.contains(' tool') ||
        name.contains(' editor') ||
        name.contains(' soundtrack') ||
        name.contains(' ost') ||
        name.contains(' artbook') ||
        name.contains(' art book') ||
        name.contains(' benchmark') ||
        name.contains(' demo');
    if (looksLikeUtility) return true;
    if (game.typeLoaded && game.appType != 'unknown') {
      return game.appType != 'game';
    }
    return false;
  }

  TrophySummary _summaryFromLoadedGames() {
    final loaded = _games
        .where((game) => game.progressLoaded && game.hasAchievements)
        .toList();
    return TrophySummary(
      unlocked: loaded.fold(0, (sum, game) => sum + game.unlocked),
      total: loaded.fold(0, (sum, game) => sum + game.total),
    );
  }

  Widget _profileHeader(SteamProfile profile, TrophySummary summary) {
    final stats = ProfileStats.fromGames(_games);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = dark ? const Color(0xFF111827) : Colors.white;
    final subtleText = dark ? Colors.white60 : const Color(0xFF64748B);
    final placeholderColor =
        dark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);
    final placeholderIconColor =
        dark ? Colors.white54 : const Color(0xFF64748B);
    final backgroundPath = widget.config.profileBackgroundPath.trim();
    final backgroundFile = backgroundPath.isEmpty ? null : File(backgroundPath);
    final hasBackground = backgroundFile != null && backgroundFile.existsSync();
    final foregroundTextColor = hasBackground ? Colors.white : null;
    final foregroundSubtleText = hasBackground ? Colors.white70 : subtleText;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProfileScreen(
                profile: profile,
                stats: stats,
                text: t,
                config: widget.config,
                games: _games,
              ))),
      child: SizedBox(
        height: 136,
        width: double.infinity,
        child: Container(
          margin: const EdgeInsets.fromLTRB(0, 4, 0, 10),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(18),
            image: hasBackground
                ? DecorationImage(
                    image: FileImage(backgroundFile, scale: 1),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  )
                : null,
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
                        Colors.black.withValues(alpha: 0.62),
                        Colors.black.withValues(alpha: 0.34),
                      ],
                    ),
                  )
                : null,
            child: Row(
              children: [
                ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: profile.avatarUrl,
                    width: 87,
                    height: 87,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 87,
                      height: 87,
                      color: placeholderColor,
                      child: Icon(Icons.person,
                          color: placeholderIconColor, size: 42),
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(profile.personaName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: foregroundTextColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                              letterSpacing: 0.8)),
                    ],
                  ),
                ),
                if (widget.config.showAverageCompletion)
                  TrophyCircle(summary: summary)
                else
                  Icon(Icons.chevron_right, color: foregroundSubtleText),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyConfig() {
    return Scaffold(
      appBar: AppBar(title: Text(t.appName)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emoji_events,
                  size: 64, color: Color(0xFF38BDF8)),
              const SizedBox(height: 14),
              Text(t.configureFirst,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(t.configureHelp,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 18),
              FilledButton(
                  onPressed: () async => widget.onOpenSettings(),
                  child: Text(t.configure)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorView(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(t.loadGamesFailed,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _refresh, child: Text(t.retry)),
          ],
        ),
      ),
    );
  }
}

class _RecentAchievement {
  final SteamGame game;
  final SteamAchievement achievement;

  const _RecentAchievement(this.game, this.achievement);
}
