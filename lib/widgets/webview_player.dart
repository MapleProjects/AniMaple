import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Reproductor vía WebView para servidores protegidos por Cloudflare
/// (fingerprint TLS de navegador requerido — ExoPlayer/proxy Dart dan 403,
/// pero el WebView es Chromium real y reproduce igual que tu navegador).
///
/// Se carga la página del player del servidor con Referer de animeav1.com
/// (sin él, Cloudflare bloquea incluso en navegador real) y User-Agent
/// de Chrome.
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
          onWebResourceError: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(
        Uri.parse(widget.url),
        headers: widget.referer != null
            ? {'Referer': widget.referer!}
            : const {},
      );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _controller)),
        if (_loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0xFF0a0812),
              child: Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF8b5cf6),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
