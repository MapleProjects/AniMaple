import 'dart:io';
import 'dart:convert';

/// Local HTTP proxy that fixes content-type for obfuscated HLS segments.
///
/// Anime streaming sites serve fMP4 segments with `text/html` content-type
/// and `.html` extensions. ExoPlayer rejects these. This proxy fetches
/// segments from the real server (with a browser User-Agent) and returns
/// them with the correct content-type.
///
/// The proxied playlist URL ends in `.m3u8` so the video_view plugin's
/// HLS detection regex (`\.(?:mpd|ism/manifest|m3u8)`) recognises it.
class HlsProxy {
  HttpServer? _server;
  int _port = 0;

  int get port => _port;
  bool get isRunning => _server != null;

  /// Start the proxy server on a random available port.
  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;
    _server!.listen(_handleRequest);
  }

  /// Stop the proxy server.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = 0;
  }

  /// Proxy an m3u8 URL: rewrites segment URLs to go through this proxy.
  /// Returns a local URL ending in `.m3u8` for ExoPlayer HLS detection.
  String proxyM3U8(String originalUrl) {
    return 'http://127.0.0.1:$_port/play.m3u8?url=${Uri.encodeComponent(originalUrl)}';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final targetUrl = request.uri.queryParameters['url'];

    if (targetUrl == null) {
      request.response
        ..statusCode = 400
        ..write('Missing url parameter')
        ..close();
      return;
    }

    try {
      if (path.contains('.m3u8')) {
        await _handleM3U8(request, targetUrl);
      } else {
        await _handleSegment(request, targetUrl);
      }
    } catch (e) {
      try {
        request.response
          ..statusCode = 502
          ..write('Proxy error: $e')
          ..close();
      } catch (_) {}
    }
  }

  /// Fetch m3u8, rewrite all segment URLs to go through the proxy.
  Future<void> _handleM3U8(HttpRequest request, String m3u8Url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(m3u8Url));
      req.headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36');
      req.headers.set('Referer', _refererOf(m3u8Url));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();

      final rewritten = _rewriteM3U8(body, m3u8Url);

      request.response
        ..statusCode = res.statusCode
        ..headers.set('Content-Type', 'application/vnd.apple.mpegurl')
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..write(rewritten)
        ..close();
    } finally {
      client.close();
    }
  }

  /// Fetch a segment and return it with correct content-type.
  Future<void> _handleSegment(HttpRequest request, String segmentUrl) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(segmentUrl));
      req.headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36');
      // Referer del dominio del segmento: algunos CDN lo exigen para servir.
      req.headers.set('Referer', _refererOf(segmentUrl));
      final res = await req.close();

      // Segments are fMP4 (video/mp4) regardless of their .html extension.
      final ctype = res.headers.contentType?.mimeType ?? 'video/mp4';
      request.response
        ..statusCode = res.statusCode
        ..headers.set(
          'Content-Type',
          ctype.startsWith('text/') || ctype == 'application/octet-stream'
              ? 'video/mp4'
              : ctype,
        )
        ..headers.set('Access-Control-Allow-Origin', '*');

      await res.pipe(request.response);
    } finally {
      client.close();
    }
  }

  static String _refererOf(String url) {
    try {
      final u = Uri.parse(url);
      return '${u.scheme}://${u.host}/';
    } catch (_) {
      return '';
    }
  }

  String _rewriteM3U8(String content, String baseUrl) {
    final lines = content.split('\n');
    final result = <String>[];
    final base = Uri.parse(baseUrl);

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        result.add(line);
      } else if (trimmed.startsWith('#')) {
        // Rewrite URI="..." inside tags like EXT-X-MAP and EXT-X-KEY
        result.add(trimmed.replaceAllMapped(
          RegExp(r'URI="([^"]+)"'),
          (m) {
            final resolved = _absoluteUrl(m.group(1)!, base);
            return 'URI="http://127.0.0.1:$_port/segment?url=${Uri.encodeComponent(resolved)}"';
          },
        ));
      } else {
        final resolved = _absoluteUrl(trimmed, base);
        result.add('http://127.0.0.1:$_port/segment?url=${Uri.encodeComponent(resolved)}');
      }
    }

    return result.join('\n');
  }

  static String _absoluteUrl(String maybeRelative, Uri base) {
    final u = Uri.tryParse(maybeRelative);
    if (u == null || !u.hasScheme) {
      return base.resolve(maybeRelative).toString();
    }
    return maybeRelative;
  }
}
