import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/steam_models.dart';

class CacheStore {
  Future<SharedPreferences>? _prefs;

  Future<SharedPreferences> get _sharedPreferences =>
      _prefs ??= SharedPreferences.getInstance();
  static const _loginModeKey = 'login_mode';
  static const _steamIdKey = 'steam_id_64';
  static const _apiKeyKey = 'steam_api_key';
  static const _showHiddenKey = 'show_hidden_achievements';
  static const _languageKey = 'language_code';
  static const _showAverageKey = 'show_average_completion';
  static const _hideNoAchievementsKey = 'hide_games_without_achievements';
  static const _hideSoftwareKey = 'hide_software_apps';
  static const _hideZeroPercentKey = 'hide_zero_percent_games';
  static const _hiddenGameAppIdsKey = 'hidden_game_appids';
  static const _separateDlcAchievementsKey = 'separate_dlc_achievements';
  static const _themeModeKey = 'theme_mode';
  static const _showProgressTiersKey = 'show_progress_tiers';
  static const _showRarityTiersKey = 'show_rarity_tiers';
  static const _showObtainabilityBadgesKey = 'show_obtainability_badges';
  static const _showRecentAchievementsStripKey =
      'show_recent_achievements_strip';
  static const _goldPerfectGamesKey = 'gold_perfect_games';
  static const _profileBackgroundPathKey = 'profile_background_path';
  static const _profileBackgroundFitKey = 'profile_background_fit';
  static const _profileBackgroundAlignmentKey = 'profile_background_alignment';
  static const _lastUpdateCheckMillisKey = 'last_update_check_millis';
  static const _achievementHelpShownKey = 'achievement_help_shown';
  static const _gameSortModeKey = 'game_sort_mode';
  static const _achievementSortModeKey = 'achievement_sort_mode';
  static const _achievementFilterKey = 'achievement_filter';
  static const _achievementShowHiddenLocalKey = 'achievement_show_hidden_local';

  Future<SteamConfig> loadConfig() async {
    final prefs = await _sharedPreferences;
    return SteamConfig(
      loginMode: prefs.getString(_loginModeKey) ?? 'manual',
      steamId64: prefs.getString(_steamIdKey) ?? '',
      apiKey: prefs.getString(_apiKeyKey) ?? '',
      showHidden: prefs.getBool(_showHiddenKey) ?? false,
      languageCode: prefs.getString(_languageKey) ?? 'pt',
      showAverageCompletion: prefs.getBool(_showAverageKey) ?? false,
      hideGamesWithoutAchievements:
          prefs.getBool(_hideNoAchievementsKey) ?? false,
      hideSoftware: prefs.getBool(_hideSoftwareKey) ?? false,
      hideZeroPercentGames: prefs.getBool(_hideZeroPercentKey) ?? false,
      separateDlcAchievements:
          prefs.getBool(_separateDlcAchievementsKey) ?? false,
      themeMode: prefs.getString(_themeModeKey) ?? 'system',
      showProgressTiers: prefs.getBool(_showProgressTiersKey) ?? true,
      showRarityTiers: prefs.getBool(_showRarityTiersKey) ?? true,
      showObtainabilityBadges:
          prefs.getBool(_showObtainabilityBadgesKey) ?? true,
      showRecentAchievementsStrip:
          prefs.getBool(_showRecentAchievementsStripKey) ?? true,
      goldPerfectGames: prefs.getBool(_goldPerfectGamesKey) ?? true,
      profileBackgroundPath: prefs.getString(_profileBackgroundPathKey) ?? '',
      profileBackgroundFit:
          prefs.getString(_profileBackgroundFitKey) ?? 'cover',
      profileBackgroundAlignment:
          prefs.getString(_profileBackgroundAlignmentKey) ?? 'center',
    );
  }

