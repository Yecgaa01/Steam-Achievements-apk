import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/steam_models.dart';

class SteamStoreSearchResult {
  final int appId;
  final String name;
  final String imageUrl;
  final bool suspiciousAddon;
  final String sourceUrl;

  const SteamStoreSearchResult(
      {required this.appId,
      required this.name,
      this.imageUrl = '',
      this.suspiciousAddon = false,
      this.sourceUrl = ''});
}

class NoAchievementsException implements Exception {}

class PlayerAchievementState {
  final bool achieved;
  final int unlockTime;

  const PlayerAchievementState({required this.achieved, this.unlockTime = 0});
}

class PublicAchievementProgress {
  final Set<String> achievedApiNames;
  final int unlockedCount;
  final int totalCount;
  final Map<String, TrophySummary> partialProgress;
  final Map<String, TrophySummary> partialProgressByTitle;
  final List<SteamAchievement> achievements;

  const PublicAchievementProgress({
    required this.achievedApiNames,
    required this.unlockedCount,
    this.totalCount = 0,
    this.partialProgress = const {},
    this.partialProgressByTitle = const {},
    this.achievements = const [],
  });
}

class SteamApi {
  static const _apiBase = 'https://api.steampowered.com';

  final http.Client _client;

  SteamApi({http.Client? client}) : _client = client ?? http.Client();

  Future<SteamProfile> getProfile(SteamConfig config) async {
    final uri =
        Uri.parse('$_apiBase/ISteamUser/GetPlayerSummaries/v0002/').replace(
      queryParameters: {
        'key': config.normalizedApiKey,
        'steamids': config.normalizedSteamId64,
        'format': 'json',
      },
    );
    final data = await _getJson(uri);
    final players =
        ((data['response'] as Map<String, dynamic>?)?['players'] as List?) ??
            const [];
    if (players.isNotEmpty && players.first is Map<String, dynamic>) {
      return SteamProfile.fromJson(players.first as Map<String, dynamic>);
    }
    return SteamProfile(
        steamId64: config.normalizedSteamId64,
        personaName: 'Steam',
        avatarUrl: '');
  }

  Future<List<SteamGame>> getOwnedGames(SteamConfig config) async {
    final uri =
        Uri.parse('$_apiBase/IPlayerService/GetOwnedGames/v0001/').replace(
      queryParameters: {
        'key': config.normalizedApiKey,
        'steamid': config.normalizedSteamId64,
        'format': 'json',
        'include_appinfo': 'true',
        'include_played_free_games': 'true',
      },
    );
    final data = await _getJson(uri);
    final games =
        ((data['response'] as Map<String, dynamic>?)?['games'] as List?) ??
            const [];
    final parsed = games
        .whereType<Map<String, dynamic>>()
        .map(SteamGame.fromJson)
        .toList();
    parsed.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return parsed;
  }

  Future<Map<int, SteamAppDetails>> getAppDetails(List<int> appIds) async {
    final result = <int, SteamAppDetails>{};
    final uniqueAppIds = appIds.toSet().toList();
    for (final batch in _chunk(uniqueAppIds, 5)) {
      final details = await Future.wait(batch.map(_getSingleAppDetails));
      for (final detail in details) {
        result[detail.appId] = detail;
      }
    }
    return result;
  }

  Future<SteamAppDetails> _getSingleAppDetails(int appId) async {
    final uri =
        Uri.parse('https://store.steampowered.com/api/appdetails').replace(
      queryParameters: {
        'appids': '$appId',
      },
    );
    try {
      final data = await _getJsonValue(uri);
      final entry = data is Map<String, dynamic> ? data['$appId'] : null;
      if (entry is! Map<String, dynamic>) {
        return SteamAppDetails(appId: appId, type: 'unknown');
      }
      if (entry['success'] == false) {
        return SteamAppDetails(appId: appId, type: 'unlisted');
      }
      final details = entry['data'];
      if (details is! Map<String, dynamic>) {
        return SteamAppDetails(appId: appId, type: 'unknown');
      }
      final type = '${details['type'] ?? 'unknown'}';
      final genres =
          (details['genres'] as List?)?.whereType<Map<String, dynamic>>() ??
              const Iterable<Map<String, dynamic>>.empty();
      final utility = genres.any((genre) {
        final id = '${genre['id'] ?? ''}';
        final description = '${genre['description'] ?? ''}'.toLowerCase();
        return id == '57' || description == 'utilities';
      });
      return SteamAppDetails(
          appId: appId,
          type: type.isEmpty ? 'unknown' : type,
          utility: utility);
    } catch (_) {
      return SteamAppDetails(appId: appId, type: 'unknown');
    }
  }

