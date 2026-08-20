import 'dart:io';
import 'dart:convert';

/// Local HTTP proxy that fixes content-type and headers for HLS / MP4 streams.
///
/// Anime streaming sites require specific Referer/User-Agent and serve
/// fMP4 segments with `text/html` content-type and `.html` extensions.
/// This proxy fetches streams from the real server with a desktop/browser
/// User-Agent and Referer, and serves them to Windows/Android players cleanly.
class HlsProxy {
  HttpServer? _server;
  int _port = 0;

  int get port => _port;
  bool get isRunning => _server != null;

  /// Start the proxy server on a random available loopback port.
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
  /// Returns a local URL ending in `.m3u8` for player HLS detection.
  String proxyM3U8(String originalUrl, {String? referer}) {
    final refParam = referer != null && referer.isNotEmpty
        ? '&ref=${Uri.encodeComponent(referer)}'
        : '';
    return 'http://127.0.0.1:$_port/play.m3u8?url=${Uri.encodeComponent(originalUrl)}$refParam';
  }

  /// Proxy a direct MP4/video URL with proper headers and range request forwarding.
  String proxyVideo(String originalUrl, {String? referer}) {
    final refParam = referer != null && referer.isNotEmpty
        ? '&ref=${Uri.encodeComponent(referer)}'
        : '';
    return 'http://127.0.0.1:$_port/video.mp4?url=${Uri.encodeComponent(originalUrl)}$refParam';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final path = request.uri.path;
    final targetUrl = request.uri.queryParameters['url'];
    final customReferer = request.uri.queryParameters['ref'];

    if (targetUrl == null) {
      request.response
        ..statusCode = 400
        ..write('Missing url parameter')
        ..close();
      return;
    }

    try {
      if (path.contains('.m3u8')) {
        await _handleM3U8(request, targetUrl, customReferer);
      } else if (path.contains('/video.mp4')) {
        await _handleVideo(request, targetUrl, customReferer);
      } else {
        await _handleSegment(request, targetUrl, customReferer);
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

  /// Fetch m3u8, rewrite all playlist and segment URLs to go through the proxy.
  Future<void> _handleM3U8(
    HttpRequest request,
    String m3u8Url,
    String? customReferer,
  ) async {
    final client = HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true);
    try {
      final req = await client.getUrl(Uri.parse(m3u8Url));
      req.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
      final ref = customReferer ?? _refererOf(m3u8Url);
      if (ref.isNotEmpty) req.headers.set('Referer', ref);
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();

      final rewritten = _rewriteM3U8(body, m3u8Url, customReferer);

      request.response
        ..statusCode = res.statusCode
        ..headers.set('Content-Type', 'application/vnd.apple.mpegurl')
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..headers.set('Cache-Control', 'no-cache')
        ..write(rewritten)
        ..close();
    } finally {
      client.close();
    }
  }

  /// Fetch a segment and return it with correct content-type.
  Future<void> _handleSegment(
    HttpRequest request,
    String segmentUrl,
    String? customReferer,
  ) async {
    final client = HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true);
    try {
      final req = await client.getUrl(Uri.parse(segmentUrl));
      req.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
      final ref = customReferer ?? _refererOf(segmentUrl);
      if (ref.isNotEmpty) req.headers.set('Referer', ref);
      final res = await req.close();

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

  /// Fetch video file (MP4) forwarding range headers for seeking support.
  Future<void> _handleVideo(
    HttpRequest request,
    String videoUrl,
    String? customReferer,
  ) async {
    final client = HttpClient()
      ..badCertificateCallback = ((cert, host, port) => true);
    try {
      final req = await client.getUrl(Uri.parse(videoUrl));
      req.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
      final ref = customReferer ?? _refererOf(videoUrl);
      if (ref.isNotEmpty) req.headers.set('Referer', ref);

      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.isNotEmpty) {
        req.headers.set(HttpHeaders.rangeHeader, range);
      }

      final res = await req.close();
      request.response.statusCode = res.statusCode;

      res.headers.forEach((name, values) {
        if (name.toLowerCase() != 'transfer-encoding' &&
            name.toLowerCase() != 'connection') {
          for (final v in values) {
            request.response.headers.add(name, v);
          }
        }
      });
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      if (request.response.headers.contentType == null ||
          request.response.headers.contentType!.mimeType.startsWith('text/')) {
        request.response.headers.set('Content-Type', 'video/mp4');
      }

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

  String _rewriteM3U8(String content, String baseUrl, String? customReferer) {
    final lines = content.split('\n');
    final result = <String>[];
    final base = Uri.parse(baseUrl);
    final refParam = customReferer != null && customReferer.isNotEmpty
        ? '&ref=${Uri.encodeComponent(customReferer)}'
        : '';

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
            return 'URI="http://127.0.0.1:$_port/segment?url=${Uri.encodeComponent(resolved)}$refParam"';
          },
        ));
      } else {
        final resolved = _absoluteUrl(trimmed, base);
        if (resolved.toLowerCase().contains('.m3u8')) {
          result.add(
            'http://127.0.0.1:$_port/play.m3u8?url=${Uri.encodeComponent(resolved)}$refParam',
          );
        } else {
          result.add(
            'http://127.0.0.1:$_port/segment?url=${Uri.encodeComponent(resolved)}$refParam',
          );
        }
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
