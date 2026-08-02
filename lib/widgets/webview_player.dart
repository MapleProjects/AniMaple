import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Reproductor vía WebView para servidores protegidos por Cloudflare
/// (fingerprint TLS de navegador requerido — ExoPlayer/proxy Dart dan 403,
/// pero el WebView es Chromium real y reproduce igual que tu navegador).
///
/// El player del servidor (ej. player.zilla-networks.com/play/{id}) se carga
/// en un <iframe> dentro de una página local. Cloudflare trata las
/// navegaciones top-level con challenge agresivo ("Attention Required" o
/// player sin fuente → "content not found"), pero los iframes embebidos se
/// sirven sin fricción — exactamente como funciona en la web de animeav1,
/// donde el video corre dentro de un iframe.
class WebviewPlayer extends StatefulWidget {
  final String url;
  final String? referer;
  final String? title;
  const WebviewPlayer({
    super.key,
    required this.url,
    this.referer = 'https://animeav1.com/',
    this.title,
  });

  @override
  State<WebviewPlayer> createState() => _WebviewPlayerState();
}

class _WebviewPlayerState extends State<WebviewPlayer> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0a0812))
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (err) {
            debugPrint('WebView error: ${err.errorCode} ${err.description}');
            if (mounted) setState(() => _loading = false);
          },
        ),
      );

    _loadEmbed();
  }

  void _loadEmbed() {
    final playerUrl = widget.url;
    final base = widget.referer ?? 'https://animeav1.com/';

    // Página local que embebe el player del servidor en un iframe (con
    // allowfullscreen). El iframe mantiene el referer de animeav1 si abrimos
    // con baseUrl, lo que evita el challenge top-level de Cloudflare.
    final html = '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  html, body {
    margin: 0; padding: 0; height: 100%; width: 100%;
    background: #0a0812; overflow: hidden;
  }
  iframe {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    border: 0;
    background: #0a0812;
  }
</style>
</head>
<body>
  <iframe src="$playerUrl" allowfullscreen allow="autoplay; fullscreen; encrypted-media; picture-in-picture"></iframe>
</body>
</html>
''';

    _controller.loadHtmlString(
      html,
      baseUrl: base,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ClipRect(
            child: WebViewWidget(controller: _controller),
          ),
        ),
        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xFF0a0812),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF8b5cf6)),
              ),
            ),
          ),
      ],
    );
  }
}
