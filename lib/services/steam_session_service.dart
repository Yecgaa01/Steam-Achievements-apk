import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum SteamSessionStatus { valid, expired, offline, missing, unknown }

class SteamSessionCheck {
  final SteamSessionStatus status;
  final String log;

  const SteamSessionCheck(this.status, this.log);
}

class SteamCookieRefreshResult {
  final bool success;
  final String status;
  final String log;

  const SteamCookieRefreshResult({
    required this.success,
    required this.status,
    required this.log,
  });
}

class SteamSessionService {
  static const _sessionSavedKey = 'steam_session_saved';
  static const _sessionSteamIdKey = 'steam_session_steamid';
  static const _sessionSavedAtKey = 'steam_session_saved_at';
  static const _sessionAutoRefreshAtKey = 'steam_session_auto_refresh_at';
  static const _sessionCookieHeaderKey = 'steam_session_cookie_header';
  static const _sessionRefreshCookieKey = 'steam_session_refresh_cookie';
  static const _sessionLastRefreshStatusKey = 'steam_session_last_refresh_status';
  static const _sessionLastRefreshLogKey = 'steam_session_last_refresh_log';
  static const _sessionProfilePathKey = 'steam_session_profile_path';
  static const _sessionPrivateAchievementsLogKey =
      'steam_session_private_achievements_log';
  static final WebUri steamCommunityUri = WebUri('https://steamcommunity.com');
  static final WebUri steamPoweredLoginUri =
      WebUri('https://login.steampowered.com');
  static final WebUri communityUri = steamCommunityUri;
  static final WebUri loginUri =
      WebUri('https://steamcommunity.com/my/games/?tab=all');

  final CookieManager _cookieManager = CookieManager.instance();
  Future<SteamCookieRefreshResult>? _refreshInFlight;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<bool> hasSavedSession() async {
    final prefs = await _prefs;
    return prefs.getBool(_sessionSavedKey) ?? false;
  }

  Future<String> loadSteamId() async {
    final prefs = await _prefs;
    return prefs.getString(_sessionSteamIdKey) ?? '';
  }

  Future<String> loadCookieHeader() async {
    final prefs = await _prefs;
    return prefs.getString(_sessionCookieHeaderKey) ?? '';
  }

  Future<String> loadRefreshCookieValue() async {
    final prefs = await _prefs;
    return prefs.getString(_sessionRefreshCookieKey) ?? '';
  }

  Future<String> loadLastRefreshStatus() async {
    final prefs = await _prefs;
    return prefs.getString(_sessionLastRefreshStatusKey) ?? '';
  }

  Future<String> loadLastRefreshLog() async {
    final prefs = await _prefs;
    return prefs.getString(_sessionLastRefreshLogKey) ?? '';
  }

  Future<void> _saveLastRefreshResult(SteamCookieRefreshResult result) async {
    final prefs = await _prefs;
    await prefs.setString(_sessionLastRefreshStatusKey, result.status);
    await prefs.setString(_sessionLastRefreshLogKey, result.log);
  }

  Future<String> loadProfilePath() async {
    final prefs = await _prefs;
    return prefs.getString(_sessionProfilePathKey) ?? '';
  }

  Future<Uri> loadProfileUri() async {
    final path = await loadProfilePath();
    if (path.startsWith('/id/') || path.startsWith('/profiles/')) {
      return Uri.parse('https://steamcommunity.com$path');
    }
    final steamId = await loadSteamId();
    if (steamId.isNotEmpty) {
      return Uri.parse('https://steamcommunity.com/profiles/$steamId/');
    }
    return Uri.parse('https://steamcommunity.com/my/');
  }

  Future<String> _captureSteamRefreshCookie() async {
    final cookies = await _cookieManager.getCookies(url: steamPoweredLoginUri);
    for (final cookie in cookies) {
      if (cookie.name == 'steamRefresh_steam') return cookie.value;
    }
    return '';
  }

  Future<void> _restoreSteamRefreshCookie() async {
    final refresh = await loadRefreshCookieValue();
    if (refresh.isEmpty) return;
    await _cookieManager.setCookie(
      url: steamPoweredLoginUri,
      name: 'steamRefresh_steam',
      value: refresh,
      domain: 'login.steampowered.com',
      path: '/',
      isSecure: true,
      isHttpOnly: true,
    );
  }

  Future<void> _saveRefreshCookieIfAvailable() async {
    final refresh = await _captureSteamRefreshCookie();
    if (refresh.isEmpty) return;
    final prefs = await _prefs;
    await prefs.setString(_sessionRefreshCookieKey, refresh);
  }