  Future<void> saveConfig(SteamConfig config) async {
    final prefs = await _sharedPreferences;
    await prefs.setString(_loginModeKey, config.loginMode);
    await prefs.setString(_steamIdKey, config.steamId64.trim());
    await prefs.setString(_apiKeyKey, config.apiKey.trim());
    await prefs.setBool(_showHiddenKey, config.showHidden);
    await prefs.setString(_languageKey, config.languageCode);
    await prefs.setBool(_showAverageKey, config.showAverageCompletion);
    await prefs.setBool(
        _hideNoAchievementsKey, config.hideGamesWithoutAchievements);
    await prefs.setBool(_hideSoftwareKey, config.hideSoftware);
    await prefs.setBool(_hideZeroPercentKey, config.hideZeroPercentGames);
    await prefs.setBool(
        _separateDlcAchievementsKey, config.separateDlcAchievements);
    await prefs.setString(_themeModeKey, config.themeMode);
    await prefs.setBool(_showProgressTiersKey, config.showProgressTiers);
    await prefs.setBool(_showRarityTiersKey, config.showRarityTiers);
    await prefs.setBool(
        _showObtainabilityBadgesKey, config.showObtainabilityBadges);
    await prefs.setBool(
        _showRecentAchievementsStripKey, config.showRecentAchievementsStrip);
    await prefs.setBool(_goldPerfectGamesKey, config.goldPerfectGames);
    await prefs.setString(
        _profileBackgroundPathKey, config.profileBackgroundPath.trim());
    await prefs.setString(
        _profileBackgroundFitKey, config.profileBackgroundFit.trim());
    await prefs.setString(_profileBackgroundAlignmentKey,
        config.profileBackgroundAlignment.trim());
  }

  Future<int> loadLastUpdateCheckMillis() async {
    final prefs = await _sharedPreferences;
    return prefs.getInt(_lastUpdateCheckMillisKey) ?? 0;
  }

  Future<void> saveLastUpdateCheckMillis(int millis) async {
    final prefs = await _sharedPreferences;
    await prefs.setInt(_lastUpdateCheckMillisKey, millis);
  }

  Future<String> loadGameSortMode() async {
    final prefs = await _sharedPreferences;
    return prefs.getString(_gameSortModeKey) ?? 'alphabetical';
  }

  Future<void> saveGameSortMode(String value) async {
    final prefs = await _sharedPreferences;
    await prefs.setString(_gameSortModeKey, value);
  }

  String _achievementViewKey(String baseKey, String steamId64, int appId) =>
      '${baseKey}_${steamId64}_$appId';

  Future<String> loadAchievementSortMode() async {
    final prefs = await _sharedPreferences;
    return prefs.getString(_achievementSortModeKey) ?? 'original';
  }

  Future<void> saveAchievementSortMode(String value) async {
    final prefs = await _sharedPreferences;
    await prefs.setString(_achievementSortModeKey, value);
  }

  Future<String> loadAchievementSortModeForGame(
      String steamId64, int appId) async {
    final prefs = await _sharedPreferences;
    return prefs.getString(
            _achievementViewKey(_achievementSortModeKey, steamId64, appId)) ??
        prefs.getString(_achievementSortModeKey) ??
        'original';
  }

  Future<void> saveAchievementSortModeForGame(
      String steamId64, int appId, String value) async {
    final prefs = await _sharedPreferences;
    await prefs.setString(
        _achievementViewKey(_achievementSortModeKey, steamId64, appId), value);
  }

  Future<String> loadAchievementFilter() async {
    final prefs = await _sharedPreferences;
    return prefs.getString(_achievementFilterKey) ?? 'all';
  }

  Future<void> saveAchievementFilter(String value) async {
    final prefs = await _sharedPreferences;
    await prefs.setString(_achievementFilterKey, value);
  }

  Future<String> loadAchievementFilterForGame(
      String steamId64, int appId) async {
    final prefs = await _sharedPreferences;
    return prefs.getString(
            _achievementViewKey(_achievementFilterKey, steamId64, appId)) ??
        prefs.getString(_achievementFilterKey) ??
        'all';
  }

