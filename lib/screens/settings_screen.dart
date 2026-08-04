import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_text.dart';
import '../models/steam_models.dart';
import '../services/cache_store.dart';
import '../services/foreground_sync.dart';
import '../services/update_service.dart';
import '../services/steam_session_service.dart';
import 'steam_login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final SteamConfig initialConfig;
  final ValueChanged<SteamConfig> onSaved;
  final Future<void> Function(SteamConfig config)? onSyncRequested;
  final Future<void> Function()? onRestoreHiddenGames;
  final VoidCallback? onAddManualGame;

  const SettingsScreen({
    super.key,
    required this.initialConfig,
    required this.onSaved,
    this.onSyncRequested,
    this.onRestoreHiddenGames,
    this.onAddManualGame,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _updateService = UpdateService();
  final _steamSessionService = SteamSessionService();
  final _imagePicker = ImagePicker();
  late final TextEditingController _steamIdController;
  late final TextEditingController _apiKeyController;
  late String _loginMode;
  bool _hasSteamSession = false;
  late bool _showAverageCompletion;
  late bool _hideSoftware;
  late bool _hideZeroPercentGames;
  late bool _separateDlcAchievements;
  late String _themeMode;
  late bool _showProgressTiers;
  late bool _showObtainabilityBadges;
  late bool _showRecentAchievementsStrip;
  late bool _goldPerfectGames;
  late String _profileBackgroundPath;
  late String _profileBackgroundFit;
  late String _profileBackgroundAlignment;
  late String _languageCode;
  late bool _showApiKey;
  PackageInfo? _packageInfo;
  UpdateInfo? _updateInfo;
  bool _saving = false;
  bool _checkingUpdate = false;
  bool _downloadingUpdate = false;

  AppText get t => AppText(
      _languageCode == 'en' ? AppLanguage.english : AppLanguage.portuguese);

  @override
  void initState() {
    super.initState();
    _loginMode = widget.initialConfig.loginMode;
    _loadSteamSessionState();
    _steamIdController =
        TextEditingController(text: widget.initialConfig.steamId64);
    _apiKeyController =
        TextEditingController(text: widget.initialConfig.apiKey);
    _showAverageCompletion = widget.initialConfig.showAverageCompletion;
    _hideSoftware = widget.initialConfig.hideSoftware;
    _hideZeroPercentGames = widget.initialConfig.hideZeroPercentGames;
    _separateDlcAchievements = widget.initialConfig.separateDlcAchievements;
    _themeMode = widget.initialConfig.themeMode;
    _showProgressTiers = widget.initialConfig.showProgressTiers;
    _showObtainabilityBadges = widget.initialConfig.showObtainabilityBadges;
    _showRecentAchievementsStrip =
        widget.initialConfig.showRecentAchievementsStrip;
    _goldPerfectGames = widget.initialConfig.goldPerfectGames;
    _profileBackgroundPath = widget.initialConfig.profileBackgroundPath;
    _profileBackgroundFit = widget.initialConfig.profileBackgroundFit;
    _profileBackgroundAlignment =
        widget.initialConfig.profileBackgroundAlignment;
    _languageCode = widget.initialConfig.languageCode;
    _showApiKey = false;
    _loadPackageInfo();
  }

  @override
  void dispose() {
    _steamIdController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  SteamConfig _currentConfig() {
    return SteamConfig(
      loginMode: _loginMode,
      steamId64: _steamIdController.text,
      apiKey: _apiKeyController.text,
      languageCode: _languageCode,
      showAverageCompletion: _showAverageCompletion,
      hideSoftware: _hideSoftware,
      hideZeroPercentGames: _hideZeroPercentGames,
      separateDlcAchievements: _separateDlcAchievements,
      themeMode: _themeMode,
      showProgressTiers: _showProgressTiers,
      showObtainabilityBadges: _showObtainabilityBadges,
      showRecentAchievementsStrip: _showRecentAchievementsStrip,
      goldPerfectGames: _goldPerfectGames,
      profileBackgroundPath: _profileBackgroundPath,
      profileBackgroundFit: _profileBackgroundFit,
      profileBackgroundAlignment: _profileBackgroundAlignment,
    );
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _packageInfo = info);
  }

  Future<void> _openHelpLink(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _confirmRestoreHiddenGames() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.restoreHiddenGames),
        content: Text(t.restoreHiddenGamesConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t.cancel)),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(t.restore)),
        ],
      ),
    );
    if (confirmed == true) await widget.onRestoreHiddenGames?.call();
  }

  Future<void> _startForegroundSyncWithPermission(SteamConfig config,
      {bool refreshUi = true}) async {
    final foregroundSync = ForegroundSync();
    var notificationsAllowed = await foregroundSync.areNotificationsAllowed();
    if (!notificationsAllowed) {
      notificationsAllowed = await foregroundSync.requestNotifications();
    }
    await foregroundSync.start();
    if (!mounted) return;
    if (!notificationsAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t.notificationPermissionDenied)));
    }
    if (refreshUi) {
      await widget.onSyncRequested?.call(config);
    }
  }

  Future<void> _syncNow() async {
    final config = _currentConfig();
    await CacheStore().saveConfig(config);
    widget.onSaved(config);
    await widget.onSyncRequested?.call(config);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _loadSteamSessionState() async {
    final initiallySavedSession = await _steamSessionService.hasSavedSession();
    if (initiallySavedSession) {
      await _steamSessionService.checkSessionWithDetails();
    }
    final hasSession = await _steamSessionService.hasSavedSession();
    final steamId = await _steamSessionService.loadSteamId();
    if (!mounted) return;
    setState(() {
      _hasSteamSession = hasSession;
      if (steamId.isNotEmpty && _steamIdController.text.trim().isEmpty) {
        _steamIdController.text = steamId;
      }
    });
  }

  Future<void> _openSteamLogin() async {
    final result = await Navigator.of(context).push<SteamLoginResult>(
      MaterialPageRoute(builder: (_) => const SteamLoginScreen()),
    );
    if (!mounted || result == null) return;
    final savedSteamId = await _steamSessionService.loadSteamId();
    setState(() {
      _loginMode = 'steamSession';
      _hasSteamSession = true;
      final steamId =
          result.steamId64.isNotEmpty ? result.steamId64 : savedSteamId;
      if (steamId.isNotEmpty) _steamIdController.text = steamId;
    });
    await _loadSteamSessionState();
    await _saveImmediately();
  }

  Future<void> _clearSteamSession() async {
    await _steamSessionService.clearSession();
    if (!mounted) return;
    setState(() {
      _hasSteamSession = false;
      if (_loginMode == 'steamSession') _loginMode = 'manual';
    });
  }

  Future<String?> _editProfileBackgroundCrop(String imagePath) async {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ProfileBackgroundCropScreen(
          imagePath: imagePath,
          isPt: t.isPt,
        ),
      ),
    );
  }

  Future<void> _pickProfileBackground() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final croppedPath = await _editProfileBackgroundCrop(image.path);
    if (croppedPath == null || croppedPath.isEmpty) return;
    final previousPath = _profileBackgroundPath.trim();
    if (previousPath.isNotEmpty && previousPath != croppedPath) {
      final previousFile = File(previousPath);
      if (await previousFile.exists()) await previousFile.delete();
    }
    if (!mounted) return;
    setState(() {
      _profileBackgroundPath = croppedPath;
      _profileBackgroundFit = 'cover';
      _profileBackgroundAlignment = 'center';
    });
    await _saveImmediately();
  }

  Future<void> _removeProfileBackground() async {
    final path = _profileBackgroundPath.trim();
    if (path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    if (mounted) {
      setState(() => _profileBackgroundPath = '');
      await _saveImmediately();
    }
  }

  Future<void> _saveImmediately() async {
    final config = _currentConfig();
    await CacheStore().saveConfig(config);
    widget.onSaved(config);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final config = _currentConfig();
    final firstValidConfig =
        !widget.initialConfig.isComplete && config.isComplete;
    await CacheStore().saveConfig(config);
    widget.onSaved(config);
    if (firstValidConfig) {
      await _startForegroundSyncWithPermission(config);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdate = true);
    try {
      final update = await _updateService.checkForUpdate();
      if (!mounted) return;
      setState(() => _updateInfo = update);
      final message = update == null
          ? t.updateNotConfigured
          : update.available
              ? t.updateAvailable(update.version)
              : t.noUpdatesAvailable;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.updateCheckFailed)));
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _downloadAndInstallUpdate() async {
    final update = _updateInfo;
    if (update == null) return;
    setState(() => _downloadingUpdate = true);
    try {
      final canInstall = await _updateService.canInstallUnknownApps();
      if (!canInstall) {
        await _updateService.openUnknownAppsSettings();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(t.unknownSourcesNeeded)));
        }
        return;
      }
      final path = await _updateService.downloadApk(update);
      await _updateService.installApk(path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.installUpdateFailed)));
      }
    } finally {
      if (mounted) setState(() => _downloadingUpdate = false);
    }
  }

  String _displayVersion(String version) {
    return version.endsWith('.0')
        ? version.substring(0, version.length - 2)
        : version;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.settings),
          bottom: TabBar(tabs: [
            Tab(text: t.loginTab),
            Tab(text: t.settingsTab),
            Tab(text: t.advancedTab),
            Tab(text: t.themeTab),
            Tab(text: t.aboutTab)
          ]),
        ),
        body: TabBarView(children: [
          _loginTab(),
          _settingsTab(),
          _advancedTab(),
          _themeTab(),
          _aboutTab()
        ]),
      ),
    );
  }

  Widget _loginTab() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(t.loginTab,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Text(t.loginMethod,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
                value: 'steamSession', label: Text(t.useSteamSession)),
            ButtonSegment(value: 'manual', label: Text(t.useManualLogin)),
          ],
          selected: {_loginMode},
          onSelectionChanged: (value) =>
              setState(() => _loginMode = value.first),
        ),
        const SizedBox(height: 18),
        if (_loginMode == 'steamSession')
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.login),
                    title: Text(t.steamSessionRecommended),
                    subtitle: Text(t.steamSessionHelp),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _openSteamLogin,
                        icon: const Icon(Icons.open_in_browser),
                        label: Text(t.steamSessionLogin),
                      ),
                      if (_hasSteamSession)
                        OutlinedButton.icon(
                          onPressed: _clearSteamSession,
                          icon: const Icon(Icons.logout),
                          label: Text(t.clearSteamSession),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (_loginMode == 'manual')
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.key),
                    title: Text(t.manualLogin),
                    subtitle: Text(t.manualLoginHelp),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _steamIdController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                        labelText: t.steamId64, hintText: '7656119...'),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _openHelpLink('https://steamid.io/'),
                      icon: const Icon(Icons.link, size: 16),
                      label: Text(t.steamIdHelpLink),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: !_showApiKey,
                    decoration: InputDecoration(
                      labelText: t.apiKey,
                      suffixIcon: IconButton(
                        icon: Icon(_showApiKey
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _showApiKey = !_showApiKey),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _openHelpLink(
                          'https://steamcommunity.com/dev/apikey'),
                      icon: const Icon(Icons.link, size: 16),
                      label: Text(t.apiKeyHelpLink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed:
              _saving || widget.onSyncRequested == null ? null : _syncNow,
          icon: const Icon(Icons.sync),
          label: Text(t.syncProfileNow),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: Text(t.save)),
      ],
    );
  }

  Widget _settingsTab() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(t.settingsTab,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(t.configHelp,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        SwitchListTile(
            value: _showAverageCompletion,
            onChanged: (value) =>
                setState(() => _showAverageCompletion = value),
            title: Text(t.showAverage),
            subtitle: Text(t.showAverageHelp)),
        SwitchListTile(
            value: _hideSoftware,
            onChanged: (value) => setState(() => _hideSoftware = value),
            title: Text(t.hideSoftware),
            subtitle: Text(t.hideSoftwareHelp)),
        SwitchListTile(
            value: _hideZeroPercentGames,
            onChanged: (value) => setState(() => _hideZeroPercentGames = value),
            title: Text(t.hideZeroPercentGames),
            subtitle: Text(t.hideZeroPercentGamesHelp)),
        SwitchListTile(
            value: _separateDlcAchievements,
            onChanged: (value) =>
                setState(() => _separateDlcAchievements = value),
            title: Text(t.separateDlcAchievements),
            subtitle: Text(t.separateDlcAchievementsHelp)),
        OutlinedButton.icon(
            onPressed: _confirmRestoreHiddenGames,
            icon: const Icon(Icons.visibility),
            label: Text(t.restoreHiddenGames)),
        const SizedBox(height: 12),
        Text(t.language, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'pt', label: Text(t.portuguese)),
            ButtonSegment(value: 'en', label: Text(t.english))
          ],
          selected: {_languageCode},
          onSelectionChanged: (selected) =>
              setState(() => _languageCode = selected.first),
        ),
        const SizedBox(height: 8),
        Text(t.scanNotice,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12)),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? t.saving : t.save)),
      ],
    );
  }

  Future<void> _clearCache() async {
    final config = _currentConfig();
    if (!config.isComplete) return;
    final clearMode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.clearCache),
        content:
            Text('${t.clearCacheWarning}\n\n${t.clearCacheKeepManualHelp}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t.cancel)),
          TextButton(
              onPressed: () => Navigator.of(context).pop('remove_all'),
              child: Text(t.removeManualGamesToo)),
          FilledButton(
              onPressed: () => Navigator.of(context).pop('keep_manual'),
              child: Text(t.keepManualGames)),
        ],
      ),
    );
    if (clearMode == null) return;
    await CacheStore().saveConfig(config);
    await CacheStore().clearProfileCache(config.normalizedSteamId64,
        keepManualGames: clearMode == 'keep_manual');
    widget.onSaved(config);
    if (config.normalizedApiKey.isNotEmpty) {
      await _startForegroundSyncWithPermission(config, refreshUi: false);
    } else {
      await widget.onSyncRequested?.call(config);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t.cacheCleared)));
  }

  Widget _advancedTab() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(t.advancedTab,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.addManualGame,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(t.manualGameNote,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12.5)),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).pop('add_manual_game'),
                  icon: const Icon(Icons.add),
                  label: Text(t.addManualGame),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.clearCache,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(t.clearCacheHelp,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12.5)),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _clearCache,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: Text(t.clearCache),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _themeTab() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(t.themeTab,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        Text(t.themeMode, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'system', label: Text(t.themeSystem)),
            ButtonSegment(value: 'dark', label: Text(t.themeDark)),
            ButtonSegment(value: 'oled', label: Text(t.themeOled)),
            ButtonSegment(value: 'light', label: Text(t.themeLight)),
          ],
          selected: {_themeMode},
          onSelectionChanged: (value) async {
            setState(() => _themeMode = value.first);
            await _saveImmediately();
          },
        ),
        const SizedBox(height: 18),
        SwitchListTile(
            value: _showProgressTiers,
            onChanged: (value) async {
              setState(() => _showProgressTiers = value);
              await _saveImmediately();
            },
            title: Text(t.showProgressTiers),
            subtitle: Text(t.showProgressTiersHelp)),
        SwitchListTile(
            value: _showObtainabilityBadges,
            onChanged: (value) async {
              setState(() => _showObtainabilityBadges = value);
              await _saveImmediately();
            },
            title: Text(t.showObtainabilityBadges),
            subtitle: Text(t.showObtainabilityBadgesHelp)),
        SwitchListTile(
            value: _showRecentAchievementsStrip,
            onChanged: (value) async {
              setState(() => _showRecentAchievementsStrip = value);
              await _saveImmediately();
            },
            title: Text(t.isPt
                ? 'Mostrar conquistas recentes na home'
                : 'Show recent achievements on home')),
        SwitchListTile(
            value: _goldPerfectGames,
            onChanged: (value) async {
              setState(() => _goldPerfectGames = value);
              await _saveImmediately();
            },
            title: Text(t.goldPerfectGames),
            subtitle: Text(t.goldPerfectGamesHelp)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.photo),
                  title: Text(t.profileBackground),
                  subtitle: Text(t.profileBackgroundHelp),
                ),
                if (_profileBackgroundPath.trim().isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      File(_profileBackgroundPath),
                      key: ValueKey(_profileBackgroundPath),
                      height: 96,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickProfileBackground,
                      icon: const Icon(Icons.photo_library),
                      label: Text(t.chooseProfileBackground),
                    ),
                    if (_profileBackgroundPath.trim().isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _removeProfileBackground,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(t.removeProfileBackground),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showChangelogDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.changelog),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<String>(
            future: _updateService.getLatestReleaseNotes(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(t.loadingChangelog)),
                    ],
                  ),
                );
              }
              final notes = _localizedReleaseNotes(snapshot.data?.trim() ?? '');
              if (snapshot.hasError || notes.isEmpty) {
                return Text(t.changelogUnavailable);
              }
              return SingleChildScrollView(
                child: _releaseNotesCard(notes),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.close),
          ),
        ],
      ),
    );
  }

  String _localizedReleaseNotes(String notes) {
    final preferred = _languageCode == 'en' ? 'en' : 'pt';
    final sections = <String, List<String>>{};
    String? currentLanguage;

    for (final rawLine in notes.replaceAll('\r\n', '\n').split('\n')) {
      final marker = _releaseNotesLanguageMarker(rawLine);
      if (marker != null) {
        currentLanguage = marker;
        sections.putIfAbsent(currentLanguage, () => []);
        continue;
      }
      if (currentLanguage != null) {
        sections[currentLanguage]!.add(rawLine);
      }
    }

    if (sections.isEmpty) {
      return notes
          .replaceAll(RegExp(r'^\s*<!--\s*\[/?(?:pt-br|pt|br|en)\]\s*-->\s*$',
              caseSensitive: false, multiLine: true), '')
          .trim();
    }
    return (sections[preferred] ??
            sections[preferred == 'en' ? 'pt' : 'en'] ??
            [])
        .where((line) => _releaseNotesLanguageMarker(line) == null)
        .join('\n')
        .trim();
  }

  String? _releaseNotesLanguageMarker(String line) {
    final htmlMarker = RegExp(
      r'^\s*<!--\s*\[?/?\s*(pt-br|pt|portugu[eê]s|br|en|english|ingl[eê]s)\s*\]?\s*-->\s*$',
      caseSensitive: false,
    ).firstMatch(line);
    final markdownMarker = RegExp(
      r'^\s*#{1,6}\s*\[?\s*(pt-br|pt|portugu[eê]s|br|en|english|ingl[eê]s)\s*\]?\s*$',
      caseSensitive: false,
    ).firstMatch(line);
    final value = (htmlMarker ?? markdownMarker)?.group(1)?.toLowerCase();
    if (value == null) return null;
    return value.startsWith('en') || value.startsWith('ingl') ? 'en' : 'pt';
  }

  Widget _releaseNotesCard(String notes) {
    final lines = notes
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines) _releaseNoteLine(line),
          ],
        ),
      ),
    );
  }

  Widget _releaseNoteLine(String rawLine) {
    final heading = rawLine.replaceFirst(RegExp(r'^#{1,6}\s*'), '').trim();
    if (heading != rawLine) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Text(heading,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
      );
    }

    final bullet = rawLine.replaceFirst(RegExp(r'^[-*]\s+'), '').trim();
    if (bullet != rawLine) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Icon(Icons.circle,
                  size: 5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 9),
            Expanded(
                child: Text(bullet,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.25))),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(rawLine,
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.25)),
    );
  }

  Widget _aboutTab() {
    final info = _packageInfo;
    final updateNotes = _updateInfo == null
        ? ''
        : _localizedReleaseNotes(_updateInfo!.notes.trim());
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(t.appName,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(
            '${t.version}: ${info == null ? '...' : _displayVersion(info.version)}',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Text(t.author,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Text(t.dataCredits,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12.5)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _openHelpLink('https://ko-fi.com/moligon'),
          icon: const Icon(Icons.favorite_border),
          label: Text(t.supportOnKofi),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _showChangelogDialog,
          icon: const Icon(Icons.history),
          label: Text(t.viewChangelog),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _openHelpLink(
              'https://github.com/$githubOwner/$githubRepo/releases/latest'),
          icon: const Icon(Icons.open_in_new),
          label: Text(t.openLatestRelease),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _checkingUpdate ? null : _checkForUpdates,
          icon: _checkingUpdate
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.system_update_alt),
          label: Text(_checkingUpdate ? t.checkingUpdates : t.checkUpdates),
        ),
        if (_updateInfo != null && _updateInfo!.available) ...[
          const SizedBox(height: 16),
          Text(t.updateAvailable(_updateInfo!.version),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          if (updateNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            _releaseNotesCard(updateNotes),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _downloadingUpdate ? null : _downloadAndInstallUpdate,
            icon: _downloadingUpdate
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download),
            label: Text(_downloadingUpdate
                ? t.downloadingUpdate
                : t.downloadAndInstall),
          ),
        ],
      ],
    );
  }
}