  Future<String> _buildCurrentAuthCookieHeader() async {
    final cookies = await _cookieManager.getCookies(url: communityUri);
    String steamLoginSecure = '';
    String sessionId = '';
    String steamLogin = '';
    for (final cookie in cookies) {
      if (cookie.name == 'steamLoginSecure') steamLoginSecure = cookie.value;
      if (cookie.name == 'sessionid') sessionId = cookie.value;
      if (cookie.name == 'steamLogin') steamLogin = cookie.value;
    }
    if (steamLoginSecure.isEmpty || sessionId.isEmpty) return '';
    final parts = <String>[
      'sessionid=$sessionId',
      'steamLoginSecure=$steamLoginSecure',
      if (steamLogin.isNotEmpty) 'steamLogin=$steamLogin',
    ];
    return parts.join('; ');
  }

  Future<String> inferSteamIdFromCookies() async {
    final cookies = await _cookieManager.getCookies(url: communityUri);
    for (final cookie in cookies) {
      if (cookie.name != 'steamLoginSecure' && cookie.name != 'steamLogin') {
        continue;
      }
      final match =
          RegExp(r'^(\d{17})%7C|^(\d{17})\|').firstMatch(cookie.value);
      final steamId = match?.group(1) ?? match?.group(2) ?? '';
      if (steamId.isNotEmpty) return steamId;
    }
    return '';
  }

  Future<bool> syncCookiesFromWebView() async {
    final authCookieHeader = await _buildCurrentAuthCookieHeader();
    if (authCookieHeader.isEmpty) return false;
    await _saveRefreshCookieIfAvailable();
    final prefs = await _prefs;
    await prefs.setBool(_sessionSavedKey, true);
    await prefs.setString(_sessionCookieHeaderKey, authCookieHeader);
    final steamId = await inferSteamIdFromCookies();
    if (steamId.isNotEmpty) {
      await prefs.setString(_sessionSteamIdKey, steamId);
    }
    return true;
  }