  Future<void> saveAchievementFilterForGame(
      String steamId64, int appId, String value) async {
    final prefs = await _sharedPreferences;
    await prefs.setString(
        _achievementViewKey(_achievementFilterKey, steamId64, appId), value);
  }

  Future<bool?> loadAchievementShowHiddenLocal() async {
    final prefs = await _sharedPreferences;
    return prefs.getBool(_achievementShowHiddenLocalKey);
  }

  Future<void> saveAchievementShowHiddenLocal(bool value) async {
    final prefs = await _sharedPreferences;
    await prefs.setBool(_achievementShowHiddenLocalKey, value);
  }

  Future<bool?> loadAchievementShowHiddenLocalForGame(
      String steamId64, int appId) async {
    final prefs = await _sharedPreferences;
    return prefs.getBool(_achievementViewKey(
            _achievementShowHiddenLocalKey, steamId64, appId)) ??
        prefs.getBool(_achievementShowHiddenLocalKey);
  }

  Future<void> saveAchievementShowHiddenLocalForGame(
      String steamId64, int appId, bool value) async {
    final prefs = await _sharedPreferences;
    await prefs.setBool(
        _achievementViewKey(_achievementShowHiddenLocalKey, steamId64, appId),
        value);
  }

  Future<bool> loadAchievementHelpShown() async {
    final prefs = await _sharedPreferences;
    return prefs.getBool(_achievementHelpShownKey) ?? false;
  }

  Future<void> saveAchievementHelpShown() async {
    final prefs = await _sharedPreferences;
    await prefs.setBool(_achievementHelpShownKey, true);
  }

