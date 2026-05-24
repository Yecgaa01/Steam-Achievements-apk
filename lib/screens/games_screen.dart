import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_text.dart';
import '../models/steam_models.dart';
import '../services/cache_store.dart';
import '../services/steam_api.dart';
import '../widgets/game_card.dart';
import '../widgets/trophy_circle.dart';
import 'game_detail_screen.dart';
import 'profile_screen.dart';

enum GameSortMode { alphabetical, recent, completion, playtime }

class GamesScreen extends StatefulWidget {
  final SteamConfig config;
  final Future<String?> Function() onOpenSettings;

  const GamesScreen(
      {super.key, required this.config, required this.onOpenSettings});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  static const _batchSize = 25;

  final _api = SteamApi();
  final _cache = CacheStore();
  final _searchController = TextEditingController();
  final _manualGameController = TextEditingController();
  final _scrollController = ScrollController();

  SteamProfile? _profile;
  List<SteamGame> _games = [];
  bool _initialLoading = true;
  bool _progressLoading = false;
  bool _typeLoading = false;
  String? _error;
  int _visibleCount = 40;
  int _progressScanCursor = 0;
  int _typeScanCursor = 0;
  GameSortMode _sortMode = GameSortMode.alphabetical;
  Set<int> _hiddenGameAppIds = {};
  bool _showOnlyHiddenGames = false;

