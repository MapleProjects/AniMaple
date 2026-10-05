import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

/// Local HTTP proxy that fixes content-type and headers for HLS / MP4 streams.
///
/// Anime streaming sites require specific Referer/User-Agent and serve
/// fMP4 segments with `text/html` content-type and `.html` extensions.
/// This proxy fetches streams from the real server with a desktop/browser
/// User-Agent and Referer, and serves them to Windows/Android players cleanly.
class HlsProxy {
  static final HlsProxy instance = HlsProxy();
  HttpServer? _server;
  int _port = 0;

  int get port => _port;
  bool get isRunning => _server != null;

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  final HttpClient _client = HttpClient()
    ..badCertificateCallback = ((_, __, ___) => true)
    ..maxConnectionsPerHost = 24
    ..idleTimeout = const Duration(seconds: 60);

  final Map<String, List<String>> _playlistSegments = {};
  final Map<String, Uint8List> _segmentCache = {};
  final Map<String, Future<Uint8List>> _inFlight = {};
  static const int _prefetchWindow = 4;
  static const int _maxCacheSize = 20;

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
    _segmentCache.clear();
    _inFlight.clear();
    _playlistSegments.clear();
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

  void _applyHeaders(HttpClientRequest req, String targetUrl, String? customReferer) {
    req.headers.set('User-Agent', _defaultUserAgent);
    req.headers.set('Accept', '*/*');
    req.headers.set('Accept-Language', 'es-ES,es;q=0.9,en;q=0.8');
    req.headers.set('Sec-Fetch-Dest', 'empty');
    req.headers.set('Sec-Fetch-Mode', 'cors');
    req.headers.set('Sec-Fetch-Site', 'cross-site');

    final ref = customReferer ?? _refererOf(targetUrl);
    if (ref.isNotEmpty) {
      req.headers.set('Referer', ref);
      try {
        final u = Uri.parse(ref);
        req.headers.set('Origin', '${u.scheme}://${u.host}');
      } catch (_) {}
    }
  }

  /// Fetch m3u8, rewrite all playlist and segment URLs to go through the proxy.
  Future<void> _handleM3U8(
    HttpRequest request,
    String m3u8Url,
    String? customReferer,
  ) async {
    final req = await _client.getUrl(Uri.parse(m3u8Url));
    _applyHeaders(req, m3u8Url, customReferer);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();

    final rewritten = _rewriteM3U8(body, m3u8Url, customReferer);

    request.response
      ..statusCode = res.statusCode
      ..headers.set('Content-Type', 'application/vnd.apple.mpegurl')
      ..headers.set('Access-Control-Allow-Origin', '*')
      ..headers.set('Cache-Control', 'no-cache')
      ..write(rewritten);
    await request.response.close();
  }

  /// Fetch a segment with intelligent in-memory caching and predictive prefetching.
  Future<void> _handleSegment(
    HttpRequest request,
    String segmentUrl,
    String? customReferer,
  ) async {
    final ref = customReferer ?? _refererOf(segmentUrl);
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);

