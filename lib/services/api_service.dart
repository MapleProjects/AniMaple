import 'dart:convert';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import '../models/anime.dart';

class ApiService {
  static late String baseUrl;

  static void init() {
    if (Platform.isAndroid) {
      // Android emulator uses 10.0.2.2 to reach host localhost
      baseUrl = 'http://10.0.2.2:3939';
    } else {
      baseUrl = 'http://127.0.0.1:3939';
    }
  }

  static void setHost(String host) {
    baseUrl = 'http://$host:3939';
  }

  static Future<dynamic> _get(String path) async {
    final resp = await http.get(Uri.parse('$baseUrl/api$path'));
    if (resp.statusCode != 200) throw Exception('API error: ${resp.statusCode}');
    return jsonDecode(resp.body);
  }

  static Future<dynamic> _post(String path) async {
    final resp = await http.post(Uri.parse('$baseUrl/api$path'));
    if (resp.statusCode != 200) throw Exception('API error: ${resp.statusCode}');
    return jsonDecode(resp.body);
  }

  // ── Recent episodes ──
  static Future<List<RecentEpisode>> fetchRecent() async {
    final data = await _get('/recent');
    return (data as List).map((e) => RecentEpisode.fromJson(e)).toList();
  }

  // ── Search ──
  static Future<List<AnimeBasic>> search(String query) async {
    final data = await _get('/search?q=${Uri.encodeComponent(query)}');
    return (data as List).map((e) => AnimeBasic.fromJson(e)).toList();
  }

  // ── Schedule ──
  static Future<List<AnimeBasic>> fetchSchedule() async {
    final data = await _get('/schedule');
    return (data as List).map((e) => AnimeBasic.fromJson(e)).toList();
  }

  // ── Anime detail ──
  static Future<AnimeDetail> fetchAnimeDetail(String slug) async {
    final data = await _get('/anime/$slug');
    return AnimeDetail.fromJson(data);
  }

  // ── Episode detail ──
  static Future<EpisodeDetail> fetchEpisodeDetail(String anime, int episode) async {
    final data = await _get('/episode?anime=$anime&episode=$episode');
    return EpisodeDetail.fromJson(data);
  }

  // ── Check if server is alive ──
  static Future<bool> checkAlive(String url) async {
    try {
      final data = await _get('/check-alive?url=${Uri.encodeComponent(url)}');
      return data['alive'] ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Followed ──
  static Future<List<FollowedAnime>> fetchFollowed() async {
    final data = await _get('/followed');
    return (data as List).map((e) => FollowedAnime.fromJson(e)).toList();
  }

  static Future<bool> toggleFollow(int animeId, String title, String slug) async {
    final data = await _post('/follow?anime_id=$animeId&anime_title=${Uri.encodeComponent(title)}&anime_slug=$slug');
    return data['followed'] ?? false;
  }

  static Future<void> unfollow(int animeId) async {
    await _post('/unfollow?anime_id=$animeId');
  }

  // ── History ──
  static Future<List<HistoryEntry>> fetchHistory() async {
    final data = await _get('/history');
    return (data as List).map((e) => HistoryEntry.fromJson(e)).toList();
  }

  static Future<void> addHistory(int animeId, String slug, String title, int episode) async {
    await _post('/history/add?anime_id=$animeId&anime_slug=$slug&anime_title=${Uri.encodeComponent(title)}&episode_number=$episode');
  }

  static Future<void> deleteHistory(String slug) async {
    await _post('/history/delete?anime_slug=$slug');
  }

  // ── Extract direct video URL ──
  static Future<Map<String, dynamic>> fetchVideoUrl(String embedUrl) async {
    final data = await _get('/video-url?url=${Uri.encodeComponent(embedUrl)}');
    return Map<String, dynamic>.from(data);
  }
}
