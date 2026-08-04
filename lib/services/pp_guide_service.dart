import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class GuideItem {
  final String label;
  final String source;
  final String url;
  final bool isDlc;

  const GuideItem({
    required this.label,
    required this.source,
    required this.url,
    this.isDlc = false,
  });
}

class GuideResult {
  final List<GuideItem> base;
  final List<GuideItem> dlc;
  final bool canLoadDlc;

  const GuideResult({
    required this.base,
    required this.dlc,
    this.canLoadDlc = false,
  });
}

class _GuideSpec {
  final String source;
  final String label;
  final String? slug;
  final String? url;

  const _GuideSpec(this.source, this.label, {this.slug, this.url});
}

class _GuideOverride {
  final bool? pp;
  final bool? pst;
  final bool? psnp;
  final List<_GuideSpec>? guides;
  final List<_GuideSpec>? ppItems;
  final List<_GuideSpec>? pstItems;
  final List<_GuideSpec>? psnpItems;
  final List<_GuideSpec>? dlc;
  final bool noDlc;
  final bool noAutoDlc;

  const _GuideOverride({
    this.pp,
    this.pst,
    this.psnp,
    this.guides,
    this.ppItems,
    this.pstItems,
    this.psnpItems,
    this.dlc,
    this.noDlc = false,
    this.noAutoDlc = false,
  });
}

class _PsnDlcItem {
  final String label;
  final String slug;
  final String url;

  const _PsnDlcItem(this.label, this.slug, this.url);
}

class _PcgwCandidate {
  final String label;
  final String slug;

  const _PcgwCandidate(this.label, this.slug);
}

class PpGuideService {
  static const _psnpAsset = 'assets/pp_guide/pp.json';
  static const _pstAsset = 'assets/pp_guide/pst.json';
  static const _psnpUpdaterUrl =
      'https://raw.githubusercontent.com/Yecgaa01/pp-updater/main/pp-updater.json';
  static const _pstUpdaterUrl =
      'https://raw.githubusercontent.com/Yecgaa01/pp-updater/refs/heads/main/PSUpdater.json';
  static const _fixesUrl =
      'https://raw.githubusercontent.com/Yecgaa01/pp-updater/refs/heads/main/fixes.json';

  List<String>? _psnpGuides;
  List<String>? _pstGuides;
  Map<String, _GuideOverride>? _remoteOverrides;
  int _remoteOverridesLoadedAt = 0;
  final _urlExistsCache = <String, bool>{};

  static final PpGuideService instance = PpGuideService._();
  PpGuideService._();

  Future<GuideResult> findBaseGuides(String gameName, int appId) async {
    final key = appId.toString();
    final override = (await _loadRemoteOverrides())[key];
    final autoSlug = _lookupSlugFromName(gameName);
    final collectionOverride = _isCollectionOverride(override);
    final items = <GuideItem>[];

    if (override?.guides != null) {
      await _addManualGuideItems(items, override!.guides!, autoSlug, gameName);
    } else if (collectionOverride) {
      await _addAutoGuideItems(items, override, autoSlug, gameName,
          manualOnly: true);
    } else {
      await _addAutoGuideItems(items, override, autoSlug, gameName);
    }

    final base = _dedupe(items);
    if (base.isEmpty && !_hasGuideOverride(override)) {
      base.addAll(await _findPcgwCollectionItems(gameName, appId));
    }
    final hasManualDlc = (override?.dlc ?? const []).isNotEmpty;
    final canLoadDlc = base.isNotEmpty &&
        override?.noDlc != true &&
        (hasManualDlc ||
            (!_isCollectionOverride(override) &&
                !_skipAutoDlc(gameName, appId, override)));
    final result =
        GuideResult(base: base, dlc: const [], canLoadDlc: canLoadDlc);
    return result;
  }