  Future<Set<int>> loadHiddenGameAppIds() async {
    final prefs = await _sharedPreferences;
    return (prefs.getStringList(_hiddenGameAppIdsKey) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  Future<void> saveHiddenGameAppIds(Set<int> appIds) async {
    final prefs = await _sharedPreferences;
    await prefs.setStringList(
        _hiddenGameAppIdsKey, appIds.map((appId) => '$appId').toList()..sort());
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    final prefs = await _sharedPreferences;
    final raw = prefs.getString('cache_$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> setJson(String key, Map<String, dynamic> value) async {
    final prefs = await _sharedPreferences;
    await prefs.setString('cache_$key', jsonEncode(value));
  }

  Future<SteamProfile?> loadCachedProfile(String steamId64) async {
    final json = await getJson('profile_$steamId64');
    if (json == null) return null;
    return SteamProfile.fromJson(json);
  }

  Future<void> saveCachedProfile(String steamId64, SteamProfile profile) async {
    await setJson('profile_$steamId64', profile.toJson());
  }

  Future<List<SteamGame>> loadCachedGames(String steamId64) async {
    final json = await getJson('games_$steamId64');
    final items = json?['games'];
    if (items is! List) return [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(SteamGame.fromCacheJson)
        .toList();
  }

  Future<void> saveCachedGames(String steamId64, List<SteamGame> games) async {
    await setJson('games_$steamId64', {
      'saved_at': DateTime.now().toIso8601String(),
      'games': games.map((game) => game.toJson()).toList(),
    });
  }

  Future<void> resetCachedGameProgress(String steamId64) async {
    final games = await loadCachedGames(steamId64);
    if (games.isEmpty) return;
    await saveCachedGames(
      steamId64,
      games
          .map((game) =>
              game.copyWith(unlocked: 0, total: 0, progressLoaded: false))
          .toList(),
    );
  }

  String _achievementPreloadDoneKey(String steamId64, String languageCode) =>
      'achievement_preload_done_${steamId64}_$languageCode';

  Future<bool> loadAchievementPreloadDone(
      String steamId64, String languageCode) async {
    final prefs = await _sharedPreferences;
    return prefs.getBool(_achievementPreloadDoneKey(steamId64, languageCode)) ??
        false;
  }

  Future<void> saveAchievementPreloadDone(
      String steamId64, String languageCode) async {
    final prefs = await _sharedPreferences;
    await prefs.setBool(
        _achievementPreloadDoneKey(steamId64, languageCode), true);
  }

  String _achievementCacheKey(
          String steamId64, int appId, String languageCode) =>
      'achievements_v12_${steamId64}_${appId}_$languageCode';

  Future<List<SteamAchievement>> loadCachedAchievements(
      String steamId64, int appId,
      {String languageCode = 'en'}) async {
    final json =
        await getJson(_achievementCacheKey(steamId64, appId, languageCode));
    final items = json?['achievements'];
    if (items is! List) return [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(SteamAchievement.fromJson)
        .where((achievement) => achievement.apiName.isNotEmpty)
        .toList();
  }

  Future<void> saveCachedAchievements(
      String steamId64, int appId, List<SteamAchievement> achievements,
      {String languageCode = 'en'}) async {
    if (achievements.isEmpty) return;
    await setJson(_achievementCacheKey(steamId64, appId, languageCode), {
      'saved_at': DateTime.now().toIso8601String(),
      'achievements':
          achievements.map((achievement) => achievement.toJson()).toList(),
    });
  }

  Future<void> resetCachedGameAchievementProgress(String steamId64) async {
    final games = await loadCachedGames(steamId64);
    if (games.isEmpty) return;
    await saveCachedGames(
      steamId64,
      games
          .map((game) => game.copyWith(
                unlocked: 0,
                total: 0,
                progressLoaded: false,
                latestAchievementUnix: 0,
              ))
          .toList(),
    );
  }

  Future<void> clearAllCachedAchievements(String steamId64) async {
    final prefs = await _sharedPreferences;
    for (final key in prefs
        .getKeys()
        .where((key) =>
            key.startsWith('cache_achievements_${steamId64}_') ||
            key.startsWith('cache_achievements_v2_${steamId64}_') ||
            key.startsWith('cache_achievements_v3_${steamId64}_') ||
            key.startsWith('cache_achievements_v4_${steamId64}_') ||
            key.startsWith('cache_achievements_v5_${steamId64}_') ||
            key.startsWith('cache_achievements_v6_${steamId64}_') ||
            key.startsWith('cache_achievements_v7_${steamId64}_') ||
            key.startsWith('cache_achievements_v8_${steamId64}_') ||
            key.startsWith('cache_achievements_v9_${steamId64}_') ||
            key.startsWith('cache_achievements_v10_${steamId64}_') ||
            key.startsWith('cache_achievements_v11_${steamId64}_') ||
            key.startsWith('cache_achievements_v12_${steamId64}_'))
        .toList()) {
      await prefs.remove(key);
    }
  }

  Future<void> clearCachedAchievements(String steamId64, int appId) async {
    final prefs = await _sharedPreferences;
    await prefs.remove('cache_achievements_${steamId64}_$appId');
    await prefs.remove('cache_${_achievementCacheKey(steamId64, appId, 'en')}');
    await prefs.remove('cache_${_achievementCacheKey(steamId64, appId, 'pt')}');
    await prefs.remove('cache_achievements_${steamId64}_${appId}_en');
    await prefs.remove('cache_achievements_${steamId64}_${appId}_pt');
    await prefs.remove('cache_achievements_v2_${steamId64}_${appId}_en');
    await prefs.remove('cache_achievements_v2_${steamId64}_${appId}_pt');
    await prefs.remove('cache_achievements_v3_${steamId64}_${appId}_en');
    await prefs.remove('cache_achievements_v3_${steamId64}_${appId}_pt');
    await prefs.remove('cache_achievements_v4_${steamId64}_${appId}_en');
    await prefs.remove('cache_achievements_v4_${steamId64}_${appId}_pt');
    await prefs.remove('cache_achievements_v5_${steamId64}_${appId}_en');
    await prefs.remove('cache_achievements_v5_${steamId64}_${appId}_pt');
    await prefs.remove('cache_achievements_v6_${steamId64}_${appId}_en');
    await prefs.remove('cache_achievements_v6_${steamId64}_${appId}_pt');
    await prefs.remove('cache_achievements_v7_${steamId64}_${appId}_en');
    await prefs.remove('cache_achievements_v7_${steamId64}_${appId}_pt');
    await prefs.remove('cache_achievements_v8_${steamId64}_${appId}_en');
    await prefs.remove('cache_achievements_v8_${steamId64}_${appId}_pt');
    await prefs.remove('cache_achievements_v9_${steamId64}_${appId}_en');
    await prefs.remove('cache_achievements_v9_${steamId64}_${appId}_pt');
    await prefs.remove('cache_achievements_v10_${steamId64}_${appId}_en');
    await prefs.remove('cache_achievements_v10_${steamId64}_${appId}_pt');
    await prefs.remove('cache_achievements_v11_${steamId64}_${appId}_en');
    await prefs.remove('cache_achievements_v11_${steamId64}_${appId}_pt');
    await prefs.remove('cache_achievements_v12_${steamId64}_${appId}_en');
    await prefs.remove('cache_achievements_v12_${steamId64}_${appId}_pt');
  }

  Future<Set<String>> loadPinnedAchievementIds(
      String steamId64, int appId) async {
    final prefs = await _sharedPreferences;
    return (prefs.getStringList('pinned_achievements_${steamId64}_$appId') ??
            const [])
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  Future<void> savePinnedAchievementIds(
      String steamId64, int appId, Set<String> ids) async {
    final prefs = await _sharedPreferences;
    await prefs.setStringList(
        'pinned_achievements_${steamId64}_$appId', ids.toList()..sort());
  }

  Future<void> clearProfileCache(String steamId64,
      {bool keepManualGames = false}) async {
    final prefs = await _sharedPreferences;
    final manualGames = keepManualGames
        ? (await loadCachedGames(steamId64))
            .where((game) => game.manuallyAdded || game.sourceUrl.isNotEmpty)
            .map((game) => game.copyWith(
                unlocked: 0,
                total: 0,
                progressLoaded: false,
                hasAchievements: true,
                typeLoaded: false,
                appType: 'unknown',
                manuallyAdded: true))
            .toList()
        : <SteamGame>[];
    await prefs.remove('cache_profile_$steamId64');
    await prefs.remove('cache_games_$steamId64');
    await prefs.remove('sync_full_completed_$steamId64');
    for (final key in prefs
        .getKeys()
        .where(
            (key) => key.startsWith('achievement_preload_done_${steamId64}_'))
        .toList()) {
      await prefs.remove(key);
    }
    for (final key in prefs
        .getKeys()
        .where((key) =>
            key.startsWith('cache_achievements_${steamId64}_') ||
            key.startsWith('cache_achievements_v2_${steamId64}_') ||
            key.startsWith('cache_achievements_v3_${steamId64}_') ||
            key.startsWith('cache_achievements_v4_${steamId64}_') ||
            key.startsWith('cache_achievements_v5_${steamId64}_') ||
            key.startsWith('cache_achievements_v6_${steamId64}_') ||
            key.startsWith('cache_achievements_v7_${steamId64}_') ||
            key.startsWith('cache_achievements_v8_${steamId64}_') ||
            key.startsWith('cache_achievements_v9_${steamId64}_') ||
            key.startsWith('cache_achievements_v10_${steamId64}_') ||
            key.startsWith('cache_achievements_v11_${steamId64}_') ||
            key.startsWith('cache_achievements_v12_${steamId64}_'))
        .toList()) {
      await prefs.remove(key);
    }
    if (manualGames.isNotEmpty) {
      await saveCachedGames(steamId64, manualGames);
    }
  }
}