class _ProfileBackgroundCropScreen extends StatefulWidget {
  final String imagePath;
  final bool isPt;

  const _ProfileBackgroundCropScreen({
    required this.imagePath,
    required this.isPt,
  });

  @override
  State<_ProfileBackgroundCropScreen> createState() =>
      _ProfileBackgroundCropScreenState();
}

class _ProfileBackgroundCropScreenState
    extends State<_ProfileBackgroundCropScreen> {
  final _boundaryKey = GlobalKey();
  final _transformationController = TransformationController();
  bool _saving = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _saveCrop() async {
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final fullImage = await boundary.toImage(pixelRatio: 2);
      final imageWidth = fullImage.width.toDouble();
      final cropHeight = imageWidth * 136 / 390;
      final cropTop = (fullImage.height - cropHeight) / 2;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final src = Rect.fromLTWH(0, cropTop, imageWidth, cropHeight);
      const dst = Rect.fromLTWH(0, 0, 1170, 408);
      canvas.drawImageRect(fullImage, src, dst, Paint());
      final croppedImage = await recorder.endRecording().toImage(1170, 408);
      final byteData =
          await croppedImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final appDir = await getApplicationDocumentsDirectory();
      final file = File(
        '${appDir.path}/profile_background_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      Navigator.of(context).pop(file.path);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.isPt ? 'Ajustar foto do banner' : 'Adjust banner photo';
    final help = widget.isPt
        ? 'Arraste a imagem e use pinça para ajustar o zoom.'
        : 'Drag the image and pinch to adjust zoom.';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveCrop,
            child: Text(widget.isPt ? 'OK' : 'Done'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(help,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    key: _boundaryKey,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 0.55,
                      maxScale: 5,
                      boundaryMargin: const EdgeInsets.all(420),
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        final cropHeight = width * 136 / 390;
                        final top = (constraints.maxHeight - cropHeight) / 2;
                        return CustomPaint(
                          painter: _CropOverlayPainter(
                            top: top,
                            height: cropHeight,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _saveCrop,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(widget.isPt ? 'Salvar recorte' : 'Save crop'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final double top;
  final double height;

  const _CropOverlayPainter({required this.top, required this.height});

  @override
  void paint(Canvas canvas, Size size) {
    final crop = Rect.fromLTWH(0, top, size.width, height);
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.38);
    final fullPath = Path()..addRect(Offset.zero & size);
    final cropPath = Path()..addRect(crop);
    canvas.drawPath(
      Path.combine(PathOperation.difference, fullPath, cropPath),
      overlay,
    );

    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRect(crop, border);

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.38)
      ..strokeWidth = 0.8;
    for (final x in [
      crop.left + crop.width / 3,
      crop.left + crop.width * 2 / 3
    ]) {
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), grid);
    }
    for (final y in [
      crop.top + crop.height / 3,
      crop.top + crop.height * 2 / 3
    ]) {
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) =>
      oldDelegate.top != top || oldDelegate.height != height;
}
