class SteamConfig {
  final String loginMode;
  final String steamId64;
  final String apiKey;
  final bool showHidden;
  final String languageCode;
  final bool showAverageCompletion;
  final bool hideGamesWithoutAchievements;
  final bool hideSoftware;
  final bool hideZeroPercentGames;
  final bool separateDlcAchievements;
  final String themeMode;
  final bool showProgressTiers;
  final bool showRarityTiers;
  final bool showObtainabilityBadges;
  final bool showRecentAchievementsStrip;
  final bool goldPerfectGames;
  final String profileBackgroundPath;
  final String profileBackgroundFit;
  final String profileBackgroundAlignment;

  const SteamConfig({
    this.loginMode = 'manual',
    required this.steamId64,
    required this.apiKey,
    this.showHidden = false,
    this.languageCode = 'pt',
    this.showAverageCompletion = false,
    this.hideGamesWithoutAchievements = false,
    this.hideSoftware = false,
    this.hideZeroPercentGames = false,
    this.separateDlcAchievements = false,
    this.themeMode = 'system',
    this.showProgressTiers = true,
    this.showRarityTiers = true,
    this.showObtainabilityBadges = true,
    this.showRecentAchievementsStrip = true,
    this.goldPerfectGames = true,
    this.profileBackgroundPath = '',
    this.profileBackgroundFit = 'cover',
    this.profileBackgroundAlignment = 'center',
  });

  bool get isComplete {
    final hasSteamId = steamId64.trim().isNotEmpty;
    if (loginMode == 'steamSession') return hasSteamId;
    return hasSteamId && apiKey.trim().isNotEmpty;
  }

  String get normalizedSteamId64 => steamId64.trim();
  String get normalizedApiKey => apiKey.trim();

  SteamConfig copyWith({
    String? loginMode,
    String? steamId64,
    String? apiKey,
    bool? showHidden,
    String? languageCode,
    bool? showAverageCompletion,
    bool? hideGamesWithoutAchievements,
    bool? hideSoftware,
    bool? hideZeroPercentGames,
    bool? separateDlcAchievements,
    String? themeMode,
    bool? showProgressTiers,
    bool? showRarityTiers,
    bool? showObtainabilityBadges,
    bool? showRecentAchievementsStrip,
    bool? goldPerfectGames,
    String? profileBackgroundPath,
    String? profileBackgroundFit,
    String? profileBackgroundAlignment,
  }) {
    return SteamConfig(
      loginMode: loginMode ?? this.loginMode,
      steamId64: steamId64 ?? this.steamId64,
      apiKey: apiKey ?? this.apiKey,
      showHidden: showHidden ?? this.showHidden,
      languageCode: languageCode ?? this.languageCode,
      showAverageCompletion:
          showAverageCompletion ?? this.showAverageCompletion,
      hideGamesWithoutAchievements:
          hideGamesWithoutAchievements ?? this.hideGamesWithoutAchievements,
      hideSoftware: hideSoftware ?? this.hideSoftware,
      hideZeroPercentGames: hideZeroPercentGames ?? this.hideZeroPercentGames,
      separateDlcAchievements:
          separateDlcAchievements ?? this.separateDlcAchievements,
      themeMode: themeMode ?? this.themeMode,
      showProgressTiers: showProgressTiers ?? this.showProgressTiers,
      showRarityTiers: showRarityTiers ?? this.showRarityTiers,
      showObtainabilityBadges:
          showObtainabilityBadges ?? this.showObtainabilityBadges,
      showRecentAchievementsStrip:
          showRecentAchievementsStrip ?? this.showRecentAchievementsStrip,
      goldPerfectGames: goldPerfectGames ?? this.goldPerfectGames,
      profileBackgroundPath:
          profileBackgroundPath ?? this.profileBackgroundPath,
      profileBackgroundFit: profileBackgroundFit ?? this.profileBackgroundFit,
      profileBackgroundAlignment:
          profileBackgroundAlignment ?? this.profileBackgroundAlignment,
    );
  }
}

int intFromAny(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? fallback;
  return fallback;
}

double? doubleFromAny(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

bool boolFromAny(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }
  return false;
}

class SteamProfile {
  final String steamId64;
  final String personaName;
  final String avatarUrl;

  const SteamProfile(
      {required this.steamId64,
      required this.personaName,
      required this.avatarUrl});

  Map<String, dynamic> toJson() {
    return {
      'steamid': steamId64,
      'personaname': personaName,
      'avatarfull': avatarUrl,
    };
  }

