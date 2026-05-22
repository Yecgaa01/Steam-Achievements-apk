import 'package:flutter/material.dart';

import 'models/steam_models.dart';
import 'screens/games_screen.dart';
import 'screens/settings_screen.dart';
import 'services/cache_store.dart';

void main() {
  runApp(const SteamTrophiesApp());
}

class SteamTrophiesApp extends StatefulWidget {
  const SteamTrophiesApp({super.key});

  @override
  State<SteamTrophiesApp> createState() => _SteamTrophiesAppState();
}

class _SteamTrophiesAppState extends State<SteamTrophiesApp> {
  final _cache = CacheStore();
  SteamConfig? _config;
  int _syncToken = 0;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await _cache.loadConfig();
    setState(() => _config = config);
  }

  Future<String?> _openSettings(BuildContext context) async {
    final config = _config ?? const SteamConfig(steamId64: '', apiKey: '');
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initialConfig: config,
          onSaved: (newConfig) {
            final oldConfig = _config;
            final profileChanged = oldConfig?.normalizedSteamId64 !=
                    newConfig.normalizedSteamId64 ||
                oldConfig?.normalizedApiKey != newConfig.normalizedApiKey;
            setState(() {
              _config = newConfig;
              if (profileChanged) _syncToken++;
            });
          },
          onRestoreHiddenGames: () async {
            await _cache.saveHiddenGameAppIds({});
            setState(() => _syncToken++);
          },
          onSyncRequested: (newConfig) async => setState(() {
            _config = newConfig;
            _syncToken++;
          }),
        ),
      ),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF38BDF8), brightness: brightness),
      scaffoldBackgroundColor:
          dark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBarTheme: AppBarTheme(
          backgroundColor: dark ? const Color(0xFF020617) : Colors.white,
          foregroundColor: dark ? Colors.white : const Color(0xFF0F172A),
          centerTitle: false),
      chipTheme: ChipThemeData(
          backgroundColor:
              dark ? const Color(0xFF111827) : const Color(0xFFE2E8F0),
          selectedColor:
              dark ? const Color(0xFF075985) : const Color(0xFFBAE6FD),
          labelStyle:
              TextStyle(color: dark ? Colors.white : const Color(0xFF0F172A))),
      useMaterial3: true,
    );
  }

  ThemeMode _themeMode(SteamConfig config) {
    if (config.themeMode == 'light') return ThemeMode.light;
    if (config.themeMode == 'dark') return ThemeMode.dark;
    return ThemeMode.system;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Steam Achievements',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode:
          _themeMode(_config ?? const SteamConfig(steamId64: '', apiKey: '')),
      home: Builder(
        builder: (context) {
          final config = _config;
          if (config == null) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          return GamesScreen(
              key: ValueKey('${config.normalizedSteamId64}-$_syncToken'),
              config: config,
              onOpenSettings: () async {
                final action = await _openSettings(context);
                if (action == 'add_manual_game') return 'add_manual_game';
                return null;
              });
        },
      ),
    );
  }
}