  Future<List<GuideItem>> findDlcGuides(String gameName, int appId) async {
    final autoSlug = _lookupSlugFromName(gameName);
    final override = (await _loadRemoteOverrides())[appId.toString()];
    if (override?.noDlc == true) {
      return const [];
    }

    final items = <GuideItem>[];
    final manualDlcs = override?.dlc ?? const <_GuideSpec>[];
    for (final dlc in manualDlcs) {
      final url = await _resolveGuideSpecUrl(dlc, autoSlug);
      if (url != null) {
        items.add(GuideItem(
          label: dlc.label,
          source: _sourceKey(dlc.source),
          url: url,
          isDlc: true,
        ));
      }
    }

    if (!_isCollectionOverride(override) &&
        !_skipAutoDlc(gameName, appId, override)) {
      final dlcSlug = _overridePsnpSlug(override, autoSlug);
      final autoDlcs = await _findPsnProfilesDlcItems(dlcSlug);
      for (final dlc in autoDlcs) {
        if (_isSeriesDlcForDifferentGame(autoSlug, dlc) ||
            _isSeriesDlcForDifferentGame(dlcSlug, dlc)) {
          continue;
        }
        items.add(GuideItem(
          label: dlc.label,
          source: 'psnp',
          url: dlc.url,
          isDlc: true,
        ));
        final ppUrl = await _getPowerPyxAutoDlcUrl(dlcSlug, dlc);
        if (ppUrl != null) {
          items.add(GuideItem(
            label: dlc.label,
            source: 'pp',
            url: ppUrl,
            isDlc: true,
          ));
        }
      }
    }

    final sorted = _dedupe(items)
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return sorted;
  }

  Future<void> _addManualGuideItems(List<GuideItem> items,
      List<_GuideSpec> guides, String autoSlug, String gameName) async {
    for (final guide in guides) {
      final url = await _resolveGuideSpecUrl(guide, autoSlug);
      if (url != null) {
        items.add(GuideItem(
          label: guide.label.isNotEmpty ? guide.label : gameName,
          source: _sourceKey(guide.source),
          url: url,
        ));
      }
    }
  }

  Future<void> _addAutoGuideItems(List<GuideItem> items,
      _GuideOverride? override, String autoSlug, String gameName,
      {bool manualOnly = false}) async {
    final baseLabel = gameName.isNotEmpty ? gameName : _slugToLabel(autoSlug);

    if (override?.pp != false && (!manualOnly || override?.ppItems != null)) {
      final ppItems = override?.ppItems;
      if (ppItems != null && ppItems.length > 1) {
        await _addManualGuideItems(items, ppItems, autoSlug, gameName);
      } else {
        final spec = ppItems?.isNotEmpty == true ? ppItems!.first : null;
        var ppUrl = spec?.url;
        if (ppUrl == null) {
          final slug = spec?.slug ?? '$autoSlug-trophy-guide-roadmap';
          ppUrl = await _findPowerPyxUrl(slug);
          if (ppUrl == null && spec?.slug != null) {
            ppUrl = await _findPowerPyxUrl('$autoSlug-trophy-guide-roadmap');
          }
        }
        if (ppUrl != null) {
          items.add(GuideItem(
              label: spec?.label ?? baseLabel, source: 'pp', url: ppUrl));
        }
      }
    }

    if (override?.pst != false && (!manualOnly || override?.pstItems != null)) {
      final pstItems = override?.pstItems ??
          (manualOnly
              ? const <_GuideSpec>[]
              : [_GuideSpec('pst', baseLabel, slug: autoSlug)]);
      for (final spec in pstItems) {
        final pstUrl = spec.url ??
            (override?.pstItems != null && spec.slug != null
                ? _playStationTrophiesUrl(spec.slug!)
                : await _findPstUrl(spec.slug ?? autoSlug));
        if (pstUrl != null) {
          items.add(GuideItem(
              label: spec.label.isNotEmpty ? spec.label : baseLabel,
              source: 'pst',
              url: pstUrl));
        }
      }
    }

    if (override?.psnp != false &&
        (!manualOnly || override?.psnpItems != null)) {
      final psnpItems = override?.psnpItems;
      if (psnpItems != null) {
        for (final spec in psnpItems) {
          final psnpUrl = spec.url ??
              (spec.slug != null && RegExp(r'^\d+-').hasMatch(spec.slug!)
                  ? _psnProfilesUrl(spec.slug!)
                  : await _findPsnProfilesUrl(
                      _cleanPsnpLookupSlug(spec.slug ?? autoSlug)));
          if (psnpUrl != null) {
            items.add(GuideItem(
                label: spec.label.isNotEmpty ? spec.label : baseLabel,
                source: 'psnp',
                url: psnpUrl));
          }
        }
      } else {
        final psnpUrl = await _findPsnProfilesUrl(autoSlug);
        if (psnpUrl != null) {
          items.add(GuideItem(label: baseLabel, source: 'psnp', url: psnpUrl));
        }
      }
    }
  }