    try {
      final bytes = await _getOrFetchSegment(segmentUrl, ref);

      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.headers.set('Content-Type', 'video/mp4');

      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        final start = int.tryParse(parts[0]) ?? 0;
        final end = (parts.length > 1 && parts[1].isNotEmpty)
            ? (int.tryParse(parts[1]) ?? bytes.length - 1)
            : bytes.length - 1;

        if (start < bytes.length && end >= start) {
          final clampedEnd = end >= bytes.length ? bytes.length - 1 : end;
          final slice = bytes.sublist(start, clampedEnd + 1);
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$clampedEnd/${bytes.length}',
          );
          request.response.headers.contentLength = slice.length;
          request.response.add(slice);
          await request.response.close();
          _triggerPrefetchAfter(segmentUrl, ref);
          return;
        }
      }

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();

      _triggerPrefetchAfter(segmentUrl, ref);
    } catch (e) {
      await _pipeDirectSegment(request, segmentUrl, customReferer);
    }
  }

  Future<Uint8List> _getOrFetchSegment(String url, String referer) async {
    if (_segmentCache.containsKey(url)) {
      return _segmentCache[url]!;
    }
    if (_inFlight.containsKey(url)) {
      return await _inFlight[url]!;
    }

    final future = _downloadSegment(url, referer);
    _inFlight[url] = future;
    try {
      final bytes = await future;
      _addToCache(url, bytes);
      return bytes;
    } finally {
      _inFlight.remove(url);
    }
  }

  Future<Uint8List> _downloadSegment(String url, String referer) async {
    final req = await _client.getUrl(Uri.parse(url));
    _applyHeaders(req, url, referer);
    final resp = await req.close();
    if (resp.statusCode != 200 && resp.statusCode != 206) {
      throw HttpException('HTTP ${resp.statusCode} fetching segment', uri: Uri.parse(url));
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in resp) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  void _addToCache(String url, Uint8List bytes) {
    if (_segmentCache.length >= _maxCacheSize) {
      _segmentCache.remove(_segmentCache.keys.first);
    }
    _segmentCache[url] = bytes;
  }

  void _triggerPrefetchAfter(String currentUrl, String referer) {
    for (final segs in _playlistSegments.values) {
      final idx = segs.indexOf(currentUrl);
      if (idx >= 0) {
        for (var i = 1; i <= _prefetchWindow; i++) {
          final targetIdx = idx + i;
          if (targetIdx < segs.length) {
            final nextUrl = segs[targetIdx];
            if (!_segmentCache.containsKey(nextUrl) && !_inFlight.containsKey(nextUrl)) {
              final f = _downloadSegment(nextUrl, referer);
              _inFlight[nextUrl] = f;
              f.then((bytes) {
                _addToCache(nextUrl, bytes);
              }).catchError((_) {}).whenComplete(() {
                _inFlight.remove(nextUrl);
              });
            }
          }
        }
        break;
      }
    }
  }

  Future<void> _pipeDirectSegment(
    HttpRequest request,
    String segmentUrl,
    String? customReferer,
  ) async {
    final req = await _client.getUrl(Uri.parse(segmentUrl));
    _applyHeaders(req, segmentUrl, customReferer);

    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.isNotEmpty) {
      req.headers.set(HttpHeaders.rangeHeader, range);
    }

    final res = await req.close();
    request.response.statusCode = res.statusCode;
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Content-Type', 'video/mp4');

    final contentRange = res.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      request.response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
    }
    final contentLength = res.headers.contentLength;
    if (contentLength > 0) {
      request.response.headers.contentLength = contentLength;
    }

    await res.pipe(request.response);
  }

  /// Fetch video file (MP4) with transparent range forwarding and streaming.
  Future<void> _handleVideo(
    HttpRequest request,
    String videoUrl,
    String? customReferer,
  ) async {
    await _pipeDirectVideo(request, videoUrl, customReferer);
  }

  Future<void> _pipeDirectVideo(
    HttpRequest request,
    String videoUrl,
    String? customReferer,
  ) async {
    try {
      final req = await _client.getUrl(Uri.parse(videoUrl));
      _applyHeaders(req, videoUrl, customReferer);

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

      try {
        await res.pipe(request.response);
      } catch (_) {
        // Client disconnected
      }
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
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
    final segments = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        result.add(line);
      } else if (trimmed.startsWith('#')) {
        result.add(trimmed.replaceAllMapped(
          RegExp(r'URI="([^"]+)"'),
          (m) {
            final uriVal = m.group(1)!;
            final resolved = _absoluteUrl(uriVal, base);
            final path = resolved.toLowerCase().contains('.m3u8') ? 'play.m3u8' : 'segment';
            if (path == 'segment') {
              segments.add(resolved);
            }
            return 'URI="http://127.0.0.1:$_port/$path?url=${Uri.encodeComponent(resolved)}$refParam"';
          },
        ));
      } else {
        final resolved = _absoluteUrl(trimmed, base);
        if (resolved.toLowerCase().contains('.m3u8')) {
          result.add(
            'http://127.0.0.1:$_port/play.m3u8?url=${Uri.encodeComponent(resolved)}$refParam',
          );
        } else {
          segments.add(resolved);
          result.add(
            'http://127.0.0.1:$_port/segment?url=${Uri.encodeComponent(resolved)}$refParam',
          );
        }
      }
    }

    if (segments.isNotEmpty) {
      _playlistSegments[baseUrl] = segments;
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