  List<List<T>> _chunk<T>(List<T> items, int size) {
    final chunks = <List<T>>[];
    for (var index = 0; index < items.length; index += size) {
      chunks.add(items.sublist(index, (index + size).clamp(0, items.length)));
    }
    return chunks;
  }

  int? extractAppId(String input) {
    final trimmed = input.trim();
    final direct = int.tryParse(trimmed);
    if (direct != null) return direct;
    final patterns = [
      RegExp(r'/app/(\d{2,10})', caseSensitive: false),
      RegExp(r'/stats/(\d{2,10})', caseSensitive: false),
      RegExp(r'''appid[="'\s:]+(\d{2,10})''', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(trimmed);
      final appId = int.tryParse(match?.group(1) ?? '');
      if (appId != null) return appId;
    }
    return null;
  }

  Future<List<SteamStoreSearchResult>> searchStore(String query) async {
    final extracted = extractAppId(query);
    if (extracted != null) {
      return [
        SteamStoreSearchResult(
          appId: extracted,
          name: 'App $extracted',
          sourceUrl: query.trim(),
        )
      ];
    }
    final term = query.trim();
    if (term.isEmpty) return const [];
    final uri = Uri.parse('https://store.steampowered.com/api/storesearch/')
        .replace(queryParameters: {'term': term, 'cc': 'us', 'l': 'english'});
    var data = await _getJsonValue(uri);
    var items = data is Map<String, dynamic> ? data['items'] : null;
    if (items is! List || items.isEmpty) {
      final fallbackUri = Uri.parse(
          'https://steamcommunity.com/actions/SearchApps/${Uri.encodeComponent(term)}');
      data = await _getJsonValue(fallbackUri);
      items = data is List
          ? data
          : data is Map<String, dynamic>
              ? data['apps']
              : null;
    }
    if (items is! List) return const [];
    final results = items
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final appId = intFromAny(item['id']);
          final name = '${item['name'] ?? 'App $appId'}';
          return SteamStoreSearchResult(
            appId: appId,
            name: name,
            imageUrl: '${item['tiny_image'] ?? ''}',
            suspiciousAddon: _looksLikeAddonName(name),
          );
        })
        .where((result) => result.appId > 0)
        .toList();
    results.sort((a, b) {
      if (a.suspiciousAddon != b.suspiciousAddon) {
        return a.suspiciousAddon ? 1 : -1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return results.take(20).toList();
  }

  bool _looksLikeAddonName(String name) {
    final lower = name.toLowerCase();
    return lower.contains('dlc') ||
        lower.contains('soundtrack') ||
        lower.contains('ost') ||
        lower.contains('artbook') ||
        lower.contains('art book') ||
        lower.contains('season pass') ||
        lower.contains('bonus content') ||
        lower.contains('demo') ||
        lower.contains('trailer') ||
        lower.contains('upgrade');
  }

  bool _hasAchievementMarkers(String body) {
    final lower = body.toLowerCase();
    final hasMarkers = lower.contains('achieverow') ||
        lower.contains('achievetxt') ||
        lower.contains('achievements') ||
        lower.contains('achievement');
    if (hasMarkers) return true;
    if (lower.contains('steam guard') ||
        lower.contains('login') && lower.contains('password')) {
      return false;
    }
    return false;
  }

  Future<bool> _hasPublicAchievementsAt(Uri uri) async {
    final response = await _client.get(
      uri,
      headers: const {
        'User-Agent': 'Mozilla/5.0 SteamAchievements/1.0',
        'Accept': 'text/html,application/xhtml+xml'
      },
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }
    return _hasAchievementMarkers(response.body);
  }

  Future<bool> hasPublicAchievementPage(
      SteamConfig config, SteamStoreSearchResult result) async {
    final appId = result.appId;
    final sourceUri = Uri.tryParse(result.sourceUrl);
    if (sourceUri != null && sourceUri.hasScheme) {
      try {
        if (await _hasPublicAchievementsAt(sourceUri)) {
          return true;
        }
      } catch (_) {
        // Fall back to public community pages below.
      }
    }

    try {
      if ((await _getAchievementSchema(config, appId)).isNotEmpty) {
        return true;
      }
    } catch (_) {
      // Fall back to public community pages below.
    }

    for (final uri in [
      Uri.parse('https://steamcommunity.com/stats/$appId/achievements/'),
      Uri.parse(
          'https://steamcommunity.com/profiles/${config.normalizedSteamId64}/stats/$appId/achievements/'),
    ]) {
      try {
        if (await _hasPublicAchievementsAt(uri)) {
          return true;
        }
      } catch (_) {
        // Try the next public source.
      }
    }
    return false;
  }

  Future<SteamGame?> buildManualGame(
      SteamConfig config, SteamStoreSearchResult result) async {
    final details = await getAppDetails([result.appId]);
    final detail = details[result.appId];
    if (detail != null &&
        detail.type != 'unknown' &&
        (detail.type != 'game' || detail.utility)) {
      return null;
    }
    final hasPublicPage = await hasPublicAchievementPage(config, result);
    final schema = await _getAchievementSchema(config, result.appId)
        .catchError((_) => const <Map<String, dynamic>>[]);
    if (!hasPublicPage && schema.isEmpty && result.sourceUrl.isEmpty) {
      return null;
    }
    return SteamGame(
      appId: result.appId,
      name: result.name,
      playtimeForever: 0,
      progressLoaded: false,
      hasAchievements: true,
      appType: 'game',
      typeLoaded: true,
      manuallyAdded: true,
      sourceUrl: result.sourceUrl,
    );
  }

  Uri? _publicAchievementUri(SteamConfig config, SteamGame game) {
    final sourceUri = Uri.tryParse(game.sourceUrl);
    if (sourceUri != null && sourceUri.hasScheme) return sourceUri;
    if (config.normalizedSteamId64.isEmpty) return null;
    return Uri.parse(
        'https://steamcommunity.com/profiles/${config.normalizedSteamId64}/stats/${game.appId}/achievements/');
  }

  Future<PublicAchievementProgress?> _getPublicAchievementProgress(
      SteamConfig config, SteamGame game,
      {List<Map<String, dynamic>>? schema}) async {
    final sourceUri = _publicAchievementUri(config, game);
    if (sourceUri == null) return null;
    final response = await _client.get(
      sourceUri,
      headers: const {
        'User-Agent': 'Mozilla/5.0 SteamAchievements/1.0',
        'Accept': 'text/html,application/xhtml+xml'
      },
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    if (!_hasAchievementMarkers(response.body)) return null;

    final pageProgressMatch = RegExp(
            r'(\d+)\s+of\s+(\d+)\s+\([^)]*\)\s+achievements\s+earned',
            caseSensitive: false)
        .firstMatch(_decodeHtml(response.body));
    final pageUnlocked = pageProgressMatch == null
        ? 0
        : int.tryParse(pageProgressMatch.group(1) ?? '') ?? 0;
    final pageTotal = pageProgressMatch == null
        ? 0
        : int.tryParse(pageProgressMatch.group(2) ?? '') ?? 0;

    schema ??= await _getAchievementSchema(config, game.appId);
    final matchingSchema = config.languageCode == 'en'
        ? schema
        : <Map<String, dynamic>>[
            ...schema,
            ...await _getAchievementSchema(
                config.copyWith(languageCode: 'en'), game.appId),
          ];
    final iconToApi = <String, String>{};
    final nameToApi = <String, String>{};
    for (final achievement in matchingSchema) {
      final apiName = '${achievement['name'] ?? ''}';
      if (apiName.isEmpty) continue;
      final iconFile = _imageFileName('${achievement['icon'] ?? ''}');
      final grayFile = _imageFileName('${achievement['icongray'] ?? ''}');
      final name =
          _normalizeMatchText('${achievement['displayName'] ?? apiName}');
      if (iconFile.isNotEmpty) iconToApi[iconFile] = apiName;
      if (grayFile.isNotEmpty) iconToApi[grayFile] = apiName;
      if (name.isNotEmpty) nameToApi[name] = apiName;
    }

    final achieved = <String>{};
    var unlockedCount = 0;
    final blocks = RegExp(
            r'<div[^>]+class="[^"]*achieveRow[^"]*"[\s\S]*?(?=<div[^>]+class="[^"]*achieveRow|<br><br><br>|</body>|$)',
            caseSensitive: false)
        .allMatches(response.body)
        .map((match) => match.group(0) ?? '')
        .where((block) => block.trim().isNotEmpty)
        .toList();
    final scanBlocks = blocks.isNotEmpty
        ? blocks
        : RegExp(r'<h3[\s\S]*?</h5>[\s\S]*?(?:Unlocked[^<\n]*|\d+\s*/\s*\d+)?',
                caseSensitive: false)
            .allMatches(response.body)
            .map((match) => match.group(0) ?? '')
            .toList();

    final partialProgress = <String, TrophySummary>{};
    final partialProgressByTitle = <String, TrophySummary>{};
    final publicAchievements = <SteamAchievement>[];
    for (final block in scanBlocks) {
      final imageMatch = RegExp(r'<img[^>]+src="([^"]+)"', caseSensitive: false)
          .firstMatch(block);
      final titleMatch =
          RegExp(r'<h3[^>]*>([\s\S]*?)</h3>', caseSensitive: false)
              .firstMatch(block);
      final title = _decodeHtml(_stripHtml(titleMatch?.group(1) ?? ''));
      final normalizedTitle = _normalizeMatchText(title);
      final imageApi =
          iconToApi[_imageFileName(_decodeHtml(imageMatch?.group(1) ?? ''))];
      final titleApi = nameToApi[normalizedTitle];
      final apiName = imageApi ?? titleApi;
      if (apiName != null && apiName.isNotEmpty) {
        final progressMatch =
            RegExp(r'(\d+)\s*/\s*(\d+)').firstMatch(_stripHtml(block));
        if (progressMatch != null) {
          final current = int.tryParse(progressMatch.group(1) ?? '') ?? 0;
          final total = int.tryParse(progressMatch.group(2) ?? '') ?? 0;
          if (total > 0) {
            final summary = TrophySummary(unlocked: current, total: total);
            partialProgressByTitle[normalizedTitle] = summary;
            partialProgress[apiName] = summary;
          }
        }
      }
      if (title.isEmpty ||
          RegExp(r'hidden\s+achievements?\s+remaining', caseSensitive: false)
              .hasMatch(title)) {
        continue;
      }
      final descriptionMatch =
          RegExp(r'<h5[^>]*>([\s\S]*?)</h5>', caseSensitive: false)
              .firstMatch(block);
      final imageUrl = _decodeHtml(imageMatch?.group(1) ?? '');
      final isUnlocked =
          RegExp(r'Unlocked\s', caseSensitive: false).hasMatch(block);
      if (apiName == null &&
          !isUnlocked &&
          !partialProgressByTitle.containsKey(normalizedTitle)) {
        continue;
      }
      if (title.isNotEmpty) {
        final progress = partialProgressByTitle[normalizedTitle];
        publicAchievements.add(SteamAchievement(
          apiName: apiName ?? normalizedTitle,
          name: title,
          description:
              _decodeHtml(_stripHtml(descriptionMatch?.group(1) ?? '')),
          icon: imageUrl,
          iconGray: imageUrl,
          hidden: false,
          achieved: isUnlocked,
          progressCurrent: progress?.unlocked ?? 0,
          progressTotal: progress?.total ?? 0,
        ));
      }
      if (!isUnlocked) {
        continue;
      }
      unlockedCount++;
      if (apiName != null && apiName.isNotEmpty) achieved.add(apiName);
    }

    return PublicAchievementProgress(
      achievedApiNames: achieved,
      unlockedCount: unlockedCount > 0 ? unlockedCount : pageUnlocked,
      totalCount: pageTotal,
      partialProgress: partialProgress,
      partialProgressByTitle: partialProgressByTitle,
      achievements: publicAchievements,
    );
  }

  Future<SteamGame> hydrateGameProgress(SteamConfig config, SteamGame game,
      {bool allowPublicFallback = false}) async {
    try {
      final schema = await _getAchievementSchema(config, game.appId);
      if (schema.isEmpty) {
        throw NoAchievementsException();
      }
      final player = await _getPlayerAchievements(config, game.appId);
      return game.copyWith(
        unlocked: player.values.where((state) => state.achieved).length,
        total: schema.length,
        progressLoaded: true,
        hasAchievements: true,
      );
    } on NoAchievementsException {
      if (allowPublicFallback ||
          game.manuallyAdded ||
          game.sourceUrl.isNotEmpty) {
        try {
          final publicProgress =
              await _getPublicAchievementProgress(config, game);
          if (publicProgress != null && publicProgress.totalCount > 0) {
            return game.copyWith(
              unlocked: publicProgress.unlockedCount,
              total: publicProgress.totalCount,
              progressLoaded: true,
              hasAchievements: true,
            );
          }
        } catch (_) {
          // Keep the game visible if public fallback fails.
        }
        return game.copyWith(progressLoaded: false, hasAchievements: true);
      }
      return game.copyWith(
          unlocked: 0, total: 0, progressLoaded: true, hasAchievements: false);
    } catch (_) {
      if (allowPublicFallback ||
          game.manuallyAdded ||
          game.sourceUrl.isNotEmpty) {
        try {
          final publicProgress =
              await _getPublicAchievementProgress(config, game);
          if (publicProgress != null && publicProgress.totalCount > 0) {
            return game.copyWith(
              unlocked: publicProgress.unlockedCount,
              total: publicProgress.totalCount,
              progressLoaded: true,
              hasAchievements: true,
            );
          }
        } catch (_) {
          // Keep the game visible if public fallback fails.
        }
      }
      return game;
    }
  }

  Future<List<SteamAchievement>> getAchievementsForGame(
      SteamConfig config, SteamGame game) async {
    final schema = await _getAchievementSchema(config, game.appId);
    if (schema.isEmpty) {
      throw NoAchievementsException();
    }
    Map<String, PlayerAchievementState> player = const {};
    PublicAchievementProgress? publicProgress;
    publicProgress =
        await _getPublicAchievementProgress(config, game, schema: schema);
    try {
      player = await _getPlayerAchievements(config, game.appId);
    } catch (_) {
      player = const {};
    }
    return _buildAchievements(config, game.appId, schema, player,
        publicProgress: publicProgress);
  }

  Future<List<SteamAchievement>> getAchievements(
      SteamConfig config, int appId) async {
    final schema = await _getAchievementSchema(config, appId);
    if (schema.isEmpty) {
      throw NoAchievementsException();
    }
    final player = await _getPlayerAchievements(config, appId);
    return _buildAchievements(config, appId, schema, player);
  }

  Future<List<SteamAchievement>> _buildAchievements(
      SteamConfig config,
      int appId,
      List<Map<String, dynamic>> schema,
      Map<String, PlayerAchievementState> player,
      {PublicAchievementProgress? publicProgress}) async {
    final global = await _getGlobalPercentages(appId);
    final steamHuntersDescriptions = await _getSteamHuntersDescriptions(appId);
    final obtainability = await _getSteamHuntersObtainability(appId);
    final steamHuntersGroups = config.separateDlcAchievements
        ? await _getSteamHuntersGroups(appId)
        : <String, String>{};
    final exophaseGroups =
        config.separateDlcAchievements && steamHuntersGroups.isEmpty
            ? await _getExophaseGroups(config, appId)
            : <String, String>{};
    final groups =
        steamHuntersGroups.isNotEmpty ? steamHuntersGroups : exophaseGroups;

    return schema
        .map((achievement) {
          final apiName = '${achievement['name'] ?? ''}';
          final steamDescription = '${achievement['description'] ?? ''}';
          return SteamAchievement(
            apiName: apiName,
            name: '${achievement['displayName'] ?? apiName}',
            description: steamDescription.isNotEmpty
                ? steamDescription
                : (steamHuntersDescriptions[apiName] ?? ''),
            icon: '${achievement['icon'] ?? ''}',
            iconGray: '${achievement['icongray'] ?? ''}',
            hidden: boolFromAny(achievement['hidden']),
            achieved: publicProgress != null
                ? publicProgress.achievedApiNames.contains(apiName)
                : (player[apiName]?.achieved ?? false),
            globalPercent: global[apiName],
            unlockTime: player[apiName]?.unlockTime ?? 0,
            groupName: _groupNameForApiName(apiName, groups),
            progressCurrent:
                publicProgress?.partialProgress[apiName]?.unlocked ??
                    publicProgress
                        ?.partialProgressByTitle[_normalizeMatchText(
                            '${achievement['displayName'] ?? apiName}')]
                        ?.unlocked ??
                    0,
            progressTotal: publicProgress?.partialProgress[apiName]?.total ??
                publicProgress
                    ?.partialProgressByTitle[_normalizeMatchText(
                        '${achievement['displayName'] ?? apiName}')]
                    ?.total ??
                0,
            obtainability: obtainability[apiName] ?? 0,
          );
        })
        .where((achievement) => achievement.apiName.isNotEmpty)
        .toList();
  }

  String _groupNameForApiName(String apiName, Map<String, String> groups) {
    final exact = groups[apiName];
    if (exact != null) return exact;
    final numeric = _numericApiKey(apiName);
    if (numeric == null) return '';
    String? match;
    for (final entry in groups.entries) {
      if (_numericApiKey(entry.key) != numeric) continue;
      if (match != null && match != entry.value) return '';
      match = entry.value;
    }
    return match ?? '';
  }

  String? _numericApiKey(String value) {
    final matches = RegExp(r'\d+').allMatches(value).toList();
    if (matches.isEmpty) return null;
    final raw = matches.last.group(0) ?? '';
    final normalized = raw.replaceFirst(RegExp(r'^0+'), '');
    return normalized.isEmpty ? '0' : normalized;
  }

  Future<List<Map<String, dynamic>>> _getAchievementSchema(
      SteamConfig config, int appId) async {
    final uri =
        Uri.parse('$_apiBase/ISteamUserStats/GetSchemaForGame/v2/').replace(
      queryParameters: {
        'key': config.normalizedApiKey,
        'appid': '$appId',
        'l': config.languageCode == 'en' ? 'english' : 'brazilian',
      },
    );
    final data = await _getJson(uri, noAchievementsOn400: true);
    final achievements =
        (((data['game'] as Map<String, dynamic>?)?['availableGameStats']
                as Map<String, dynamic>?)?['achievements'] as List?) ??
            const [];
    return achievements.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, String>> _getSteamHuntersDescriptions(int appId) async {
    final uri =
        Uri.parse('https://steamhunters.com/api/apps/$appId/achievements');
    try {
      final data = await _getJsonValue(uri);
      final achievements = data is List ? data : const [];
      return {
        for (final item in achievements.whereType<Map<String, dynamic>>())
          if (item['apiName'] != null &&
              '${item['description'] ?? ''}'.trim().isNotEmpty)
            '${item['apiName']}': '${item['description']}'.trim(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, int>> _getSteamHuntersObtainability(int appId) async {
    final uri =
        Uri.parse('https://steamhunters.com/api/apps/$appId/achievements');
    try {
      final data = await _getJsonValue(uri);
      final achievements = data is List ? data : const [];
      return {
        for (final item in achievements.whereType<Map<String, dynamic>>())
          if (item['apiName'] != null)
            '${item['apiName']}': intFromAny(item['obtainability']),
      };
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> _getSteamHuntersGroups(int appId) async {
    final uri = Uri.parse(
        'https://steamhunters.com/apps/$appId/achievements?group=dlcandupdate&sort=sh');
    try {
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) return {};
      return _parseSteamHuntersGroups(response.body);
    } catch (_) {
      return {};
    }
  }

  Map<String, String> _parseSteamHuntersGroups(String html) {
    final groups = <String, String>{};
    final groupPattern = RegExp(
      r'<li[^>]*data-flash="[^\"]*"[\s\S]*?href="[^"]*#(collapse\d+)"[\s\S]*?<h3[^>]*>([\s\S]*?)</h3>[\s\S]*?<ol[^>]*id="\1"[^>]*>([\s\S]*?)(?=<li[^>]*data-flash=|</ol>\s*</sh-check-list>|</ol>\s*</div>)',
      caseSensitive: false,
    );
    final apiPattern = RegExp(r'API Name:\s*([^"\n<]+)', caseSensitive: false);
    for (final match in groupPattern.allMatches(html)) {
      final rawGroupName = _decodeHtml(_stripHtml(match.group(2) ?? '').trim());
      final groupName = rawGroupName
          .replaceFirst(RegExp(r"\s+\d{1,2}\s+[A-Za-z]{3}\s+'\d{2}$"), '')
          .trim();
      final body = match.group(3) ?? '';
      if (groupName.isEmpty || body.isEmpty) continue;
      for (final apiMatch in apiPattern.allMatches(body)) {
        final apiName = _decodeHtml((apiMatch.group(1) ?? '').trim());
        if (apiName.isNotEmpty && !groups.containsKey(apiName)) {
          groups[apiName] = groupName;
        }
      }
    }
    return groups;
  }

  String _stripHtml(String value) => value.replaceAll(RegExp(r'<[^>]+>'), ' ');

  String _decodeHtml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<Map<String, String>> _getExophaseGroups(
      SteamConfig config, int appId) async {
    try {
      final englishSchema = config.languageCode == 'en'
          ? await _getAchievementSchema(config, appId)
          : await _getAchievementSchema(
              config.copyWith(languageCode: 'en'), appId);
      final nameToApi = <String, String>{};
      final nameDescriptionToApi = <String, String>{};
      final imageFileToApi = <String, String>{};
      for (final achievement in englishSchema) {
        final apiName = '${achievement['name'] ?? ''}';
        final name =
            _normalizeMatchText('${achievement['displayName'] ?? apiName}');
        final description =
            _normalizeMatchText('${achievement['description'] ?? ''}');
        final iconFile = _imageFileName('${achievement['icon'] ?? ''}');
        final iconGrayFile = _imageFileName('${achievement['icongray'] ?? ''}');
        if (apiName.isEmpty || name.isEmpty) {
          continue;
        }
        nameToApi[name] = apiName;
        if (description.isNotEmpty) {
          nameDescriptionToApi['$name\n$description'] = apiName;
        }
        if (iconFile.isNotEmpty) {
          imageFileToApi[iconFile] = apiName;
        }
        if (iconGrayFile.isNotEmpty) {
          imageFileToApi[iconGrayFile] = apiName;
        }
      }
      if (nameToApi.isEmpty && imageFileToApi.isEmpty) {
        return {};
      }

      final gameName = await _getStoreGameName(appId);
      final slug = _exophaseSlug(gameName.isEmpty ? 'app $appId' : gameName);
      final uri =
          Uri.parse('https://www.exophase.com/game/$slug/achievements/');
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return {};
      }
      if (response.body.contains('Just a moment') ||
          response.body.contains('Enable JavaScript and cookies')) {
        return {};
      }
      return _parseExophaseGroups(
          response.body, nameToApi, nameDescriptionToApi, imageFileToApi);
    } catch (_) {
      return {};
    }
  }

  Future<String> _getStoreGameName(int appId) async {
    try {
      final uri =
          Uri.parse('https://store.steampowered.com/api/appdetails').replace(
        queryParameters: {
          'appids': '$appId',
          'filters': 'basic',
        },
      );
      final data = await _getJson(uri);
      final app = data['$appId'];
      final details = app is Map<String, dynamic> ? app['data'] : null;
      if (details is Map<String, dynamic>) return '${details['name'] ?? ''}';
    } catch (_) {}
    return '';
  }

  String _exophaseSlug(String name) {
    final normalized = name
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '$normalized-steam';
  }

  Map<String, String> _parseExophaseGroups(
      String html,
      Map<String, String> nameToApi,
      Map<String, String> nameDescriptionToApi,
      Map<String, String> imageFileToApi) {
    final groups = <String, String>{};
    final headerPattern =
        RegExp(r'<h3 class="dlc-add-on">([\s\S]*?)</h3>', caseSensitive: false);
    final headers = headerPattern.allMatches(html).toList();
    for (var index = 0; index < headers.length; index++) {
      final header = headers[index];
      final groupName = _cleanExophaseGroupName(
          _decodeHtml(_stripHtml(header.group(1) ?? '')));
      if (groupName.isEmpty) continue;
      final nextStart =
          index + 1 < headers.length ? headers[index + 1].start : html.length;
      final block = html.substring(header.end, nextStart);
      final listMatch = RegExp(
              r'<ul class="[^"]*(?:achievement|platform-steam)[^"]*">([\s\S]*?)</ul>',
              caseSensitive: false)
          .firstMatch(block);
      final listBody = listMatch?.group(1) ?? block;
      for (final item in RegExp(r'<li class="[^"]*award[^"]*"[\s\S]*?</li>',
              caseSensitive: false)
          .allMatches(listBody)) {
        final itemHtml = item.group(0) ?? '';
        final nameMatch = RegExp(
                r'<div class="text-medium award-title[^"]*"[\s\S]*?<a [^>]*>([\s\S]*?)</a>',
                caseSensitive: false)
            .firstMatch(itemHtml);
        final descriptionMatch = RegExp(
                r'<div class="award-description[^"]*">[\s\S]*?<p>([\s\S]*?)</p>',
                caseSensitive: false)
            .firstMatch(itemHtml);
        final name = _normalizeMatchText(
            _decodeHtml(_stripHtml(nameMatch?.group(1) ?? '')));
        final description = _normalizeMatchText(
            _decodeHtml(_stripHtml(descriptionMatch?.group(1) ?? '')));
        final imageMatch =
            RegExp(r'<img[^>]+src="([^"]+)"', caseSensitive: false)
                .firstMatch(itemHtml);
        final imageFile =
            _imageFileName(_decodeHtml(imageMatch?.group(1) ?? ''));
        final apiName = imageFileToApi[imageFile] ??
            nameDescriptionToApi['$name\n$description'] ??
            nameToApi[name];
        if (apiName != null && apiName.isNotEmpty) groups[apiName] = groupName;
      }
    }
    return groups;
  }

  String _imageFileName(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final slash = path.lastIndexOf('/');
    return slash >= 0
        ? path.substring(slash + 1).toLowerCase()
        : path.toLowerCase();
  }

  String _cleanExophaseGroupName(String value) {
    return value
        .replaceAll(RegExp(r'\s+Achievements$', caseSensitive: false), '')
        .replaceAll(RegExp(r'^.*? - '), '')
        .trim();
  }

  String _normalizeMatchText(String value) {
    return _decodeHtml(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<Map<String, PlayerAchievementState>> _getPlayerAchievements(
      SteamConfig config, int appId) async {
    final uri =
        Uri.parse('$_apiBase/ISteamUserStats/GetPlayerAchievements/v0001/')
            .replace(
      queryParameters: {
        'key': config.normalizedApiKey,
        'steamid': config.normalizedSteamId64,
        'appid': '$appId',
        'l': config.languageCode == 'en' ? 'english' : 'brazilian',
      },
    );
    final data = await _getJson(uri, noAchievementsOn400: true);
    final achievements = ((data['playerstats']
            as Map<String, dynamic>?)?['achievements'] as List?) ??
        const [];
    return {
      for (final item in achievements.whereType<Map<String, dynamic>>())
        if (item['apiname'] != null)
          '${item['apiname']}': PlayerAchievementState(
            achieved: boolFromAny(item['achieved']),
            unlockTime: intFromAny(item['unlocktime']),
          ),
    };
  }

  Future<Map<String, double>> _getGlobalPercentages(int appId) async {
    final uri = Uri.parse(
            '$_apiBase/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v0002/')
        .replace(
      queryParameters: {
        'gameid': '$appId',
        'format': 'json',
      },
    );
    try {
      final data = await _getJson(uri, noAchievementsOn400: true);
      final achievements = ((data['achievementpercentages']
              as Map<String, dynamic>?)?['achievements'] as List?) ??
          const [];
      return {
        for (final item in achievements.whereType<Map<String, dynamic>>())
          if (item['name'] != null)
            '${item['name']}': doubleFromAny(item['percent']) ?? 0,
      };
    } on NoAchievementsException {
      return {};
    }
  }

  Future<dynamic> _getJsonValue(Uri uri,
      {bool noAchievementsOn400 = false}) async {
    final response = await _client.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'Mozilla/5.0 SteamAchievements/1.0',
      },
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode == 400 && noAchievementsOn400) {
      throw NoAchievementsException();
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception(
          'A Steam recusou o acesso. Confira SteamID64, API key, privacidade do perfil e se os dados de jogos/achievements estão públicos. O jogo também pode estar privado e por isso as achievements dele não aparecem.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Steam API ${response.statusCode}: ${response.body}');
    }
    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> _getJson(Uri uri,
      {bool noAchievementsOn400 = false}) async {
    return await _getJsonValue(uri, noAchievementsOn400: noAchievementsOn400)
        as Map<String, dynamic>;
  }
}