  Future<String?> _resolveGuideSpecUrl(_GuideSpec item, String autoSlug) async {
    if (item.url != null) return item.url;
    final source = _sourceKey(item.source);
    final slug = item.slug ?? autoSlug;
    if (source == 'pp') return _findPowerPyxUrl(slug);
    if (source == 'pst') return _playStationTrophiesUrl(slug);
    if (source == 'psnp') {
      if (RegExp(r'^\d+-').hasMatch(slug)) return _psnProfilesUrl(slug);
      return _findPsnProfilesUrl(_cleanPsnpLookupSlug(slug));
    }
    return null;
  }

  Future<List<GuideItem>> _findPcgwCollectionItems(
      String gameName, int appId) async {
    final candidates = await _suggestPcgwCollection(gameName);
    if (candidates.length <= 1) return const [];
    final items = <GuideItem>[];
    for (final candidate in candidates) {
      final slug = _normalizeCollectionSlug(candidate.slug);
      final ppUrl = await _findPowerPyxUrl('$slug-trophy-guide-roadmap');
      if (ppUrl != null) {
        items.add(GuideItem(label: candidate.label, source: 'pp', url: ppUrl));
        continue;
      }
      final psnpUrl = await _findPsnProfilesUrl(slug);
      if (psnpUrl != null) {
        items.add(
            GuideItem(label: candidate.label, source: 'psnp', url: psnpUrl));
      }
    }
    final deduped = _dedupe(items)
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return deduped.length > 1 ? deduped : const [];
  }