  String _profilePathFromUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.host != 'steamcommunity.com') return '';
    final segments = uri.pathSegments;
    if (segments.length < 2) return '';
    final kind = segments[0].toLowerCase();
    if (kind == 'id' || kind == 'profiles') {
      return '/${segments[0]}/${segments[1]}/';
    }
    return '';
  }

  Future<void> saveProfilePathFromUrl(String value) async {
    final path = _profilePathFromUrl(value);
    if (path.isEmpty) return;
    final prefs = await _prefs;
    await prefs.setString(_sessionProfilePathKey, path);
  }

  Future<void> savePrivateAchievementsLog(String log) async {
    final prefs = await _prefs;
    await prefs.setString(_sessionPrivateAchievementsLogKey, log);
  }

  Future<String> loadPrivateAchievementsLog() async {
    final prefs = await _prefs;
    return prefs.getString(_sessionPrivateAchievementsLogKey) ?? '';
  }

  bool _looksLikeSteamLoginPage(String body) {
    final lower = body.toLowerCase();
    return lower.contains('/login/home') ||
        lower.contains('steamcommunity.com/login') ||
        lower.contains('name="username"') &&
            lower.contains('name="password"') ||
        lower.contains('enable javascript and cookies');
  }

  Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('steamcommunity.com')
          .timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<SteamSessionCheck> checkSessionWithDetails(
      {bool tryRefresh = true}) async {
    final log = <String>[];
    void add(String message) =>
        log.add('${DateTime.now().toIso8601String()}  $message');

    add('check=start tryRefresh=$tryRefresh');
    if (!await hasInternetConnection()) {
      add('internet=offline');
      return SteamSessionCheck(SteamSessionStatus.offline, log.join('\n'));
    }
    add('internet=online');
    final hasSession = await hasSavedSession();
    add('hasSession=$hasSession');
    if (!hasSession) {
      return SteamSessionCheck(SteamSessionStatus.missing, log.join('\n'));
    }
    final steamId = await loadSteamId();
    final cookieHeader = await loadCookieHeader();
    final refresh = await loadRefreshCookieValue();
    add('steamId=${steamId.isNotEmpty}');
    add('cookieHeader=${cookieHeader.isNotEmpty} length=${cookieHeader.length}');
    add('steamRefresh=${refresh.isNotEmpty} length=${refresh.length}');
    if (steamId.isEmpty || cookieHeader.isEmpty) {
      return SteamSessionCheck(SteamSessionStatus.missing, log.join('\n'));
    }

    try {
      final uri = await loadProfileUri();
      add('request=$uri');
      final response = await http.get(
        uri,
        headers: {
          'Cookie': cookieHeader,
          'User-Agent': chromeAndroidUserAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 7));
      final body = response.body;
      final lower = body.toLowerCase();
      final looksLogin = _looksLikeSteamLoginPage(body);
      final hasProfileMarkers = lower.contains('profile_header') ||
          lower.contains('profile_header_centered_persona') ||
          lower.contains('actual_persona_name') ||
          lower.contains('profile_in_game_header') ||
          lower.contains('games') ||
          lower.contains('recent activity');
      add('statusCode=${response.statusCode}');
      add('finalUrl=${response.request?.url}');
      add('bodyLength=${body.length}');
      add('looksLogin=$looksLogin');
      add('hasProfileMarkers=$hasProfileMarkers');
      add('title=${RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(body)?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? ''}');

      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          !looksLogin &&
          hasProfileMarkers) {
        final prefs = await _prefs;
        await prefs.setBool(_sessionSavedKey, true);
        await prefs.setInt(
            _sessionSavedAtKey, DateTime.now().millisecondsSinceEpoch);
        add('result=valid');
        return SteamSessionCheck(SteamSessionStatus.valid, log.join('\n'));
      }
      if (tryRefresh && refresh.isNotEmpty) {
        add('refreshTokenExchange=start');
        final tokenRefresh = await refreshWebCookiesFromSteamRefresh();
        add(tokenRefresh.log);
        final tokenRefreshed = await checkSessionWithDetails(tryRefresh: false);
        add('afterTokenRefresh=${tokenRefreshed.status}');
        add(tokenRefreshed.log);
        if (tokenRefreshed.status == SteamSessionStatus.valid) {
          return SteamSessionCheck(SteamSessionStatus.valid, log.join('\n'));
        }
        add('headlessRefresh=start');
        final refreshLog = await testHeadlessRefresh();
        add(refreshLog);
        final refreshed = await checkSessionWithDetails(tryRefresh: false);
        add('afterRefresh=${refreshed.status}');
        add(refreshed.log);
        if (refreshed.status == SteamSessionStatus.valid) {
          return SteamSessionCheck(SteamSessionStatus.valid, log.join('\n'));
        }
      }
      if (looksLogin || response.statusCode == 401 || response.statusCode == 403) {
        await markSessionExpired();
        add('result=expired');
        return SteamSessionCheck(SteamSessionStatus.expired, log.join('\n'));
      }
      add('result=unknown');
      return SteamSessionCheck(SteamSessionStatus.unknown, log.join('\n'));
    } on SocketException catch (error) {
      add('socketException=$error');
      return SteamSessionCheck(SteamSessionStatus.offline, log.join('\n'));
    } on TimeoutException catch (error) {
      add('timeout=$error');
      return SteamSessionCheck(SteamSessionStatus.offline, log.join('\n'));
    } catch (error) {
      add('exception=$error');
      return SteamSessionCheck(SteamSessionStatus.unknown, log.join('\n'));
    }
  }

  Future<SteamSessionStatus> checkSessionStatus({bool tryRefresh = true}) async {
    final result = await checkSessionWithDetails(tryRefresh: tryRefresh);
    return result.status;
  }

  String _randomSessionId() {
    final random = Random.secure();
    const hex = '0123456789abcdef';
    return List.generate(24, (_) => hex[random.nextInt(16)]).join();
  }

  List<String> _splitSetCookieHeader(String? header) {
    if (header == null || header.trim().isEmpty) return const [];
    return header.split(RegExp(r',\s*(?=[^;,]+=)'));
  }

  String _cookieName(String setCookie) {
    final index = setCookie.indexOf('=');
    return index <= 0 ? '' : setCookie.substring(0, index).trim();
  }

  String _cookieValue(String setCookie) {
    final firstPart = setCookie.split(';').first;
    final index = firstPart.indexOf('=');
    return index <= 0 ? '' : firstPart.substring(index + 1).trim();
  }

  String _cookieDomain(String setCookie, Uri fallbackUri) {
    final match = RegExp(r'\bdomain=([^;]+)', caseSensitive: false)
        .firstMatch(setCookie);
    return (match?.group(1) ?? fallbackUri.host)
        .trim()
        .replaceFirst(RegExp(r'^\.'), '');
  }

  Future<http.Response> _postMultipart(
      Uri uri, Map<String, String> fields,
      {Map<String, String> headers = const {}}) async {
    final request = http.MultipartRequest('POST', uri);
    request.fields.addAll(fields);
    request.headers.addAll(headers);
    final streamed = await request.send().timeout(const Duration(seconds: 12));
    return http.Response.fromStream(streamed);
  }

  Future<SteamCookieRefreshResult> refreshWebCookiesFromSteamRefresh() {
    final current = _refreshInFlight;
    if (current != null) return current;
    final future = _refreshWebCookiesFromSteamRefreshInternal();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<SteamCookieRefreshResult> _refreshWebCookiesFromSteamRefreshInternal() async {
    final log = <String>[];
    void add(String message) =>
        log.add('${DateTime.now().toIso8601String()}  $message');

    add('refreshToken=start');
    final refreshToken = await loadRefreshCookieValue();
    final steamId = await loadSteamId();
    add('refreshToken.present=${refreshToken.isNotEmpty}');
    add('steamId.present=${steamId.isNotEmpty}');
    if (refreshToken.isEmpty) {
      final result = SteamCookieRefreshResult(
          success: false, status: 'refresh-token-missing', log: log.join('\n'));
      await _saveLastRefreshResult(result);
      return result;
    }
    if (steamId.isEmpty) {
      final result = SteamCookieRefreshResult(
          success: false, status: 'steamid-missing', log: log.join('\n'));
      await _saveLastRefreshResult(result);
      return result;
    }

    final sessionId = _randomSessionId();
    try {
      final finalizeUri =
          Uri.parse('https://login.steampowered.com/jwt/finalizelogin');
      final candidates = _refreshTokenCandidates(refreshToken);
      add('refreshToken.candidates=${candidates.length}');
      http.Response? finalizeResponse;
      dynamic parsed;
      List<dynamic>? transferInfo;
      var lastFinalizeError = '';
      for (final candidate in candidates) {
        add('candidate.${candidate.key} ${_tokenShape(candidate.value)}');
        add('finalize.request=${candidate.key}');
        final response = await _postMultipart(finalizeUri, {
          'nonce': candidate.value,
          'sessionid': sessionId,
          'redir': 'https://steamcommunity.com/login/home/?goto=',
        }, headers: {
          'Origin': 'https://steamcommunity.com',
          'Referer': 'https://steamcommunity.com/',
          'User-Agent': chromeAndroidUserAgent,
        });
        add('finalize.status.${candidate.key}=${response.statusCode}');
        if (response.statusCode >= 400) {
          lastFinalizeError = 'http-${response.statusCode}';
          continue;
        }
        final body = jsonDecode(response.body);
        if (body is! Map) {
          lastFinalizeError = 'malformed';
          continue;
        }
        if (body['error'] != null) {
          lastFinalizeError = '${body['error']}';
          add('finalize.error.${candidate.key}=${body['error']}');
          continue;
        }
        final info = body['transfer_info'];
        if (info is! List || info.isEmpty) {
          lastFinalizeError = 'transfer-info-missing';
          continue;
        }
        finalizeResponse = response;
        parsed = body;
        transferInfo = info;
        add('finalize.ok=${candidate.key}');
        break;
      }
      if (finalizeResponse == null || parsed is! Map || transferInfo == null) {
        final result = SteamCookieRefreshResult(
            success: false,
            status: lastFinalizeError == 'transfer-info-missing'
                ? 'transfer-info-missing'
                : 'refresh-token-rejected',
            log: log.join('\n'));
        await _saveLastRefreshResult(result);
        return result;
      }
      add('transfer.count=${transferInfo.length}');

      final setCookieRecords = <MapEntry<String, String>>[];
      for (final cookie in _splitSetCookieHeader(finalizeResponse.headers['set-cookie'])) {
        setCookieRecords.add(MapEntry(finalizeUri.host, cookie));
      }
      for (final item in transferInfo) {
        if (item is! Map) continue;
        final url = '${item['url'] ?? ''}';
        final params = item['params'];
        if (url.isEmpty || params is! Map) continue;
        final fields = <String, String>{'steamID': steamId};
        for (final param in params.entries) {
          fields['${param.key}'] = '${param.value}';
        }
        final transferUri = Uri.parse(url);
        add('transfer.request=${transferUri.host}');
        http.Response? transferResponse;
        for (var attempt = 1; attempt <= 5; attempt++) {
          transferResponse = await _postMultipart(transferUri, fields,
              headers: {'User-Agent': chromeAndroidUserAgent});
          add('transfer.status.${transferUri.host}=${transferResponse.statusCode}');
          final cookies =
              _splitSetCookieHeader(transferResponse.headers['set-cookie']);
          if (transferResponse.statusCode < 400 && cookies.isNotEmpty) {
            setCookieRecords.addAll(
                cookies.map((cookie) => MapEntry(transferUri.host, cookie)));
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      add('cookieRecords=${setCookieRecords.length}');
      final steamLoginSecureRecord = setCookieRecords.firstWhere(
        (entry) =>
            entry.key == 'steamcommunity.com' &&
            _cookieName(entry.value) == 'steamLoginSecure',
        orElse: () => setCookieRecords.firstWhere(
          (entry) => _cookieName(entry.value) == 'steamLoginSecure',
          orElse: () => const MapEntry('', ''),
        ),
      );
      final steamLoginSecureCookie = steamLoginSecureRecord.value;
      if (steamLoginSecureCookie.isEmpty) {
        final result = SteamCookieRefreshResult(
            success: false, status: 'steamLoginSecure-missing', log: log.join('\n'));
        await _saveLastRefreshResult(result);
        return result;
      }
      final steamLoginSecure = _cookieValue(steamLoginSecureCookie);
      if (steamLoginSecure.isEmpty) {
        final result = SteamCookieRefreshResult(
            success: false, status: 'steamLoginSecure-empty', log: log.join('\n'));
        await _saveLastRefreshResult(result);
        return result;
      }

      final domains = setCookieRecords
          .map((entry) => _cookieDomain(entry.value, Uri.parse('https://${entry.key}')))
          .where((domain) => domain.isNotEmpty && domain != 'login.steampowered.com')
          .toSet();
      domains.add('steamcommunity.com');
      add('cookieDomains=${domains.join(',')}');
      for (final record in setCookieRecords) {
        final domain = _cookieDomain(record.value, Uri.parse('https://${record.key}'));
        if (domain.isEmpty || domain == 'login.steampowered.com') continue;
        final name = _cookieName(record.value);
        final value = _cookieValue(record.value);
        if (name.isEmpty || value.isEmpty) continue;
        await _cookieManager.setCookie(
          url: WebUri('https://$domain'),
          name: name,
          value: value,
          domain: domain,
          path: '/',
          isSecure: true,
          isHttpOnly: name == 'steamLoginSecure',
        );
      }
      for (final domain in domains) {
        final url = WebUri('https://$domain');
        await _cookieManager.setCookie(
          url: url,
          name: 'sessionid',
          value: sessionId,
          domain: domain,
          path: '/',
          isSecure: true,
        );
      }
      final prefs = await _prefs;
      await prefs.setBool(_sessionSavedKey, true);
      await prefs.setString(
          _sessionCookieHeaderKey,
          _normalizeManualCookieHeader(
            sessionId: sessionId,
            steamLoginSecure: steamLoginSecure,
            extraAuth: '',
            steamId: steamId,
          ));
      await prefs.setInt(
          _sessionSavedAtKey, DateTime.now().millisecondsSinceEpoch);
      add('result=generated-cookies');
      final valid = await _retryKeepAlive(log);
      add(valid ? 'recheck=valid' : 'recheck=failed');
      final result = SteamCookieRefreshResult(
          success: valid,
          status: valid ? 'ok' : 'generated-but-invalid',
          log: log.join('\n'));
      await _saveLastRefreshResult(result);
      if (!valid) await markSessionExpired();
      return result;
    } catch (error) {
      add('exception=${error.runtimeType}');
      final result = SteamCookieRefreshResult(
          success: false, status: 'exception', log: log.join('\n'));
      await _saveLastRefreshResult(result);
      return result;
    }
  }

  List<MapEntry<String, String>> _refreshTokenCandidates(String value) {
    final candidates = <MapEntry<String, String>>[];
    final deferred = <MapEntry<String, String>>[];
    void add(List<MapEntry<String, String>> target, String label, String token) {
      final trimmed = token.trim();
      if (trimmed.isEmpty) return;
      if (candidates.any((entry) => entry.value == trimmed) ||
          deferred.any((entry) => entry.value == trimmed)) {
        return;
      }
      target.add(MapEntry(label, trimmed));
    }

    final decoded = Uri.decodeComponent(value);
    for (final token in [value, decoded]) {
      if (token.contains('%7C%7C')) {
        add(candidates, 'encoded-pipe-suffix', token.split('%7C%7C').last);
      }
      if (token.contains('||')) {
        add(candidates, 'pipe-suffix', token.split('||').last);
      }
    }
    add(deferred, 'raw', value);
    add(deferred, 'decoded', decoded);
    for (final token in [value, decoded]) {
      if (token.contains('|')) add(deferred, 'single-pipe-suffix', token.split('|').last);
      if (token.contains('%7C')) {
        add(deferred, 'encoded-single-pipe-suffix', token.split('%7C').last);
      }
    }
    return [...candidates, ...deferred];
  }

  Future<bool> _retryKeepAlive(List<String> log) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (attempt > 1) {
        await Future<void>.delayed(Duration(milliseconds: attempt == 2 ? 700 : 1200));
      }
      final valid = await keepAliveSession();
      log.add('${DateTime.now().toIso8601String()}  recheck.$attempt=${valid ? 'valid' : 'failed'}');
      if (valid) return true;
    }
    return false;
  }

  String _tokenShape(String token) {
    final parts = token.split('.').length;
    final looksJwt = parts == 3;
    return 'length=${token.length} parts=$parts looksJwt=$looksJwt';
  }

  Future<bool> keepAliveSession() async {
    final steamId = await loadSteamId();
    final cookieHeader = await loadCookieHeader();
    if (steamId.isEmpty || cookieHeader.isEmpty) return false;
    try {
      final response = await http.get(
        await loadProfileUri(),
        headers: {
          'Cookie': cookieHeader,
          'User-Agent': chromeAndroidUserAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 7));
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          !_looksLikeSteamLoginPage(response.body) &&
          (response.body.toLowerCase().contains('profile_header') ||
              response.body.toLowerCase().contains('profile_header_centered_persona') ||
              response.body.toLowerCase().contains('actual_persona_name') ||
              response.body.toLowerCase().contains('recent activity') ||
              response.body.toLowerCase().contains('games'))) {
        final prefs = await _prefs;
        await prefs.setBool(_sessionSavedKey, true);
        await prefs.setInt(
            _sessionSavedAtKey, DateTime.now().millisecondsSinceEpoch);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> refreshSessionIfStale() async {
    if (!await hasSavedSession()) return;
    final prefs = await _prefs;
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastAutoRefresh = prefs.getInt(_sessionAutoRefreshAtKey) ?? 0;
    if (lastAutoRefresh > 0 &&
        now - lastAutoRefresh < const Duration(hours: 20).inMilliseconds) {
      return;
    }
    await prefs.setInt(_sessionAutoRefreshAtKey, now);
    final keptAlive = await keepAliveSession();
    if (keptAlive) return;
    final tokenRefresh = await refreshWebCookiesFromSteamRefresh();
    if (tokenRefresh.success) return;
    await testHeadlessRefresh();
    if (!await keepAliveSession()) {
      await markSessionExpired();
    }
  }

  static const chromeAndroidUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  Future<Map<String, String>> getAuthenticatedHeaders(
      {bool refresh = true}) async {
    if (refresh) await refreshSessionIfStale();
    if (!await hasSavedSession()) return const {};
    final savedCookieHeader = await loadCookieHeader();
    if (savedCookieHeader.isEmpty) return const {};
    return {
      'Cookie': savedCookieHeader,
      'User-Agent': chromeAndroidUserAgent,
    };
  }

  Future<String> saveCoreWebViewAuthCookies({
    String steamId = '',
    String profileUrl = '',
    bool updateSavedAt = true,
  }) async {
    final log = <String>[];
    void add(String message) =>
        log.add('${DateTime.now().toIso8601String()}  $message');

    add('webViewCookieCapture=start');
    final cookies = await _cookieManager.getCookies(url: communityUri);
    String steamLoginSecure = '';
    String sessionId = '';
    for (final cookie in cookies) {
      if (cookie.name == 'steamLoginSecure') steamLoginSecure = cookie.value;
      if (cookie.name == 'sessionid') sessionId = cookie.value;
    }
    add('sessionid=${sessionId.isNotEmpty ? _maskSecret(sessionId) : 'empty'}');
    add('steamLoginSecure=${steamLoginSecure.isNotEmpty ? _maskSecret(steamLoginSecure) : 'empty'}');
    await _saveRefreshCookieIfAvailable();
    add('steamRefresh=${(await loadRefreshCookieValue()).isNotEmpty ? 'present' : 'empty'}');
    if (sessionId.isEmpty || steamLoginSecure.isEmpty) {
      add('result=missing-core-cookies');
      return log.join('\n');
    }
    final resolvedSteamId = steamId.trim().isNotEmpty
        ? steamId.trim()
        : _inferSteamIdFromAuthValue(steamLoginSecure);
    final prefs = await _prefs;
    await prefs.setBool(_sessionSavedKey, true);
    await prefs.setString(
        _sessionCookieHeaderKey,
        _normalizeManualCookieHeader(
          sessionId: sessionId,
          steamLoginSecure: steamLoginSecure,
          extraAuth: '',
          steamId: resolvedSteamId,
        ));
    if (updateSavedAt) {
      await prefs.setInt(
          _sessionSavedAtKey, DateTime.now().millisecondsSinceEpoch);
    }
    if (resolvedSteamId.isNotEmpty) {
      await prefs.setString(_sessionSteamIdKey, resolvedSteamId);
    }
    final profilePath = _profilePathFromUrl(profileUrl);
    if (profilePath.isNotEmpty) {
      await prefs.setString(_sessionProfilePathKey, profilePath);
      add('profilePath=$profilePath');
    }
    add('saveCoreCookies=ok');
    add('steamId=${resolvedSteamId.isNotEmpty}');
    final valid = await keepAliveSession();
    add(valid ? 'testPrivateSession=ok' : 'testPrivateSession=failed');
    add(valid ? 'result=saved-valid' : 'result=saved-but-not-verified');
    return log.join('\n');
  }

  Future<bool> saveSession(
      {String steamId = '', bool updateSavedAt = true}) async {
    final cookieHeader = await _buildCurrentAuthCookieHeader();
    await _saveRefreshCookieIfAvailable();
    final prefs = await _prefs;
    if (cookieHeader.isEmpty) {
      await prefs.setBool(_sessionSavedKey, false);
      await prefs.remove(_sessionCookieHeaderKey);
      return false;
    }
    await prefs.setBool(_sessionSavedKey, true);
    if (updateSavedAt) {
      await prefs.setInt(
          _sessionSavedAtKey, DateTime.now().millisecondsSinceEpoch);
    }
    await prefs.setString(_sessionCookieHeaderKey, cookieHeader);
    final resolvedSteamId = steamId.trim().isNotEmpty
        ? steamId.trim()
        : await inferSteamIdFromCookies();
    if (resolvedSteamId.isNotEmpty) {
      await prefs.setString(_sessionSteamIdKey, resolvedSteamId);
    }
    return true;
  }

  Future<void> markSessionExpired() async {
    final prefs = await _prefs;
    await prefs.setBool(_sessionSavedKey, false);
    await prefs.remove(_sessionCookieHeaderKey);
  }

  String _maskSecret(String value) {
    if (value.length <= 8) return '***';
    return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
  }

  String _cookiePair(String name, String value) => '$name=$value';

  String _normalizeManualCookieHeader({
    required String sessionId,
    required String steamLoginSecure,
    required String extraAuth,
    required String steamId,
  }) {
    final parts = <String>[];
    void addPair(String name, String value) {
      final cleanName = name.trim();
      final cleanValue = value.trim();
      if (cleanName.isEmpty || cleanValue.isEmpty) return;
      parts.add(_cookiePair(cleanName, cleanValue));
    }

    addPair('sessionid', sessionId);
    addPair('steamLoginSecure', steamLoginSecure);
    final extra = extraAuth.trim();
    if (extra.isNotEmpty) {
      if (extra.contains('=')) {
        for (final rawPart in extra.split(';')) {
          final index = rawPart.indexOf('=');
          if (index <= 0) continue;
          addPair(rawPart.substring(0, index), rawPart.substring(index + 1));
        }
      } else if (steamId.trim().isNotEmpty) {
        addPair('steamMachineAuth${steamId.trim()}', extra);
      } else {
        addPair('steamParental', extra);
      }
    }
    return parts.join('; ');
  }

  String _inferSteamIdFromAuthValue(String value) {
    final match = RegExp(r'^(\d{17})%7C|^(\d{17})\|').firstMatch(value);
    return match?.group(1) ?? match?.group(2) ?? '';
  }

  Future<String> saveManualAuthenticationData({
    required String sessionId,
    required String steamLoginSecure,
    required String extraAuth,
    required String steamId,
  }) async {
    final log = <String>[];
    void add(String message) =>
        log.add('${DateTime.now().toIso8601String()}  $message');

    add('manualAuth=start');
    final cleanSessionId = sessionId.trim();
    final cleanSteamLoginSecure = steamLoginSecure.trim();
    final cleanSteamId = steamId.trim().isNotEmpty
        ? steamId.trim()
        : _inferSteamIdFromAuthValue(cleanSteamLoginSecure);
    add('sessionid=${cleanSessionId.isNotEmpty ? _maskSecret(cleanSessionId) : 'empty'}');
    add('steamLoginSecure=${cleanSteamLoginSecure.isNotEmpty ? _maskSecret(cleanSteamLoginSecure) : 'empty'}');
    add('extraAuth=${extraAuth.trim().isNotEmpty ? 'present' : 'empty'}');
    if (cleanSessionId.isEmpty || cleanSteamLoginSecure.isEmpty) {
      add('result=missing-required-fields');
      return log.join('\n');
    }
    final cookieHeader = _normalizeManualCookieHeader(
      sessionId: cleanSessionId,
      steamLoginSecure: cleanSteamLoginSecure,
      extraAuth: extraAuth,
      steamId: cleanSteamId,
    );
    final prefs = await _prefs;
    await prefs.setString(_sessionCookieHeaderKey, cookieHeader);
    await prefs.setBool(_sessionSavedKey, true);
    await prefs.setInt(
        _sessionSavedAtKey, DateTime.now().millisecondsSinceEpoch);
    if (cleanSteamId.isNotEmpty) {
      await prefs.setString(_sessionSteamIdKey, cleanSteamId);
    }
    add('saveCookieHeader=ok');
    final valid = await keepAliveSession();
    add(valid ? 'testPrivateSession=ok' : 'testPrivateSession=failed');
    add(valid ? 'result=saved-valid' : 'result=saved-but-not-verified');
    return log.join('\n');
  }

  Future<String> testSavedAuthenticationData() async {
    final log = <String>[];
    void add(String message) =>
        log.add('${DateTime.now().toIso8601String()}  $message');
    add('manualAuthTest=start');
    add('hasCookieHeader=${(await loadCookieHeader()).isNotEmpty}');
    add('hasSteamId=${(await loadSteamId()).isNotEmpty}');
    final valid = await keepAliveSession();
    add(valid ? 'testPrivateSession=ok' : 'testPrivateSession=failed');
    return log.join('\n');
  }

  Future<String> testHeadlessRefresh() async {
    final log = <String>[];
    void add(String message) =>
        log.add('${DateTime.now().toIso8601String()}  $message');

    add('start');
    add('beforeAuthHeader=${(await _buildCurrentAuthCookieHeader()).isNotEmpty}');
    add('beforeSteamId=${(await inferSteamIdFromCookies()).isNotEmpty}');

    final prefs = await _prefs;
    final savedAt = prefs.getInt(_sessionSavedAtKey) ?? 0;
    final lastAutoRefresh = prefs.getInt(_sessionAutoRefreshAtKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    add('savedAgeHours=${savedAt <= 0 ? 'unknown' : ((now - savedAt) / 3600000).toStringAsFixed(1)}');
    add('lastAutoRefreshAgeHours=${lastAutoRefresh <= 0 ? 'never' : ((now - lastAutoRefresh) / 3600000).toStringAsFixed(1)}');

    await _restoreSteamRefreshCookie();
    add('restoreSteamRefresh=${(await loadRefreshCookieValue()).isNotEmpty}');

    final completer = Completer<void>();
    late final HeadlessInAppWebView headlessWebView;
    Timer? timeoutTimer;

    Future<void> finish(String reason, {String profileUrl = ''}) async {
      if (completer.isCompleted) return;
      add('finish=$reason');
      timeoutTimer?.cancel();
      try {
        if (reason == 'profile-url') {
          final saved = await saveSession(updateSavedAt: true);
          await saveProfilePathFromUrl(profileUrl);
          add(saved ? 'saveSession=ok' : 'saveSession=empty-auth');
        } else if (reason == 'login-url' || reason == 'expired-page') {
          add('renewManually=$reason');
        } else {
          add('saveSession=skipped');
        }
      } catch (error) {
        add('saveSession=error:${error.runtimeType}');
      }
      try {
        await headlessWebView.dispose();
        add('dispose=ok');
      } catch (error) {
        add('dispose=error:${error.runtimeType}');
      }
      completer.complete();
    }

    final refreshUri = await loadProfileUri();
    add('refreshRequest=$refreshUri');

    headlessWebView = HeadlessInAppWebView(
      initialUrlRequest:
          URLRequest(url: WebUri(refreshUri.toString())),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        thirdPartyCookiesEnabled: true,
        sharedCookiesEnabled: true,
        transparentBackground: true,
        userAgent: chromeAndroidUserAgent,
      ),
      onWebViewCreated: (_) => add('created'),
      onLoadStart: (_, url) => add('loadStart=${url?.toString() ?? ''}'),
      onLoadStop: (_, url) async {
        add('loadStop=${url?.toString() ?? ''}');
        final rawUrl = url?.toString().toLowerCase() ?? '';
        if (rawUrl.contains('/login/')) {
          add('skipCookieSync=login-url');
          await finish('login-url');
          return;
        }
        if (rawUrl.contains('/profiles/') || rawUrl.contains('/id/')) {
          final html = await headlessWebView.webViewController?.getHtml() ?? '';
          final lowerHtml = html.toLowerCase();
          final headlessLooksLogin = _looksLikeSteamLoginPage(html);
          final headlessHasProfileMarkers = lowerHtml.contains('profile_header') ||
              lowerHtml.contains('profile_header_centered_persona') ||
              lowerHtml.contains('actual_persona_name') ||
              lowerHtml.contains('recent activity') ||
              lowerHtml.contains('games');
          add('headlessBodyLength=${html.length}');
          add('headlessLooksLogin=$headlessLooksLogin');
          add('headlessHasProfileMarkers=$headlessHasProfileMarkers');
          if (headlessLooksLogin || !headlessHasProfileMarkers) {
            add('skipCookieSync=expired-page');
            await finish('expired-page');
            return;
          }
          await syncCookiesFromWebView();
          add('duringAuthHeader=${(await _buildCurrentAuthCookieHeader()).isNotEmpty}');
          add('duringSteamId=${(await inferSteamIdFromCookies()).isNotEmpty}');
          await finish('profile-url', profileUrl: url?.toString() ?? '');
        }
      },
      onReceivedError: (_, request, error) =>
          add('error=${request.url} ${error.type}'),
      onConsoleMessage: (_, message) => add('console=${message.messageLevel}'),
    );

    try {
      await headlessWebView.run();
      add('run=ok');
      timeoutTimer = Timer(const Duration(seconds: 12), () {
        finish('timeout');
      });
      await completer.future;
    } catch (error) {
      add('run=error:${error.runtimeType}');
    } finally {
      timeoutTimer?.cancel();
    }

    add('afterAuthHeader=${(await _buildCurrentAuthCookieHeader()).isNotEmpty}');
    add('afterSteamId=${(await inferSteamIdFromCookies()).isNotEmpty}');
    return log.join('\n');
  }

  Future<void> clearSession() async {
    await _cookieManager.deleteAllCookies();
    final prefs = await _prefs;
    await prefs.remove(_sessionSavedKey);
    await prefs.remove(_sessionSteamIdKey);
    await prefs.remove(_sessionCookieHeaderKey);
    await prefs.remove(_sessionRefreshCookieKey);
  }
}
