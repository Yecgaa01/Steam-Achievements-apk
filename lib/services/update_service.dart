import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const githubOwner = 'Yecgaa01';
const githubRepo = 'Steam-Achievements-apk';
const apkAssetName = 'release.apk';

class UpdateInfo {
  final String version;
  final String notes;
  final String apkUrl;
  final bool available;

  const UpdateInfo(
      {required this.version,
      required this.notes,
      required this.apkUrl,
      required this.available});
}

class UpdateService {
  static const _channel = MethodChannel('steam_achievements/update');

  Future<Map<String, dynamic>?> _getLatestReleaseData() async {
    final uri = Uri.parse(
        'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest');
    final response = await http.get(uri, headers: {
      'Accept': 'application/vnd.github+json'
    }).timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('GitHub ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<String> getLatestReleaseNotes() async {
    final data = await _getLatestReleaseData();
    return '${data?['body'] ?? ''}'.trim();
  }

  Future<UpdateInfo?> checkForUpdate() async {
    final local = await PackageInfo.fromPlatform();
    final data = await _getLatestReleaseData();
    if (data == null) return null;
    final tag = '${data['tag_name'] ?? ''}'
        .replaceFirst(RegExp(r'^v', caseSensitive: false), '');
    final assets = data['assets'] is List ? data['assets'] as List : const [];
    final asset = assets
        .whereType<Map<String, dynamic>>()
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (item) => item?['name'] == apkAssetName,
          orElse: () => null,
        );
    final apkUrl = '${asset?['browser_download_url'] ?? ''}';
    if (tag.isEmpty || apkUrl.isEmpty) return null;

    return UpdateInfo(
      version: tag,
      notes: '${data['body'] ?? ''}',
      apkUrl: apkUrl,
      available: _compareVersions(tag, local.version) > 0,
    );
  }

  Future<String> downloadApk(UpdateInfo update) async {
    final response = await http
        .get(Uri.parse(update.apkUrl))
        .timeout(const Duration(minutes: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Download ${response.statusCode}');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$apkAssetName');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  Future<bool> canInstallUnknownApps() async {
    return await _channel.invokeMethod<bool>('canInstallUnknownApps') ?? true;
  }

  Future<void> openUnknownAppsSettings() async {
    await _channel.invokeMethod<void>('openUnknownAppsSettings');
  }

  Future<void> installApk(String path) async {
    await _channel.invokeMethod<void>('installApk', {'path': path});
  }

  Future<void> showUpdateNotification(UpdateInfo update,
      {required String title, required String text}) async {
    await _channel.invokeMethod<void>('showUpdateNotification', {
      'title': title,
      'text': text,
      'version': update.version,
    });
  }

  int _compareVersions(String remote, String local) {
    final r = _parseVersion(remote);
    final l = _parseVersion(local);
    for (var i = 0; i < 3; i++) {
      if (r[i] != l[i]) return r[i].compareTo(l[i]);
    }
    return 0;
  }

  List<int> _parseVersion(String value) {
    final parts = value
        .split(RegExp(r'[^0-9]+'))
        .where((part) => part.isNotEmpty)
        .take(3)
        .map(int.parse)
        .toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }
}