  Future<List<_PcgwCandidate>> _suggestPcgwCollection(String title) async {
    if (title.trim().isEmpty) return const [];
    try {
      final page = await _pcgwSearchPage(title);
      if (page == null) return const [];
      final wikitext = await _pcgwWikitext(page);
      if (wikitext == null) return const [];
      return _extractPcgwCandidates(wikitext, page);
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _pcgwSearchPage(String title) async {
    final data = await _pcgwGetJson({
      'action': 'query',
      'format': 'json',
      'list': 'search',
      'srsearch': title,
      'srlimit': '1',
    });
    final search = data?['query']?['search'];
    if (search is List && search.isNotEmpty) {
      final first = search.first;
      if (first is Map && first['title'] is String) {
        return first['title'] as String;
      }
    }
    return null;
  }

  Future<String?> _pcgwWikitext(String title) async {
    final data = await _pcgwGetJson({
      'action': 'query',
      'format': 'json',
      'prop': 'revisions',
      'titles': title,
      'rvprop': 'content',
      'rvslots': 'main',
    });
    final pages = data?['query']?['pages'];
    if (pages is! Map) return null;
    for (final page in pages.values) {
      if (page is! Map) continue;
      final revisions = page['revisions'];
      if (revisions is! List || revisions.isEmpty) continue;
      final revision = revisions.first;
      if (revision is! Map) continue;
      final slots = revision['slots'];
      if (slots is Map) {
        final main = slots['main'];
        if (main is Map && main['*'] is String) return main['*'] as String;
      }
      if (revision['*'] is String) return revision['*'] as String;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _pcgwGetJson(Map<String, String> params) async {
    final uri = Uri.https('www.pcgamingwiki.com', '/w/api.php', params);
    final response = await http.get(uri).timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) return null;
    final parsed = jsonDecode(response.body);
    return parsed is Map<String, dynamic> ? parsed : null;
  }

  List<_PcgwCandidate> _extractPcgwCandidates(
      String wikitext, String pageTitle) {
    final candidates = <_PcgwCandidate>[];
    final seen = <String>{};
    void add(String rawTitle) {
      final label = _normalizePcgwTitle(rawTitle);
      final key = label.toLowerCase();
      if (label.isEmpty || seen.contains(key)) return;
      seen.add(key);
      candidates.add(_PcgwCandidate(label, _pcgwSlugify(label)));
    }

    for (final section in _pcgwSections(wikitext, 'included')) {
      for (final link in _pcgwLinks(section)) {
        add(link);
      }
    }
    for (final section in _pcgwSections(wikitext, 'games')) {
      for (final link in _pcgwLinks(section)) {
        add(link);
      }
    }
    for (final template
        in RegExp(r'\{\{[Cc]ollection([\s\S]*?)\}\}').allMatches(wikitext)) {
      for (final link in _pcgwLinks(template.group(1) ?? '')) {
        add(link);
      }
    }

    final titleLc = pageTitle.toLowerCase();
    if (candidates.isEmpty &&
        (titleLc.contains('collection') || titleLc.contains('compilation'))) {
      for (final link in _pcgwLinks(wikitext)) {
        final label = _normalizePcgwTitle(link);
        final lc = label.toLowerCase();
        if (!lc.contains('category:') &&
            !lc.contains('file:') &&
            !lc.contains('template:') &&
            !lc.contains('pcgamingwiki:')) {
          add(label);
        }
        if (candidates.length >= 12) break;
      }
    }
    return candidates;
  }

  Iterable<String> _pcgwSections(String wikitext, String headingPart) sync* {
    final pattern = RegExp(
        '==+\\s*[^=]*${RegExp.escape(headingPart)}[^=]*\\s*==+([\\s\\S]*?)(?=\\n==)',
        caseSensitive: false);
    for (final match in pattern.allMatches(wikitext)) {
      yield match.group(1) ?? '';
    }
  }

  Iterable<String> _pcgwLinks(String text) sync* {
    for (final match in RegExp(r'\[\[([^\]]+)\]\]').allMatches(text)) {
      yield match.group(1) ?? '';
    }
  }

  String _normalizePcgwTitle(String title) {
    var value = title.trim();
    value = value.replaceFirst(RegExp(r'\s*\|.*$'), '');
    value = value.replaceFirst(RegExp(r'#.*$'), '');
    value = value.replaceFirst(RegExp(r'\s*\([^)]*\)$'), '');
    return value.replaceAll('_', ' ').trim();
  }

  String _pcgwSlugify(String title) {
    var slug = title.toLowerCase().replaceAll('&', ' and ');
    slug = slug.replaceAll(RegExp(r"[:',.!?()]"), '');
    slug = slug.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    slug = slug.replaceAll(RegExp(r'^-+|-+$'), '');
    return slug;
  }

  String _normalizeCollectionSlug(String slug) {
    if (slug.startsWith('ninja-gaiden')) {
      return slug.replaceFirst(RegExp(r'-master-collection$'), '');
    }
    return slug;
  }

  bool _hasGuideOverride(_GuideOverride? override) {
    return override != null &&
        (override.pp != null ||
            override.pst != null ||
            override.psnp != null ||
            override.guides != null ||
            override.ppItems != null ||
            override.pstItems != null ||
            override.psnpItems != null ||
            override.dlc != null);
  }

  Future<Map<String, _GuideOverride>> _loadRemoteOverrides() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_remoteOverrides != null &&
        now - _remoteOverridesLoadedAt < const Duration(minutes: 10).inMilliseconds) {
      return _remoteOverrides!;
    }
    try {
      final fixesUri = Uri.parse(_fixesUrl).replace(queryParameters: {
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final response =
          await http.get(fixesUri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        _remoteOverrides = const {};
        _remoteOverridesLoadedAt = now;
        return _remoteOverrides!;
      }
      final parsed = jsonDecode(response.body);
      final games = parsed is Map ? parsed['games'] : null;
      if (games is! Map) {
        _remoteOverrides = const {};
        _remoteOverridesLoadedAt = now;
        return _remoteOverrides!;
      }
      final result = <String, _GuideOverride>{};
      for (final entry in games.entries) {
        final appId = '${entry.key}';
        final value = entry.value;
        if (appId.isEmpty || value is! Map) continue;
        result[appId] = _parseRemoteOverride(value);
      }
      _remoteOverrides = result;
      _remoteOverridesLoadedAt = now;
    } catch (_) {
      _remoteOverrides = const {};
      _remoteOverridesLoadedAt = now;
    }
    return _remoteOverrides!;
  }

  _GuideOverride _parseRemoteOverride(Map<dynamic, dynamic> value) {
    final guides = _parseRemoteGuideList(value['guides']);
    final dlc = _parseRemoteGuideList(value['dlc']);
    final ppItems = _parseRemoteSourceItems(value['pp'], 'pp');
    final pstItems = _parseRemoteSourceItems(value['pst'], 'pst');
    final psnpItems = _parseRemoteSourceItems(value['psnp'], 'psnp');
    return _GuideOverride(
      pp: _remoteBool(value['pp']),
      pst: _remoteBool(value['pst']),
      psnp: _remoteBool(value['psnp']),
      guides: guides.isEmpty ? null : guides,
      ppItems: ppItems.isEmpty ? null : ppItems,
      pstItems: pstItems.isEmpty ? null : pstItems,
      psnpItems: psnpItems.isEmpty ? null : psnpItems,
      dlc: dlc.isEmpty ? null : dlc,
      noDlc: value['noDlc'] == true,
      noAutoDlc: value['noAutoDlc'] == true,
    );
  }

  bool? _remoteBool(dynamic value) {
    if (value is bool) return value;
    if (value is Map || value is List || value == null) return null;
    return null;
  }

  List<_GuideSpec> _parseRemoteSourceItems(dynamic value, String source) {
    if (value == null || value is bool) return const [];
    if (value is String) return [_GuideSpec(source, '', slug: value)];
    if (value is Map) return [_parseRemoteGuideSpec(value, source)];
    if (value is List) {
      return value
          .map((item) {
            if (item is Map) return _parseRemoteGuideSpec(item, source);
            if (item is String && item.trim().isNotEmpty) {
              final itemValue = item.trim();
              return _GuideSpec(
                source,
                '',
                slug: itemValue.startsWith('http') ? null : itemValue,
                url: itemValue.startsWith('http') ? itemValue : null,
              );
            }
            return null;
          })
          .whereType<_GuideSpec>()
          .toList();
    }
    return const [];
  }

  List<_GuideSpec> _parseRemoteGuideList(dynamic value) {
    if (value is! List) return const [];
    final result = <_GuideSpec>[];
    for (final item in value) {
      if (item is! Map) continue;
      final direct = _parseRemoteGuideSpec(item, '${item['source'] ?? ''}');
      if (direct.url != null || direct.slug != null) {
        result.add(direct);
      }
      for (final source in ['pp', 'pst', 'psnp']) {
        final sourceValue = item[source];
        if (sourceValue == null || sourceValue is bool) continue;
        final label = '${item['label'] ?? ''}'.trim();
        if (sourceValue is String) {
          final value = sourceValue.trim();
          if (value.isEmpty) continue;
          result.add(_GuideSpec(
            source,
            label,
            slug: value.startsWith('http') ? null : value,
            url: value.startsWith('http') ? value : null,
          ));
        } else if (sourceValue is Map) {
          result.add(_parseRemoteGuideSpec(sourceValue, source));
        } else if (sourceValue is List) {
          for (final nested in sourceValue) {
            if (nested is Map) result.add(_parseRemoteGuideSpec(nested, source));
            if (nested is String && nested.trim().isNotEmpty) {
              final value = nested.trim();
              result.add(_GuideSpec(
                source,
                label,
                slug: value.startsWith('http') ? null : value,
                url: value.startsWith('http') ? value : null,
              ));
            }
          }
        }
      }
    }
    return result;
  }

  _GuideSpec _parseRemoteGuideSpec(Map<dynamic, dynamic> item, String fallbackSource) {
    var source = '${item['source'] ?? fallbackSource}'.trim();
    final label = '${item['label'] ?? ''}'.trim();
    final slug = '${item['slug'] ?? ''}'.trim();
    final url = '${item['url'] ?? ''}'.trim();
    if (source.isEmpty && url.isNotEmpty) {
      source = _sourceFromUrl(url);
    }
    return _GuideSpec(
      source.isNotEmpty ? source : fallbackSource,
      label,
      slug: slug.isNotEmpty ? slug : null,
      url: url.isNotEmpty ? url : null,
    );
  }
  String _sourceFromUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('powerpyx.com')) return 'pp';
    if (lower.contains('playstationtrophies.org')) return 'pst';
    if (lower.contains('psnprofiles.com')) return 'psnp';
    return '';
  }

  Future<List<String>> _loadPsnProfilesGuides() async {
    if (_psnpGuides != null) return _psnpGuides!;
    final asset = await _loadStringListAsset(_psnpAsset);
    final remote = await _loadStringListUrl(_psnpUpdaterUrl);
    _psnpGuides = _dedupeStrings([...asset, ...remote])
        .where((slug) => RegExp(r'^\d+-[A-Za-z0-9%\-]+$').hasMatch(slug))
        .toList();
    return _psnpGuides!;
  }

  Future<List<String>> _loadPstGuides() async {
    if (_pstGuides != null) return _pstGuides!;
    final asset = await _loadStringListAsset(_pstAsset);
    final remote = await _loadStringListUrl(_pstUpdaterUrl);
    _pstGuides = _dedupeStrings([...asset, ...remote])
        .map((slug) => slug.toLowerCase())
        .where(
            (slug) => RegExp(r'^[a-z0-9][a-z0-9\-]*[a-z0-9]$').hasMatch(slug))
        .toList();
    return _pstGuides!;
  }

  Future<List<String>> _loadStringListAsset(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        return parsed.whereType<String>().toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<List<String>> _loadStringListUrl(String url) async {
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return const [];
      final body = response.body;
      try {
        final parsed = jsonDecode(body);
        if (parsed is List) {
          return parsed.whereType<String>().toList();
        }
        if (parsed is Map) {
          final result = <String>[];
          for (final entry in parsed.entries) {
            if (entry.key is String) result.add(entry.key as String);
            final value = entry.value;
            if (value is String) result.add(value);
            if (value is Map) {
              if (value['slug'] is String) result.add(value['slug'] as String);
              for (final nested in value.keys) {
                if (nested is String) result.add(nested);
              }
            }
          }
          return result;
        }
      } catch (_) {
        return RegExp(r'"([^"]+)"')
            .allMatches(body)
            .map((match) => match.group(1) ?? '')
            .where((value) => value.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<String?> _findPowerPyxUrl(String slug) async {
    for (final variant in _slugVariants(slug)) {
      final url = _powerPyxUrl(variant);
      if (await _urlExists(url)) return url;
    }
    return null;
  }

  Future<String?> _findPsnProfilesUrl(String slug) async {
    final guides = await _loadPsnProfilesGuides();
    final byStripped = <String, String>{};
    final byTrophyBase = <String, String>{};
    for (final guide in guides) {
      final stripped = _stripId(guide);
      byStripped.putIfAbsent(stripped, () => guide);
      final base = _trophyBase(stripped);
      if (base != null) byTrophyBase.putIfAbsent(base, () => guide);
    }
    for (final variant in _slugVariants(slug)) {
      final guide = byTrophyBase[variant] ??
          byStripped[variant] ??
          byStripped['$variant-trophy-guide'];
      if (guide != null) return _psnProfilesUrl(guide);
    }
    return null;
  }

  Future<String?> _findPstUrl(String slug) async {
    final guides = await _loadPstGuides();
    final bySlug = {for (final guide in guides) guide: guide};
    for (final variant in _slugVariants(slug)) {
      final guide = bySlug[variant.toLowerCase()];
      if (guide != null) return _playStationTrophiesUrl(guide);
      final rawUrl = _playStationTrophiesUrl(variant);
      if (await _urlExists(rawUrl)) return rawUrl;
    }
    return null;
  }

  Future<List<_PsnDlcItem>> _findPsnProfilesDlcItems(String slug) async {
    final guides = await _loadPsnProfilesGuides();
    final results = <_PsnDlcItem>[];
    final seen = <String>{};
    for (final variant in _slugVariants(slug)) {
      final prefix = '$variant-';
      for (final guide in guides) {
        final stripped = _stripId(guide);
        if (!stripped.startsWith(prefix) ||
            !stripped.endsWith('-dlc-trophy-guide') ||
            RegExp('^${RegExp.escape(prefix)}[0-9]+-').hasMatch(stripped) ||
            _isNumberedSeriesFalseDlc(variant, stripped) ||
            !seen.add(guide)) {
          continue;
        }
        final label = _dlcLabel(variant, stripped);
        if (label != null) {
          results.add(_PsnDlcItem(label, guide, _psnProfilesUrl(guide)));
        }
      }
    }
    results
        .sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return results;
  }

  Future<String?> _getPowerPyxAutoDlcUrl(
      String autoSlug, _PsnDlcItem dlc) async {
    final stripped = _stripId(dlc.slug);
    for (final variant in _slugVariants(autoSlug)) {
      final prefix = '$variant-';
      const suffix = '-dlc-trophy-guide';
      if (stripped.startsWith(prefix) && stripped.endsWith(suffix)) {
        final dlcPart =
            stripped.substring(prefix.length, stripped.length - suffix.length);
        return _findPowerPyxUrl('$variant-$dlcPart-dlc-trophy-guide-roadmap');
      }
    }
    return null;
  }

  Future<bool> _urlExists(String url) async {
    final cached = _urlExistsCache[url];
    if (cached != null) return cached;
    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final exists = response.statusCode == 200;
      _urlExistsCache[url] = exists;
      return exists;
    } catch (_) {
      _urlExistsCache[url] = false;
      return false;
    }
  }

  String _lookupSlugFromName(String name) {
    var slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    return _normalizeLookupSlug(slug);
  }

  String _normalizeLookupSlug(String slug) {
    slug = slug.toLowerCase().replaceAll('spiderman', 'spider-man');
    const suffixes = [
      'the-complete-edition',
      'complete-edition',
      'free-edition',
      'free-version',
      'free-trial',
      'free',
      'the-definitive-edition',
      'definitive-edition',
      'remastered-starring-lara-croft',
    ];
    for (final suffix in suffixes) {
      slug = _stripSuffix(slug, suffix);
    }
    slug = slug.replaceAll(
        RegExp(
            r'^(grand-theft-auto-v|grand-theft-auto-5|gta-v|gta-5)(-.+)?-(enhanced|legacy)(-.+)?$'),
        'grand-theft-auto-v');
    slug = slug.replaceAll(
        RegExp(
            r'^(grand-theft-auto-v|grand-theft-auto-5|gta-v|gta-5)-(enhanced|legacy)(-.+)?$'),
        'grand-theft-auto-v');
    return slug;
  }

  String _stripSuffix(String slug, String suffix) {
    final marker = '-$suffix';
    if (slug == suffix) return '';
    if (slug.endsWith(marker)) {
      return slug.substring(0, slug.length - marker.length);
    }
    return slug;
  }

  List<String> _slugVariants(String slug) {
    final variants = <String>[];
    void add(String value) {
      if (value.isNotEmpty && !variants.contains(value)) variants.add(value);
    }

    slug = _normalizeLookupSlug(slug);
    add(slug);
    _addControlledAliases(variants, slug);

    var arabicToRoman = slug;
    for (final pair in _romans) {
      arabicToRoman = _replaceNumberToken(arabicToRoman, pair[1], pair[0]);
    }
    add(arabicToRoman);
    _addControlledAliases(variants, arabicToRoman);

    var romanToArabic = slug;
    for (final pair in _romans) {
      romanToArabic = _replaceNumberToken(romanToArabic, pair[0], pair[1]);
    }
    add(romanToArabic);
    _addControlledAliases(variants, romanToArabic);
    return variants;
  }

  void _addControlledAliases(List<String> variants, String slug) {
    if (slug == 'grand-theft-auto-vice-city') return;
    if (slug == 'grand-theft-auto-5' ||
        slug == 'grand-theft-auto-v' ||
        slug == 'gta-5' ||
        slug == 'gta-v') {
      if (!variants.contains('grand-theft-auto-v-trophy-guide-roadmap')) {
        variants.add('grand-theft-auto-v-trophy-guide-roadmap');
      }
      if (!variants.contains('grand-theft-auto-v-trophy-guide')) {
        variants.add('grand-theft-auto-v-trophy-guide');
      }
    }
  }

  String _replaceNumberToken(String slug, String from, String to) {
    return slug.split('-').map((part) => part == from ? to : part).join('-');
  }

  String _stripId(String slug) => slug.replaceFirst(RegExp(r'^\d+-'), '');

  String? _trophyBase(String stripped) {
    final match = RegExp(r'^(.*)-trophy-guide$').firstMatch(stripped);
    return match?.group(1);
  }

  String? _dlcLabel(String base, String stripped) {
    final pattern = RegExp('^${RegExp.escape(base)}-(.*)-dlc-trophy-guide\$');
    final match = pattern.firstMatch(stripped);
    if (match == null) return null;
    final raw = match.group(1) ?? '';
    if (raw.isEmpty) return null;
    return _slugToLabel(raw);
  }

  bool _isNumberedSeriesFalseDlc(String base, String stripped) {
    final match = RegExp('^${RegExp.escape(base)}-(.*?)-').firstMatch(stripped);
    return _isSeriesMarker(match?.group(1));
  }

  bool _isSeriesDlcForDifferentGame(String baseSlug, _PsnDlcItem dlc) {
    final stripped = _stripId(dlc.slug);
    for (final variant in _slugVariants(baseSlug)) {
      final prefix = '$variant-';
      if (!stripped.startsWith(prefix)) continue;
      final rest = stripped.substring(prefix.length);
      final nextToken = rest.split('-').first;
      if (_isSeriesMarker(nextToken)) return true;
    }
    return false;
  }

  bool _isSeriesMarker(String? token) {
    if (token == null || token.isEmpty) return false;
    final normalized = token.toLowerCase();
    return RegExp(r'^\d+$').hasMatch(normalized) ||
        _seriesMarkers.contains(normalized);
  }

  String _overridePsnpSlug(_GuideOverride? override, String fallbackSlug) {
    final psnp = override?.psnpItems;
    if (psnp == null || psnp.length != 1 || psnp.first.slug == null) {
      return fallbackSlug;
    }
    return _cleanPsnpLookupSlug(psnp.first.slug!);
  }

  String _cleanPsnpLookupSlug(String slug) => slug
      .replaceFirst(RegExp(r'^\d+-'), '')
      .replaceFirst(RegExp(r'-trophy-guide$'), '');

  bool _skipAutoDlc(String gameName, int appId, _GuideOverride? override) {
    final slug = _lookupSlugFromName(gameName);
    return override?.noAutoDlc == true ||
        override?.noDlc == true ||
        appId == 1602010 ||
        slug.endsWith('-the-definitive-edition') ||
        slug.endsWith('-definitive-edition') ||
        slug.startsWith('persona-4-arena-ultimax');
  }

  bool _isCollectionOverride(_GuideOverride? override) {
    if (override == null) return false;
    return (override.ppItems?.length ?? 0) > 1 ||
        (override.pstItems?.length ?? 0) > 1 ||
        (override.psnpItems?.length ?? 0) > 1;
  }

  List<GuideItem> _dedupe(List<GuideItem> items) {
    final seen = <String>{};
    final result = <GuideItem>[];
    for (final item in items) {
      final key = item.url
          .toLowerCase()
          .replaceFirst(RegExp(r'^https?://www\.'), 'https://')
          .replaceFirst(RegExp(r'/$'), '');
      if (seen.add(key)) result.add(item);
    }
    return result;
  }

  List<String> _dedupeStrings(List<String> items) {
    final seen = <String>{};
    final result = <String>[];
    for (final item in items) {
      final value = item.trim();
      if (value.isNotEmpty && seen.add(value)) result.add(value);
    }
    return result;
  }

  String _sourceKey(String source) {
    final normalized = source.toLowerCase();
    if (normalized == 'powerpyx') return 'pp';
    if (normalized == 'ps trophies' ||
        normalized == 'pstrophies' ||
        normalized == 'playstationtrophies' ||
        normalized == 'playstation-trophies') {
      return 'pst';
    }
    if (normalized == 'psn' ||
        normalized == 'psnprofiles' ||
        normalized == 'psn-profiles') {
      return 'psnp';
    }
    return normalized;
  }

  String _slugToLabel(String slug) => slug
      .replaceAll('-', ' ')
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  String _powerPyxUrl(String slug) =>
      'https://www.powerpyx.com/${slug.replaceAll(RegExp(r'^/+|/+$'), '')}/';
  String _playStationTrophiesUrl(String slug) =>
      'https://www.playstationtrophies.org/game/$slug/guide/';
  String _psnProfilesUrl(String slug) => 'https://psnprofiles.com/guide/$slug';

  static const _romans = [
    ['xviii', '18'],
    ['xvii', '17'],
    ['xvi', '16'],
    ['xiii', '13'],
    ['viii', '8'],
    ['vii', '7'],
    ['xiv', '14'],
    ['xii', '12'],
    ['iii', '3'],
    ['xix', '19'],
    ['xv', '15'],
    ['xi', '11'],
    ['vi', '6'],
    ['iv', '4'],
    ['ix', '9'],
    ['ii', '2'],
    ['xx', '20'],
    ['x', '10'],
    ['v', '5'],
    ['i', '1'],
  ];

  static const _seriesMarkers = {
    'ii',
    'iii',
    'iv',
    'v',
    'vi',
    'vii',
    'viii',
    'ix',
    'x',
    'xi',
    'xii',
    'xiii',
    'xiv',
    'xv',
    'xvi',
    'xvii',
    'xviii',
    'xix',
    'xx',
  };

}