  AppText get t => AppText(widget.config.languageCode == 'en'
      ? AppLanguage.english
      : AppLanguage.portuguese);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _scrollController.addListener(_onScroll);
    _loadInitial();
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
        _typeScanCursor = 0;
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
      _progressScanCursor = 0;
      _typeScanCursor = 0;
      _showOnlyHiddenGames = false;
    });
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _manualGameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial({bool showBlockingLoader = true}) async {
    if (!widget.config.isComplete) {
      setState(() => _initialLoading = false);
      return;
    }
    if (showBlockingLoader) {
      setState(() {
        _initialLoading = true;
        _error = null;
        _visibleCount = 40;
      });
    } else {
      setState(() {
        _error = null;
        _visibleCount = 40;
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
          if (cachedGames.isNotEmpty) _games = cachedGames;
          _initialLoading = false;
        });
      }

      final profile = await _api.getProfile(widget.config);
      final freshGames = await _api.getOwnedGames(widget.config);
      final cachedByApp = {for (final game in _games) game.appId: game};
      final freshAppIds = freshGames.map((game) => game.appId).toSet();
      final manualGames = cachedGames
          .where(
              (game) => game.manuallyAdded && !freshAppIds.contains(game.appId))
          .toList();
      final merged = [
        ...freshGames.map((game) {
          final cached = cachedByApp[game.appId];
          if (cached == null) return game;
          final cachedAppType = cached.appType;
          final cachedTypeLoaded = cached.typeLoaded;
          return game.copyWith(
            unlocked: cached.unlocked,
            total: cached.total,
            progressLoaded: cached.progressLoaded,
            hasAchievements: cached.hasAchievements,
            appType: cachedAppType,
            typeLoaded: cachedTypeLoaded,
            manuallyAdded: cached.manuallyAdded,
            sourceUrl: cached.sourceUrl,
          );
        }),
        ...manualGames,
      ];
      await _cache.saveCachedProfile(steamId, profile);
      await _cache.saveCachedGames(steamId, merged);
      setState(() {
        _profile = profile;
        _games = merged;
        _progressScanCursor = 0;
        _typeScanCursor = 0;
        _initialLoading = false;
      });
      await _loadVisibleProgress();
      await _loadVisibleAppTypes();
    } catch (error) {
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

  List<SteamGame> _scanCandidates({
    required int start,
    required bool Function(SteamGame game) matches,
  }) {
    if (_games.isEmpty) return const [];
    final candidates = <SteamGame>[];
    final safeStart = start.clamp(0, _games.length - 1);
    for (var offset = 0;
        offset < _games.length && candidates.length < _batchSize;
        offset++) {
      final game = _games[(safeStart + offset) % _games.length];
      if (matches(game)) candidates.add(game);
    }
    return candidates;
  }

  int _nextScanCursor(List<SteamGame> candidates, int currentCursor) {
    if (_games.isEmpty || candidates.isEmpty) return 0;
    final lastIndex =
        _games.indexWhere((game) => game.appId == candidates.last.appId);
    if (lastIndex < 0) return currentCursor % _games.length;
    return (lastIndex + 1) % _games.length;
  }

  Future<void> _loadVisibleAppTypes() async {
    if (_typeLoading) return;
    final candidates = _scanCandidates(
      start: _typeScanCursor,
      matches: (game) => !game.typeLoaded || game.appType == 'unknown',
    );
    if (candidates.isEmpty) return;
    _typeScanCursor = _nextScanCursor(candidates, _typeScanCursor);
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
          _games[index] = _games[index]
              .copyWith(appType: type, typeLoaded: type != 'unknown');
        }
      }
    });
    await _cache.saveCachedGames(widget.config.normalizedSteamId64, _games);
    _typeLoading = false;
    if (mounted) {
      setState(() {});
      if (_games.any((game) => !game.typeLoaded || game.appType == 'unknown')) {
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _loadVisibleAppTypes();
        });
      }
    }
  }

  Future<void> _loadVisibleProgress() async {
    if (_progressLoading) return;
    final candidates = _scanCandidates(
      start: _progressScanCursor,
      matches: (game) => !game.progressLoaded,
    );
    if (candidates.isEmpty) return;
    _progressScanCursor = _nextScanCursor(candidates, _progressScanCursor);
    _progressLoading = true;
    for (var index = 0; index < candidates.length; index += 3) {
      final chunk =
          candidates.sublist(index, (index + 3).clamp(0, candidates.length));
      final hydratedGames = await Future.wait(chunk.map((game) =>
          _api.hydrateGameProgress(widget.config, game,
              allowPublicFallback:
                  game.manuallyAdded || game.sourceUrl.isNotEmpty)));
      if (!mounted) return;
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
    if (mounted) {
      setState(() {});
      if (_games.any((game) => !game.progressLoaded)) {
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          if (mounted) _loadVisibleProgress();
        });
      }
    }
  }

  Future<void> _refresh() async {
    await _loadInitial(showBlockingLoader: false);
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
              if (result.sourceUrl.isEmpty) {
                setSheetState(() => message = t.manualGameAlreadyInList);
                return;
              }
              final updated = existing.copyWith(
                manuallyAdded: true,
                sourceUrl: result.sourceUrl,
                progressLoaded: false,
                hasAchievements: true,
              );
              setState(() => _games[existingIndex] = updated);
              await _cache.saveCachedGames(
                  widget.config.normalizedSteamId64, _games);
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
            _loadVisibleProgress();
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
            progressLoaded: false,
            hasAchievements: true);
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
              progressLoaded: false,
              hasAchievements: true))
          .toList();
      _visibleCount = 40;
      _progressScanCursor = 0;
      _typeScanCursor = 0;
    });
    _loadVisibleAppTypes();
    _loadVisibleProgress();
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
    final filteredTotal = games.length;
    final visibleGames = games.take(_visibleCount).toList();
    final summary = _summaryFromLoadedGames();

    return Scaffold(
      appBar: AppBar(
        title: Text(t.appName,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
                color: Theme.of(context).colorScheme.primary)),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: t.searchGame),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: DropdownButtonFormField<GameSortMode>(
                  value: _sortMode,
                  decoration: InputDecoration(
                    labelText: t.isPt ? 'Ordenar por' : 'Sort by',
                    prefixIcon: const Icon(Icons.sort),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: GameSortMode.alphabetical, child: Text('A-Z')),
                    DropdownMenuItem(
                        value: GameSortMode.recent,
                        child: Text(t.isPt ? 'Recente' : 'Recent')),
                    DropdownMenuItem(
                        value: GameSortMode.completion,
                        child: Text(t.isPt ? 'Conclusão' : 'Completion')),
                    DropdownMenuItem(
                        value: GameSortMode.playtime,
                        child: Text(t.isPt ? 'Tempo jogado' : 'Playtime')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sortMode = value);
                    _loadVisibleAppTypes();
                    _loadVisibleProgress();
                  },
                ),
              ),
              _listStatus(filteredTotal, visibleGames.length),
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
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => GameDetailScreen(
                                config: widget.config, game: game)));
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
          game.unlocked == 0) {
        return false;
      }
      return query.isEmpty ||
          game.name.toLowerCase().contains(query) ||
          '${game.appId}'.contains(query);
    }).toList();
    if (_sortMode == GameSortMode.recent) {
      games.sort((a, b) {
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
    final manualGames = games.where((game) => game.manuallyAdded).toList();
    final regularGames = games.where((game) => !game.manuallyAdded).toList();
    return [...regularGames, ...manualGames];
  }

  Widget _listStatus(int filteredTotal, int visibleShown) {
    final scanned = _games
        .where((game) => game.progressLoaded && game.hasAchievements)
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        t.listStatus(visibleShown, filteredTotal, scanned),
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12),
      ),
    );
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
    final borderColor =
        dark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);
    final subtleText = dark ? Colors.white60 : const Color(0xFF64748B);
    final placeholderColor =
        dark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);
    final placeholderIconColor =
        dark ? Colors.white54 : const Color(0xFF64748B);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) =>
              ProfileScreen(profile: profile, stats: stats, text: t))),
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl: profile.avatarUrl,
                width: 58,
                height: 58,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: 58,
                  height: 58,
                  color: placeholderColor,
                  child: Icon(Icons.person, color: placeholderIconColor),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.personaName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    '${(stats.totalPlaytimeHours).toStringAsFixed(0)} h • ${stats.totalGames} jogos • ${stats.loadedGames} ${t.scannedGames.toLowerCase()}',
                    style: TextStyle(color: subtleText, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (widget.config.showAverageCompletion)
              TrophyCircle(summary: summary)
            else
              Icon(Icons.chevron_right, color: subtleText),
          ],
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
