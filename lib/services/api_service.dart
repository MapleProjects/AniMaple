import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as http_io;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anime.dart';

class ApiService {
  static const _base = 'https://animeav1.com';
  static const _cdn = 'https://cdn.animeav1.com';
  static const _ua = 'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0';

  static SharedPreferences? _prefs;

  // ── HTTP client with timeouts (fixes Android slow/unstable connections) ──
  static http.Client? _client;
  static http.Client get _http {
    if (_client != null) return _client!;
    final io = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 30)
      ..maxConnectionsPerHost = 6;
    _client = http_io.IOClient(io);
    return _client!;
  }

  /// Retry wrapper for flaky connections (Android/mobile).
  static Future<T> _retry<T>(Future<T> Function() fn, {int maxAttempts = 3}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (e) {
        debugPrint('Attempt $attempt/$maxAttempts failed: $e');
        if (attempt == maxAttempts) rethrow;
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    throw StateError('unreachable');
  }

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Map<String, String> get _headers => {'User-Agent': _ua};

  // ── Devalue parser ──────────────────────────────────

  static dynamic _val(List<dynamic> data, int idx) {
    if (idx < 0 || idx >= data.length) return null;
    return data[idx];
  }

  static String _resolveStr(List<dynamic> data, int idx) {
    final v = _val(data, idx);
    if (v is String) return v;
    if (v is int) {
      final inner = _val(data, v);
      if (inner is String) return inner;
      return v.toString();
    }
    if (v is double) return v.toInt().toString();
    return '';
  }

  static int _resolveI64(List<dynamic> data, int idx) {
    final v = _val(data, idx);
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static dynamic _resolveVal(List<dynamic> data, int idx) {
    if (idx < 0 || idx >= data.length) return null;
    final v = data[idx];
    if (v is String || v is bool || v == null) return v;
    if (v is num) return v;
    if (v is List) {
      return v.map((item) {
        if (item is int) return _resolveVal(data, item);
        if (item is double) return _resolveVal(data, item.toInt());
        return item;
      }).toList();
    }
    if (v is Map) {
      final resolved = <String, dynamic>{};
      for (final entry in v.entries) {
        final val = entry.value;
        if (val is int) {
          resolved[entry.key] = _resolveVal(data, val);
        } else if (val is double) {
          resolved[entry.key] = _resolveVal(data, val.toInt());
        } else {
          resolved[entry.key] = val;
        }
      }
      return resolved;
    }
    return v;
  }

  static int? _resolveNumberChain(List<dynamic> data, int idx) {
    if (idx < 0 || idx >= data.length) return null;
    final v = data[idx];
    if (v is int) {
      if (v < data.length && v != idx) {
        final inner = data[v];
        if (inner is int) return inner;
      }
      return v;
    }
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static List<dynamic>? _getMainData(Map<String, dynamic> resp) {
    final nodes = resp['nodes'] as List?;
    if (nodes == null) return null;
    List<dynamic>? best;
    int bestSize = 0;
    for (final node in nodes) {
      if (node == null) continue;
      final data = node['data'] as List?;
      if (data != null && data.length > bestSize) {
        bestSize = data.length;
        best = data;
      }
    }
    return best;
  }

  static List<dynamic>? _getNodeWithKey(Map<String, dynamic> resp, String key) {
    final nodes = resp['nodes'] as List?;
    if (nodes == null) return null;
    for (final node in nodes) {
      if (node == null) continue;
      final data = node['data'] as List?;
      if (data != null && data.isNotEmpty) {
        final first = data[0];
        if (first is Map && first.containsKey(key)) return data;
      }
    }
    return null;
  }

  static String _relativeTime(String dtStr) {
    if (dtStr.isEmpty) return '';
    final clean = dtStr.split('+').first.split('.').first;
    try {
      final dt = DateTime.parse(clean);
      final now = DateTime.now().toUtc();
      final diff = now.difference(dt);
      if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
      if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
      if (diff.inDays < 7) return 'Hace ${diff.inDays} dia${diff.inDays > 1 ? 's' : ''}';
      return 'Hace ${diff.inDays ~/ 7} sem';
    } catch (_) {
      return dtStr;
    }
  }

  static String _coverUrl(int id) => '$_cdn/covers/$id.jpg';
  static String _thumbnailUrl(int id) => '$_cdn/thumbnails/$id.jpg';
  static String _backdropUrl(int id) => '$_cdn/backdrops/$id.jpg';

  // ── Recent episodes ─────────────────────────────────

  static Future<List<RecentEpisode>> fetchRecentEpisodes() async {
    return _retry(() async {
    final resp = await _http.get(Uri.parse('$_base/__data.json'), headers: _headers);
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = _getMainData(json);
    if (data == null) return [];

    final root = data[0] as Map<String, dynamic>?;
    if (root == null) return [];

    final leIdx = root['latestEpisodes'] as int?;
    if (leIdx == null || leIdx >= data.length) return [];

    final epIndices = data[leIdx] as List?;
    if (epIndices == null) return [];

    final episodes = <RecentEpisode>[];
    for (final idxVal in epIndices) {
      final idx = idxVal is int ? idxVal : (idxVal is double ? idxVal.toInt() : -1);
      if (idx < 0 || idx >= data.length) continue;

      final resolved = _resolveVal(data, idx);
      if (resolved is! Map) continue;
      final epObj = resolved;

      final number = epObj['number'] as int? ?? 0;
      final episodeId = epObj['id'] as int? ?? 0;

      final media = epObj['media'];
      final animeTitle = media is Map ? (media['title'] as String? ?? '') : '';
      final animeSlug = media is Map ? (media['slug'] as String? ?? '') : '';

      // Resolve IDs from raw data
      int animeId = 0;
      int? posterId;
      final rawEp = data[idx] as Map?;
      if (rawEp != null) {
        final mediaIdx = rawEp['media'] as int?;
        if (mediaIdx != null && mediaIdx < data.length) {
          final rawMedia = data[mediaIdx] as Map?;
          if (rawMedia != null) {
            final aidIdx = rawMedia['id'] as int?;
            if (aidIdx != null) animeId = _resolveNumberChain(data, aidIdx) ?? 0;
            final pidIdx = rawMedia['poster'] as int?;
            if (pidIdx != null) posterId = _resolveNumberChain(data, pidIdx);
            posterId ??= animeId;
          }
        }
      }

      final createdAt = epObj['createdAt'] as String? ?? '';
      final timeAgo = _relativeTime(createdAt);

      if (animeTitle.isNotEmpty && number > 0) {
        episodes.add(RecentEpisode(
          animeId: animeId,
          animeTitle: animeTitle,
          animeSlug: animeSlug,
          episodeNumber: number,
          episodeId: episodeId,
          thumbnail: posterId != null ? _thumbnailUrl(posterId) : null,
          timeAgo: timeAgo,
        ));
      }
    }
    return episodes;
    });
  }

  // ── Search ──────────────────────────────────────────

  static Future<List<AnimeBasic>> search(String query) async {
    return _retry(() async {
    final resp = await _http.get(
      Uri.parse('$_base/catalogo/__data.json').replace(queryParameters: {'search': query}),
      headers: _headers,
    );
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = _getMainData(json);
    if (data == null) return [];

    final root = data[0] as Map<String, dynamic>?;
    if (root == null) return [];

    final resultsIdx = root['results'] as int?;
    if (resultsIdx == null || resultsIdx >= data.length) return [];

    final indices = data[resultsIdx] as List?;
    if (indices == null) return [];

    return _resolveAnimeList(data, indices);
    });
  }

  // ── Schedule ────────────────────────────────────────

  static Future<List<AnimeBasic>> fetchSchedule() async {
    return _retry(() async {
    final resp = await _http.get(Uri.parse('$_base/horario/__data.json'), headers: _headers);
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final nodes = json['nodes'] as List? ?? [];

    for (final node in nodes) {
      if (node == null) continue;
      final data = node['data'] as List?;
      if (data == null || data.length < 10) continue;
      final root = data[0] as Map<String, dynamic>?;
      if (root == null) continue;

      final allAnimes = <AnimeBasic>[];
      for (final key in root.keys) {
        final idx = root[key] as int?;
        if (idx != null && idx < data.length) {
          final resolved = _resolveVal(data, idx);
          if (resolved is List) {
            allAnimes.addAll(_resolveAnimeListFromResolved(resolved));
          }
        }
      }
      if (allAnimes.isNotEmpty) return allAnimes;
    }
    return [];
    });
  }

  // ── Anime detail ────────────────────────────────────

  static Future<AnimeDetail> fetchAnimeDetail(String slug) async {
    return _retry(() async {
    final resp = await _http.get(Uri.parse('$_base/media/$slug/__data.json'), headers: _headers);
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = _getMainData(json);
    if (data == null) throw Exception('No data');

    final root = data[0] as Map<String, dynamic>;
    final mediaIdx = root['media'] as int? ?? 1;
    final media = _resolveVal(data, mediaIdx);
    if (media is! Map) throw Exception('No media');

    final id = media['id'] as int? ?? 0;
    final title = '${media['title'] ?? ''}';
    final slugVal = '${media['slug'] ?? slug}';
    final synopsis = '${media['synopsis'] ?? ''}';
    final status = '${media['status'] ?? 'unknown'}';
    final posterId = media['poster'] as int? ?? id;
    final startDate = media['startDate'] as String?;

    final cat = media['category'];
    final category = cat is Map ? '${cat['name'] ?? 'TV Anime'}' : 'TV Anime';

    final genresList = media['genres'] as List? ?? [];
    final genres = genresList.whereType<Map>().map((g) => Genre(
      id: g['id'] as int? ?? 0,
      name: '${g['name'] ?? ''}',
      slug: '${g['slug'] ?? ''}',
    )).toList();

    final episodesList = media['episodes'] as List? ?? [];
    final episodes = episodesList.whereType<Map>().map((ep) => EpisodeBasic(
      id: ep['id'] as int? ?? 0,
      number: ep['number'] as int? ?? 0,
    )).toList();

    return AnimeDetail(
      id: id, title: title, synopsis: synopsis,
      poster: _coverUrl(posterId),
      backdrop: _backdropUrl(posterId),
      status: status, startDate: startDate,
      category: category, genres: genres,
      episodesCount: episodes.length, slug: slugVal,
      episodes: episodes, mature: false,
    );
    });
  }

  // ── Episode detail ──────────────────────────────────

  static Future<EpisodeDetail> fetchEpisodeDetail(String animeSlug, int episodeNumber) async {
    return _retry(() async {
    final resp = await _http.get(
      Uri.parse('$_base/media/$animeSlug/$episodeNumber/__data.json'),
      headers: _headers,
    );
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = _getNodeWithKey(json, 'episode') ?? _getMainData(json);
    if (data == null) throw Exception('No data');

    final root = data[0] as Map<String, dynamic>;
    final epIdx = root['episode'] as int? ?? 1;
    final embedsRootIdx = root['embeds'] as int? ?? 0;
    final downloadsRootIdx = root['downloads'] as int? ?? 0;

    final ep = _resolveVal(data, epIdx);
    if (ep is! Map) throw Exception('No episode');

    final episodeId = ep['id'] as int? ?? 0;
    final mediaId = ep['mediaId'] as int? ?? 0;
    final number = ep['number'] as int? ?? episodeNumber;

    final variants = <String>[];
    final embeds = <ServerMirror>[];
    final seenServers = <String>{};  // Track to avoid duplicates

    // Parse embeds
    if (embedsRootIdx > 0 && embedsRootIdx < data.length) {
      final embedsMap = _resolveVal(data, embedsRootIdx);
      if (embedsMap is Map) {
        for (final entry in embedsMap.entries) {
          final variantName = entry.key as String;
          if (!variants.contains(variantName)) variants.add(variantName);
          final mirrors = entry.value as List? ?? [];
          for (final mirror in mirrors) {
            if (mirror is Map) {
              final server = '${mirror['server'] ?? 'Unknown'}';
              final url = '${mirror['url'] ?? ''}';
              final key = '$variantName:$server';
              if (url.isNotEmpty && !seenServers.contains(key)) {
                seenServers.add(key);
                embeds.add(ServerMirror(server: server, url: url, variant: variantName));
              }
            }
          }
        }
      }
    }

    // Parse downloads (skip if already in embeds)
    if (downloadsRootIdx > 0 && downloadsRootIdx < data.length) {
      final dlMap = _resolveVal(data, downloadsRootIdx);
      if (dlMap is Map) {
        for (final entry in dlMap.entries) {
          final variantName = entry.key as String;
          if (!variants.contains(variantName)) variants.add(variantName);
          final mirrors = entry.value as List? ?? [];
          for (final mirror in mirrors) {
            if (mirror is Map) {
              final server = '${mirror['server'] ?? 'Unknown'}';
              final url = '${mirror['url'] ?? ''}';
              final key = '$variantName:$server';
              if (url.isNotEmpty && !seenServers.contains(key)) {
                seenServers.add(key);
                embeds.add(ServerMirror(server: server, url: url, variant: variantName));
              }
            }
          }
        }
      }
    }

    // Sort variants: DUB first
    variants.sort((a, b) {
      if (a == 'DUB') return -1;
      if (b == 'DUB') return 1;
      return a.compareTo(b);
    });

    return EpisodeDetail(
      id: episodeId, mediaId: mediaId, number: number,
      variants: variants, embeds: embeds, filler: false, downloads: [],
    );
    });
  }

  // ── Video URL extraction ────────────────────────────

  static Future<Map<String, dynamic>> fetchVideoUrl(String embedUrl) async {
    return _retry(() async {
    // HLS (zilla-networks)
    if (embedUrl.contains('zilla-networks.com/play/')) {
      final id = embedUrl.split('/').last;
      if (id.isNotEmpty) {
        // Append ?x.m3u8 so video_view's ExoPlayer regex detects HLS type.
        // URL pattern: /m3u8/{id} lacks the dot that ExoPlayer needs (\.m3u8).
        return {'url': 'https://player.zilla-networks.com/m3u8/$id?x.m3u8', 'type': 'hls'};
      }
    }

    // MP4Upload — extract direct .mp4 URL
    if (embedUrl.contains('mp4upload.com')) {
      try {
        final resp = await _http.get(Uri.parse(embedUrl), headers: _headers);
        final body = resp.body;
        // Pattern: src: "https://a*.mp4upload.com:*/d/*/video.mp4"
        final match = RegExp(r'src:\s*"(https://[^"]*\.mp4)"').firstMatch(body);
        if (match != null) {
          return {'url': match.group(1)!, 'type': 'mp4'};
        }
        // Fallback: find any mp4upload mp4 URL
        final match2 = RegExp(r'(https://a\d+\.mp4upload\.com:\d+/d/[^"]*\.mp4)').firstMatch(body);
        if (match2 != null) {
          return {'url': match2.group(1)!, 'type': 'mp4'};
        }
      } catch (e) {
        debugPrint('MP4Upload extraction error: $e');
      }
    }

    return {'url': embedUrl, 'type': 'embed'};
    });
  }

  // ── History (local) ─────────────────────────────────

  static Future<List<HistoryEntry>> fetchHistory() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getStringList('history') ?? [];
    return raw.map((s) {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return HistoryEntry.fromJson(j);
    }).toList();
  }

  static Future<void> addHistory(int animeId, String animeSlug, String animeTitle, int episodeNumber) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getStringList('history') ?? [];
    // Remove existing entry for SAME episode (not same anime)
    raw.removeWhere((s) {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return j['anime_slug'] == animeSlug && j['episode_number'] == episodeNumber;
    });
    // Add to front
    raw.insert(0, jsonEncode({
      'anime_id': animeId,
      'anime_slug': animeSlug,
      'anime_title': animeTitle,
      'episode_number': episodeNumber,
      'watched_at': DateTime.now().toIso8601String(),
    }));
    // Keep max 200
    if (raw.length > 200) raw.removeRange(200, raw.length);
    await prefs.setStringList('history', raw);
  }

  static Future<void> deleteHistory(String animeSlug) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getStringList('history') ?? [];
    raw.removeWhere((s) {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return j['anime_slug'] == animeSlug;
    });
    await prefs.setStringList('history', raw);
  }

  // ── Followed (local) ────────────────────────────────

  static Future<List<FollowedAnime>> fetchFollowed() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getStringList('followed') ?? [];
    return raw.map((s) {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return FollowedAnime.fromJson(j);
    }).toList();
  }

  static Future<bool> isFollowing(int animeId) async {
    final followed = await fetchFollowed();
    return followed.any((f) => f.animeId == animeId);
  }

  static Future<void> follow(int animeId, String animeTitle, String animeSlug) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getStringList('followed') ?? [];
    if (raw.any((s) => (jsonDecode(s) as Map)['anime_id'] == animeId)) return;
    raw.add(jsonEncode({
      'anime_id': animeId,
      'anime_title': animeTitle,
      'anime_slug': animeSlug,
      'followed_at': DateTime.now().toIso8601String(),
    }));
    await prefs.setStringList('followed', raw);
  }

  static Future<bool> toggleFollow(int animeId, String animeTitle, String animeSlug) async {
    final following = await isFollowing(animeId);
    if (following) {
      await unfollow(animeId);
      return false;
    } else {
      await follow(animeId, animeTitle, animeSlug);
      return true;
    }
  }

  static Future<void> unfollow(int animeId) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getStringList('followed') ?? [];
    raw.removeWhere((s) => (jsonDecode(s) as Map)['anime_id'] == animeId);
    await prefs.setStringList('followed', raw);
  }

  // ── Helpers ─────────────────────────────────────────

  static List<AnimeBasic> _resolveAnimeList(List<dynamic> data, List<dynamic> indices) {
    final animes = <AnimeBasic>[];
    for (final idxVal in indices) {
      final idx = idxVal is int ? idxVal : (idxVal is double ? idxVal.toInt() : -1);
      if (idx < 0 || idx >= data.length) continue;
      final obj = data[idx] as Map?;
      if (obj == null) continue;

      final idIdx = obj['id'] as int? ?? 0;
      final titleIdx = obj['title'] as int? ?? 0;
      final slugIdx = obj['slug'] as int? ?? 0;
      final synopsisIdx = obj['synopsis'] as int? ?? 0;
      final startDateIdx = obj['startDate'] as int?;

      final id = _resolveI64(data, idIdx);
      final title = _resolveStr(data, titleIdx);
      final slug = _resolveStr(data, slugIdx);
      final synopsis = _resolveStr(data, synopsisIdx);
      final startDate = startDateIdx != null ? _resolveStr(data, startDateIdx) : null;

      String category = 'TV Anime';
      final catIdx = obj['category'] as int?;
      if (catIdx != null && catIdx < data.length) {
        final catObj = data[catIdx] as Map?;
        if (catObj != null) {
          final nameIdx = catObj['name'] as int? ?? 0;
          category = _resolveStr(data, nameIdx);
        }
      }

      int? posterId = obj['poster'] as int?;
      if (posterId != null) {
        posterId = _resolveI64(data, posterId);
        if (posterId <= 0) posterId = id;
      } else {
        posterId = id;
      }

      if (title.isNotEmpty && slug.isNotEmpty) {
        animes.add(AnimeBasic(
          id: id, title: title, synopsis: synopsis,
          poster: _coverUrl(posterId),
          slug: slug, startDate: startDate, category: category,
        ));
      }
    }
    return animes;
  }

  static List<AnimeBasic> _resolveAnimeListFromResolved(List<dynamic> arr) {
    return arr.whereType<Map>().map((obj) {
      final id = obj['id'] as int? ?? 0;
      final title = obj['title'] as String? ?? '';
      final slug = obj['slug'] as String? ?? '';
      if (title.isEmpty || slug.isEmpty) return null;
      final synopsis = obj['synopsis'] as String? ?? '';
      final startDate = obj['startDate'] as String?;
      final posterId = obj['poster'] as int? ?? id;
      final cat = obj['category'];
      final category = cat is Map ? (cat['name'] as String? ?? 'TV Anime') : 'TV Anime';
      return AnimeBasic(
        id: id, title: title, synopsis: synopsis,
        poster: _coverUrl(posterId),
        slug: slug, startDate: startDate, category: category,
      );
    }).whereType<AnimeBasic>().toList();
  }
}
