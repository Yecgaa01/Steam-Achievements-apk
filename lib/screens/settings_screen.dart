import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_text.dart';
import '../models/steam_models.dart';
import '../services/cache_store.dart';
import '../services/foreground_sync.dart';
import '../services/update_service.dart';

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
  late final TextEditingController _steamIdController;
  late final TextEditingController _apiKeyController;
  late bool _showHidden;
  late bool _showAverageCompletion;
  late bool _hideSoftware;
  late bool _hideZeroPercentGames;
  late bool _separateDlcAchievements;
  late String _themeMode;
  late bool _showProgressTiers;
  late bool _showRarityTiers;
  late bool _showObtainabilityBadges;
  late bool _goldPerfectGames;
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
    _steamIdController =
        TextEditingController(text: widget.initialConfig.steamId64);
    _apiKeyController =
        TextEditingController(text: widget.initialConfig.apiKey);
    _showHidden = widget.initialConfig.showHidden;
    _showAverageCompletion = widget.initialConfig.showAverageCompletion;
    _hideSoftware = widget.initialConfig.hideSoftware;
    _hideZeroPercentGames = widget.initialConfig.hideZeroPercentGames;
    _separateDlcAchievements = widget.initialConfig.separateDlcAchievements;
    _themeMode = widget.initialConfig.themeMode;
    _showProgressTiers = widget.initialConfig.showProgressTiers;
    _showRarityTiers = widget.initialConfig.showRarityTiers;
    _showObtainabilityBadges = widget.initialConfig.showObtainabilityBadges;
    _goldPerfectGames = widget.initialConfig.goldPerfectGames;
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
      steamId64: _steamIdController.text,
      apiKey: _apiKeyController.text,
      showHidden: _showHidden,
      languageCode: _languageCode,
      showAverageCompletion: _showAverageCompletion,
      hideSoftware: _hideSoftware,
      hideZeroPercentGames: _hideZeroPercentGames,
      separateDlcAchievements: _separateDlcAchievements,
      themeMode: _themeMode,
      showProgressTiers: _showProgressTiers,
      showRarityTiers: _showRarityTiers,
      showObtainabilityBadges: _showObtainabilityBadges,
      goldPerfectGames: _goldPerfectGames,
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

  Future<void> _startForegroundSyncWithPermission(SteamConfig config) async {
    final foregroundSync = ForegroundSync();
    var notificationsAllowed = await foregroundSync.areNotificationsAllowed();
    if (!notificationsAllowed) {
      notificationsAllowed = await foregroundSync.requestNotifications();
    }
    await foregroundSync.start();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(notificationsAllowed
            ? t.syncStarted
            : t.notificationPermissionDenied)));
    await widget.onSyncRequested?.call(config);
  }

  Future<void> _syncNow() async {
    final config = _currentConfig();
    await CacheStore().saveConfig(config);
    widget.onSaved(config);
    await _startForegroundSyncWithPermission(config);
    if (mounted) Navigator.of(context).pop();
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
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t.settings),
          bottom: TabBar(tabs: [
            Tab(text: t.settingsTab),
            Tab(text: t.advancedTab),
            Tab(text: t.themeTab),
            Tab(text: t.aboutTab)
          ]),
        ),
        body: TabBarView(children: [
          _settingsTab(),
          _advancedTab(),
          _themeTab(),
          _aboutTab()
        ]),
      ),
    );
  }

  Widget _settingsTab() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(t.steam,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(t.configHelp,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        Text(t.saveReminder,
            style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
        const SizedBox(height: 18),
        TextField(
          controller: _steamIdController,
          keyboardType: TextInputType.number,
          decoration:
              InputDecoration(labelText: t.steamId64, hintText: '7656119...'),
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
              icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showApiKey = !_showApiKey),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                _openHelpLink('https://steamcommunity.com/dev/apikey'),
            icon: const Icon(Icons.link, size: 16),
            label: Text(t.apiKeyHelpLink),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
            value: _showHidden,
            onChanged: (value) => setState(() => _showHidden = value),
            title: Text(t.showHidden),
            subtitle: Text(t.showHiddenHelp)),
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
        FilledButton.tonal(
            onPressed:
                _saving || widget.onSyncRequested == null ? null : _syncNow,
            child: Text(t.syncProfileNow)),
        const SizedBox(height: 10),
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
    await CacheStore().clearProfileCache(config.normalizedSteamId64,
        keepManualGames: clearMode == 'keep_manual');
    widget.onSaved(config);
    await widget.onSyncRequested?.call(config);
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
            ButtonSegment(value: 'light', label: Text(t.themeLight)),
          ],
          selected: {_themeMode},
          onSelectionChanged: (value) =>
              setState(() => _themeMode = value.first),
        ),
        const SizedBox(height: 18),
        SwitchListTile(
            value: _showProgressTiers,
            onChanged: (value) => setState(() => _showProgressTiers = value),
            title: Text(t.showProgressTiers),
            subtitle: Text(t.showProgressTiersHelp)),
        SwitchListTile(
            value: _showRarityTiers,
            onChanged: (value) => setState(() => _showRarityTiers = value),
            title: Text(t.showRarityTiers),
            subtitle: Text(t.showRarityTiersHelp)),
        SwitchListTile(
            value: _showObtainabilityBadges,
            onChanged: (value) =>
                setState(() => _showObtainabilityBadges = value),
            title: Text(t.showObtainabilityBadges),
            subtitle: Text(t.showObtainabilityBadgesHelp)),
        SwitchListTile(
            value: _goldPerfectGames,
            onChanged: (value) => setState(() => _goldPerfectGames = value),
            title: Text(t.goldPerfectGames),
            subtitle: Text(t.goldPerfectGamesHelp)),
        const SizedBox(height: 10),
        FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? t.saving : t.save)),
      ],
    );
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
          if (_updateInfo!.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _releaseNotesCard(_updateInfo!.notes.trim()),
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
