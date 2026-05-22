import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/steam_models.dart';

class CacheStore {
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
  static const _goldPerfectGamesKey = 'gold_perfect_games';

  Future<SteamConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return SteamConfig(
      steamId64: prefs.getString(_steamIdKey) ?? '',
      apiKey: prefs.getString(_apiKeyKey) ?? '',
      showHidden: prefs.getBool(_showHiddenKey) ?? false,
      languageCode: prefs.getString(_languageKey) ?? 'pt',
      showAverageCompletion: prefs.getBool(_showAverageKey) ?? false,
      hideGamesWithoutAchievements: prefs.getBool(_hideNoAchievementsKey) ?? false,
      hideSoftware: prefs.getBool(_hideSoftwareKey) ?? false,
      hideZeroPercentGames: prefs.getBool(_hideZeroPercentKey) ?? false,
      separateDlcAchievements: prefs.getBool(_separateDlcAchievementsKey) ?? false,
      themeMode: prefs.getString(_themeModeKey) ?? 'system',
      showProgressTiers: prefs.getBool(_showProgressTiersKey) ?? true,
      showRarityTiers: prefs.getBool(_showRarityTiersKey) ?? true,
      goldPerfectGames: prefs.getBool(_goldPerfectGamesKey) ?? true,
    );
  }

  Future<void> saveConfig(SteamConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_steamIdKey, config.steamId64.trim());
    await prefs.setString(_apiKeyKey, config.apiKey.trim());
    await prefs.setBool(_showHiddenKey, config.showHidden);
    await prefs.setString(_languageKey, config.languageCode);
    await prefs.setBool(_showAverageKey, config.showAverageCompletion);
    await prefs.setBool(_hideNoAchievementsKey, config.hideGamesWithoutAchievements);
    await prefs.setBool(_hideSoftwareKey, config.hideSoftware);
    await prefs.setBool(_hideZeroPercentKey, config.hideZeroPercentGames);
    await prefs.setBool(_separateDlcAchievementsKey, config.separateDlcAchievements);
    await prefs.setString(_themeModeKey, config.themeMode);
    await prefs.setBool(_showProgressTiersKey, config.showProgressTiers);
    await prefs.setBool(_showRarityTiersKey, config.showRarityTiers);
    await prefs.setBool(_goldPerfectGamesKey, config.goldPerfectGames);
  }

  Future<Set<int>> loadHiddenGameAppIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_hiddenGameAppIdsKey) ?? const [])
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
  }

  Future<void> saveHiddenGameAppIds(Set<int> appIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenGameAppIdsKey, appIds.map((appId) => '$appId').toList()..sort());
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cache_$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> setJson(String key, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
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
    return items.whereType<Map<String, dynamic>>().map(SteamGame.fromCacheJson).toList();
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
      games.map((game) => game.copyWith(unlocked: 0, total: 0, progressLoaded: false, hasAchievements: true)).toList(),
    );
  }

  Future<List<SteamAchievement>> loadCachedAchievements(String steamId64, int appId) async {
    final json = await getJson('achievements_${steamId64}_$appId');
    final items = json?['achievements'];
    if (items is! List) return [];
    return items.whereType<Map<String, dynamic>>().map(SteamAchievement.fromJson).where((achievement) => achievement.apiName.isNotEmpty).toList();
  }

  Future<void> saveCachedAchievements(String steamId64, int appId, List<SteamAchievement> achievements) async {
    if (achievements.isEmpty) return;
    await setJson('achievements_${steamId64}_$appId', {
      'saved_at': DateTime.now().toIso8601String(),
      'achievements': achievements.map((achievement) => achievement.toJson()).toList(),
    });
  }

  Future<void> clearProfileCache(String steamId64) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cache_profile_$steamId64');
    await prefs.remove('cache_games_$steamId64');
    for (final key in prefs.getKeys().where((key) => key.startsWith('cache_achievements_${steamId64}_')).toList()) {
      await prefs.remove(key);
    }
  }
}
