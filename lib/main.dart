import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_text.dart';
import 'models/steam_models.dart';
import 'screens/games_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/steam_login_screen.dart';
import 'services/cache_store.dart';
import 'services/foreground_sync.dart';
import 'services/update_service.dart';

void main() {
  runApp(const SteamTrophiesApp());
}

class SteamTrophiesApp extends StatefulWidget {
  const SteamTrophiesApp({super.key});

  @override
  State<SteamTrophiesApp> createState() => _SteamTrophiesAppState();
}

class _SteamTrophiesAppState extends State<SteamTrophiesApp> {
  static const _legacyAppChannel =
      MethodChannel('steam_achievements/legacy_app');
  final _cache = CacheStore();
  final _updateService = UpdateService();
  final _foregroundSync = ForegroundSync();
  final _navigatorKey = GlobalKey<NavigatorState>();
  SteamConfig? _config;
  int _syncToken = 0;
  bool _legacyAppPromptShown = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await _cache.loadConfig();
    if (!mounted) return;
    setState(() => _config = config);
    _checkForUpdatesOnLaunch(config);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showLegacyAppPromptIfNeeded(config);
    });
  }

  Future<void> _showLegacyAppPromptIfNeeded(SteamConfig config) async {
    if (_legacyAppPromptShown || !mounted) return;
    _legacyAppPromptShown = true;
    final legacyPackage = await _findInstalledLegacyPackage();
    if (legacyPackage == null || !mounted) return;
    final text = AppText(config.languageCode == 'en'
        ? AppLanguage.english
        : AppLanguage.portuguese);
    final dialogContext = _navigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) return;
    final uninstall = await showDialog<bool>(
      context: dialogContext,
      builder: (context) => AlertDialog(
        title: Text(text.oldAppDetectedTitle),
        content: Text(text.oldAppDetectedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(text.notNow),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(text.uninstallOldApp),
          ),
        ],
      ),
    );
    if (uninstall == true) {
      await _legacyAppChannel.invokeMethod('uninstallPackage', legacyPackage);
    }
  }

  Future<String?> _findInstalledLegacyPackage() async {
    const legacyPackages = [
      'com.example.steam_achievements_apk',
      'com.example_steam_achievements_apk',
    ];
    for (final packageName in legacyPackages) {
      final installed = await _legacyAppChannel.invokeMethod<bool>(
            'isPackageInstalled',
            packageName,
          ) ??
          false;
      if (installed) return packageName;
    }
    return null;
  }

  Future<void> _checkForUpdatesOnLaunch(SteamConfig config) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastCheck = await _cache.loadLastUpdateCheckMillis();
    if (now - lastCheck < const Duration(hours: 12).inMilliseconds) return;
    await _cache.saveLastUpdateCheckMillis(now);
    try {
      final update = await _updateService.checkForUpdate();
      if (update == null || !update.available) return;
      var notificationsAllowed =
          await _foregroundSync.areNotificationsAllowed();
      if (!notificationsAllowed) {
        notificationsAllowed = await _foregroundSync.requestNotifications();
      }
      if (!notificationsAllowed) return;
      final text = AppText(config.languageCode == 'en'
          ? AppLanguage.english
          : AppLanguage.portuguese);
      await _updateService.showUpdateNotification(
        update,
        title: text.updateNotificationTitle,
        text: text.updateNotificationBody(update.version),
      );
    } catch (_) {
      // Automatic update checks stay silent on network/API failures.
    }
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
          onSyncRequested: (newConfig) async {
            setState(() {
              _config = newConfig;
              _syncToken++;
            });
          },
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

  ThemeData _oledTheme() {
    const background = Color(0xFF000000);
    const surface = Color(0xFF08090B);
    const surfaceVariant = Color(0xFF0C0D10);
    const outline = Color(0xFF1E293B);
    const accent = Color(0xFF38BDF8);
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: Color(0xFF7DD3FC),
        surface: surface,
        surfaceContainerHighest: surfaceVariant,
        onSurface: Color(0xFFF3F4F6),
        onSurfaceVariant: Color(0xFF8B96A8),
        outline: outline,
      ),
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: surface,
      dialogTheme: const DialogThemeData(backgroundColor: surface),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: surface),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: Color(0xFFF3F4F6),
        centerTitle: false,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: accent),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: surface,
        selectedColor: Color(0xFF082F49),
        labelStyle: TextStyle(color: Color(0xFFF3F4F6)),
        side: BorderSide(color: outline),
      ),
      useMaterial3: true,
    );
  }

  ThemeMode _themeMode(SteamConfig config) {
    if (config.themeMode == 'light') return ThemeMode.light;
    if (config.themeMode == 'dark' || config.themeMode == 'oled') {
      return ThemeMode.dark;
    }
    return ThemeMode.system;
  }

  Future<void> _renewSteamSession(BuildContext context) async {
    final result = await Navigator.of(context).push<SteamLoginResult>(
      MaterialPageRoute(builder: (_) => const SteamLoginScreen()),
    );
    if (result == null) return;
    final current = _config;
    if (current == null) return;
    final steamId = result.steamId64.trim();
    final updated = current.copyWith(
      steamId64: steamId.isNotEmpty ? steamId : current.steamId64,
      loginMode: 'steamSession',
    );
    await _cache.saveConfig(updated);
    if (mounted) setState(() => _config = updated);
  }

  @override
  Widget build(BuildContext context) {
    final activeConfig =
        _config ?? const SteamConfig(steamId64: '', apiKey: '');
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Steam Achievements',
      theme: _theme(Brightness.light),
      darkTheme: activeConfig.themeMode == 'oled'
          ? _oledTheme()
          : _theme(Brightness.dark),
      themeMode: _themeMode(activeConfig),
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
              onRenewSteamSession: () => _renewSteamSession(context),
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