  factory SteamProfile.fromJson(Map<String, dynamic> json) {
    return SteamProfile(
      steamId64: '${json['steamid'] ?? ''}',
      personaName: '${json['personaname'] ?? 'Steam'}',
      avatarUrl:
          '${json['avatarfull'] ?? json['avatarmedium'] ?? json['avatar'] ?? ''}',
    );
  }
}

class SteamGame {
  final int appId;
  final String name;
  final int playtimeForever;
  final int playtime2Weeks;
  final int lastPlayedUnix;
  final int latestAchievementUnix;
  final int unlocked;
  final int total;
  final bool progressLoaded;
  final bool hasAchievements;
  final String appType;
  final bool typeLoaded;
  final bool manuallyAdded;
  final String sourceUrl;
  final String storeHeaderUrl;

  const SteamGame({
    required this.appId,
    required this.name,
    required this.playtimeForever,
    this.playtime2Weeks = 0,
    this.lastPlayedUnix = 0,
    this.latestAchievementUnix = 0,
    this.unlocked = 0,
    this.total = 0,
    this.progressLoaded = false,
    this.hasAchievements = true,
    this.appType = 'unknown',
    this.typeLoaded = false,
    this.manuallyAdded = false,
    this.sourceUrl = '',
    this.storeHeaderUrl = '',
  });

  double get progress => total == 0 ? 0 : unlocked / total;
  String get headerUrl => storeHeaderUrl.trim().isNotEmpty
      ? storeHeaderUrl.trim()
      : 'https://cdn.akamai.steamstatic.com/steam/apps/$appId/header.jpg';
  String get sharedHeaderUrl =>
      'https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/$appId/header.jpg';
  String get capsuleUrl =>
      'https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/$appId/capsule_616x353.jpg';

  SteamGame copyWith(
      {int? playtimeForever,
      int? playtime2Weeks,
      int? unlocked,
      int? total,
      bool? progressLoaded,
      bool? hasAchievements,
      String? appType,
      bool? typeLoaded,
      int? lastPlayedUnix,
      int? latestAchievementUnix,
      bool? manuallyAdded,
      String? sourceUrl,
      String? storeHeaderUrl}) {
    return SteamGame(
      appId: appId,
      name: name,
      playtimeForever: playtimeForever ?? this.playtimeForever,
      playtime2Weeks: playtime2Weeks ?? this.playtime2Weeks,
      lastPlayedUnix: lastPlayedUnix ?? this.lastPlayedUnix,
      latestAchievementUnix:
          latestAchievementUnix ?? this.latestAchievementUnix,
      unlocked: unlocked ?? this.unlocked,
      total: total ?? this.total,
      progressLoaded: progressLoaded ?? this.progressLoaded,
      hasAchievements: hasAchievements ?? this.hasAchievements,
      appType: appType ?? this.appType,
      typeLoaded: typeLoaded ?? this.typeLoaded,
      manuallyAdded: manuallyAdded ?? this.manuallyAdded,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      storeHeaderUrl: storeHeaderUrl ?? this.storeHeaderUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'appid': appId,
      'name': name,
      'playtime_forever': playtimeForever,
      'playtime_2weeks': playtime2Weeks,
      'rtime_last_played': lastPlayedUnix,
      'latest_achievement_unix': latestAchievementUnix,
      'unlocked': unlocked,
      'total': total,
      'progress_loaded': progressLoaded,
      'has_achievements': hasAchievements,
      'app_type': appType,
      'type_loaded': typeLoaded,
      'manually_added': manuallyAdded,
      'source_url': sourceUrl,
      'store_header_url': storeHeaderUrl,
    };
  }

  factory SteamGame.fromCacheJson(Map<String, dynamic> json) {
    final base = SteamGame.fromJson(json);
    return base.copyWith(
      unlocked: intFromAny(json['unlocked']),
      total: intFromAny(json['total']),
      progressLoaded: boolFromAny(json['progress_loaded']),
      hasAchievements: json.containsKey('has_achievements')
          ? boolFromAny(json['has_achievements'])
          : true,
      appType: '${json['app_type'] ?? 'unknown'}',
      typeLoaded: boolFromAny(json['type_loaded']),
      manuallyAdded: boolFromAny(json['manually_added']),
      sourceUrl: '${json['source_url'] ?? ''}',
      storeHeaderUrl: '${json['store_header_url'] ?? ''}',
      lastPlayedUnix: intFromAny(json['rtime_last_played']),
      latestAchievementUnix: intFromAny(json['latest_achievement_unix']),
    );
  }

