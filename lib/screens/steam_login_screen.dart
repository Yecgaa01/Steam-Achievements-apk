import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/steam_session_service.dart';

class SteamLoginResult {
  final String steamId64;

  const SteamLoginResult({this.steamId64 = ''});
}

class SteamLoginScreen extends StatefulWidget {
  const SteamLoginScreen({super.key});

  @override
  State<SteamLoginScreen> createState() => _SteamLoginScreenState();
}

class _SteamLoginScreenState extends State<SteamLoginScreen> {
  final _sessionService = SteamSessionService();
  bool _loading = true;
  bool _saving = false;

  Future<void> _maybeFinishLogin(WebUri? url) async {
    if (_saving || url == null) return;
    final rawUrl = url.toString();
    final path = url.path.toLowerCase();
    final looksLoggedIn = path.startsWith('/profiles/') ||
        path.startsWith('/id/') ||
        path.startsWith('/my/') ||
        rawUrl.contains('steamcommunity.com/my');
    if (!looksLoggedIn) return;
    _saving = true;
    final steamId =
        RegExp(r'/profiles/(\d{17})').firstMatch(path)?.group(1) ?? '';
    final log = await _sessionService.saveCoreWebViewAuthCookies(
      steamId: steamId,
      profileUrl: rawUrl,
    );
    final saved = log.contains('saveCoreCookies=ok');
    if (!mounted) return;
    if (saved) {
      final resolvedSteamId =
          steamId.isNotEmpty ? steamId : await _sessionService.loadSteamId();
      if (!mounted) return;
      Navigator.of(context).pop(SteamLoginResult(steamId64: resolvedSteamId));
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Steam session not found. Finish the Steam login first.'),
        ),
      );
    }
  }

  Future<void> _finishManually() async {
    if (_saving) return;
    setState(() => _saving = true);
    final log = await _sessionService.saveCoreWebViewAuthCookies();
    final saved = log.contains('saveCoreCookies=ok');
    if (!mounted) return;
    if (saved) {
      final resolvedSteamId = await _sessionService.loadSteamId();
      if (!mounted) return;
      Navigator.of(context).pop(SteamLoginResult(steamId64: resolvedSteamId));
    } else {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Steam session not found. Finish the Steam login first.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Steam login'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _finishManually,
            child: const Text('Done'),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: SteamSessionService.loginUri),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              thirdPartyCookiesEnabled: true,
              sharedCookiesEnabled: true,
              userAgent: SteamSessionService.chromeAndroidUserAgent,
            ),
            onLoadStart: (_, __) => setState(() => _loading = true),
            onLoadStop: (_, url) async {
              if (mounted) setState(() => _loading = false);
              await _maybeFinishLogin(url);
            },
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_saving) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