  factory SteamGame.fromJson(Map<String, dynamic> json) {
    final appId = intFromAny(json['appid']);
    return SteamGame(
      appId: appId,
      name: '${json['name'] ?? 'App $appId'}',
      playtimeForever: intFromAny(json['playtime_forever']),
      playtime2Weeks: intFromAny(json['playtime_2weeks']),
      lastPlayedUnix: intFromAny(json['rtime_last_played']),
      storeHeaderUrl:
          '${json['header_image'] ?? json['capsule_image'] ?? ''}',
    );
  }
}

class SteamAppDetails {
  final int appId;
  final String type;
  final bool utility;
  final String headerImageUrl;

  const SteamAppDetails(
      {required this.appId,
      required this.type,
      this.utility = false,
      this.headerImageUrl = ''});
}

class SteamAchievement {
  final String apiName;
  final String name;
  final String description;
  final String icon;
  final String iconGray;
  final bool hidden;
  final bool achieved;
  final double? globalPercent;
  final int unlockTime;
  final String groupName;
  final int progressCurrent;
  final int progressTotal;
  final int obtainability;

  const SteamAchievement({
    required this.apiName,
    required this.name,
    required this.description,
    required this.icon,
    required this.iconGray,
    required this.hidden,
    required this.achieved,
    this.globalPercent,
    this.unlockTime = 0,
    this.groupName = '',
    this.progressCurrent = 0,
    this.progressTotal = 0,
    this.obtainability = 0,
  });

  Map<String, dynamic> toJson() {
    return {
      'apiname': apiName,
      'displayName': name,
      'description': description,
      'icon': icon,
      'icongray': iconGray,
      'hidden': hidden,
      'achieved': achieved,
      'global_percent': globalPercent,
      'unlocktime': unlockTime,
      'group_name': groupName,
      'progress_current': progressCurrent,
      'progress_total': progressTotal,
      'obtainability': obtainability,
    };
  }

  factory SteamAchievement.fromJson(Map<String, dynamic> json) {
    return SteamAchievement(
      apiName: '${json['apiname'] ?? json['apiName'] ?? ''}',
      name: '${json['displayName'] ?? json['name'] ?? json['apiname'] ?? ''}',
      description: '${json['description'] ?? ''}',
      icon: '${json['icon'] ?? ''}',
      iconGray: '${json['icongray'] ?? json['iconGray'] ?? ''}',
      hidden: boolFromAny(json['hidden']),
      achieved: boolFromAny(json['achieved']),
      globalPercent:
          doubleFromAny(json['global_percent'] ?? json['globalPercent']),
      unlockTime: intFromAny(json['unlocktime'] ?? json['unlockTime']),
      groupName: '${json['group_name'] ?? json['groupName'] ?? ''}',
      progressCurrent:
          intFromAny(json['progress_current'] ?? json['progressCurrent']),
      progressTotal:
          intFromAny(json['progress_total'] ?? json['progressTotal']),
      obtainability: intFromAny(json['obtainability']),
    );
  }
}

class TrophySummary {
  final int unlocked;
  final int total;

  const TrophySummary({required this.unlocked, required this.total});

  double get progress => total == 0 ? 0 : unlocked / total;
  int get percent => (progress * 100).round();
}

class ProfileStats {
  final int totalPlaytimeMinutes;
  final int totalGames;
  final int loadedGames;
  final int completedGames;
  final int perfectGameAchievements;
  final int totalAchievements;

  const ProfileStats({
    required this.totalPlaytimeMinutes,
    required this.totalGames,
    required this.loadedGames,
    required this.completedGames,
    required this.perfectGameAchievements,
    required this.totalAchievements,
  });

  double get totalPlaytimeHours => totalPlaytimeMinutes / 60;

  factory ProfileStats.fromGames(List<SteamGame> games) {
    final loaded = games
        .where((game) => game.progressLoaded && game.hasAchievements)
        .toList();
    final perfect = loaded
        .where((game) => game.total > 0 && game.unlocked == game.total)
        .toList();
    return ProfileStats(
      totalPlaytimeMinutes:
          games.fold(0, (sum, game) => sum + game.playtimeForever),
      totalGames: games.length,
      loadedGames: loaded.length,
      completedGames: perfect.length,
      perfectGameAchievements: perfect.fold(0, (sum, game) => sum + game.total),
      totalAchievements: loaded.fold(0, (sum, game) => sum + game.total),
    );
  }
}
