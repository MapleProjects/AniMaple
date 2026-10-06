import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Global error handler — shows a bottom sheet with the full error detail
/// and a copy button. Use from any catch block:
///
///   } catch (e, st) {
///     if (mounted) showErrorSheet(context, e, st);
///   }
///
/// Or wrap the whole app in a [ErrorBoundary] to catch unhandled errors.

void showErrorSheet(BuildContext context, Object error, StackTrace? stackTrace,
    {String? title, String? slug}) {
  // Rate limit para evitar saturación de diálogos concurrentes.
  if (_sheetOpen) return;
  final now = DateTime.now();
  if (now.difference(_lastSheetShown) < const Duration(seconds: 8)) return;
  _sheetOpen = true;
  _lastSheetShown = now;

  final detail = _formatError(error, stackTrace, slug: slug);
  // Diferir al final del frame para evitar conflictos con el Navigator durante build/layout.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) {
      _sheetOpen = false;
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF110e1a),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ErrorSheet(
        title: title ?? 'Error',
        error: error,
        detail: detail,
      ),
    ).whenComplete(() => _sheetOpen = false);
  });
  WidgetsBinding.instance.scheduleFrame();
}

bool _sheetOpen = false;
DateTime _lastSheetShown = DateTime.fromMillisecondsSinceEpoch(0);

/// True si el error es puramente de red/conexión (sin Internet, DNS,
/// socket, timeout). Estos errores son ESPERADOS en modo offline: no deben
/// mostrarse como error, la app funciona sin conexión y reintenta sola.
bool isConnectivityError(Object error) {
  final s = error.toString().toLowerCase();
  return s.contains('socketexception') ||
      s.contains('connection') ||
      s.contains('failed host lookup') ||
      s.contains('network is unreachable') ||
      s.contains('timed out') ||
      s.contains('timeout') ||
      s.contains('handshake') ||
      s.contains('software caused connection abort') ||
      s.contains('connection refused') ||
      s.contains('connection reset') ||
      s.contains('errno');
}

String _formatError(Object error, StackTrace? stackTrace, {String? slug}) {
  final buf = StringBuffer();
  buf.writeln('=== AniMaple Error Report ===');
  buf.writeln('Time: ${DateTime.now().toIso8601String()}');
  buf.writeln('Platform: ${kIsWeb ? "web" : Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  if (slug != null) buf.writeln('Slug: $slug');
  buf.writeln();
  buf.writeln('--- Error ---');
  buf.writeln(error.toString());
  if (error is HttpException) {
    buf.writeln('URI: ${error.uri}');
  }
  if (stackTrace != null) {
    buf.writeln();
    buf.writeln('--- Stack Trace ---');
    buf.writeln(stackTrace.toString().substring(
      0,
      stackTrace.toString().length > 2000 ? 2000 : stackTrace.toString().length,
    ));
  }
  return buf.toString();
}

class _ErrorSheet extends StatelessWidget {
  final String title;
  final Object error;
  final String detail;

  const _ErrorSheet({required this.title, required this.error, required this.detail});

  @override
  Widget build(BuildContext context) {
    final errorStr = error.toString();
    final isTimeout = errorStr.toLowerCase().contains('timeout') ||
        errorStr.toLowerCase().contains('timed out');
    final isConnection = errorStr.toLowerCase().contains('connection') ||
        errorStr.toLowerCase().contains('socket') ||
        errorStr.toLowerCase().contains('errno');
    final isParse = errorStr.toLowerCase().contains('format') ||
        errorStr.toLowerCase().contains('parse') ||
        errorStr.toLowerCase().contains('type cast');

    IconData icon;
    Color iconColor;
    String category;
    if (isTimeout) {
      icon = Icons.timer_off_rounded;
      iconColor = const Color(0xFFf59e0b);
      category = 'Timeout de conexión';
    } else if (isConnection) {
      icon = Icons.wifi_off_rounded;
      iconColor = const Color(0xFFef4444);
      category = 'Error de red';
    } else if (isParse) {
      icon = Icons.data_object_rounded;
      iconColor = const Color(0xFF8b5cf6);
      category = 'Error de parseo';
    } else {
      icon = Icons.error_outline_rounded;
      iconColor = const Color(0xFFef4444);
      category = 'Error inesperado';
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3a3252),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Icon(icon, color: iconColor, size: 28),
                const SizedBox(width: 10),
                Text(category, style: TextStyle(color: iconColor, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 8),
              Text(
                _shortError(errorStr),
                style: const TextStyle(color: Color(0xFFe8e4f0), fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0a0812),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1e1832)),
                ),
                child: SelectableText(
                  detail,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFFa99fc0),
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: detail));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Error copiado al portapapeles'),
                        backgroundColor: Color(0xFF8b5cf6),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copiar error', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1e1832),
                    foregroundColor: const Color(0xFFa78bfa),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _shortError(String full) {
    // Extract the first meaningful line
    final lines = full.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty && trimmed.length > 5) return trimmed;
    }
    return full.length > 120 ? '${full.substring(0, 120)}...' : full;
  }
}

/// Catches unhandled errors in the widget tree and shows the error sheet.
/// Wrap [MaterialApp] with this to get global error handling.
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  const ErrorBoundary({super.key, required this.child});

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  @override
  void initState() {
    super.initState();
    FlutterError.onError = (details) {
      debugPrint('FLUTTER ERROR: ${details.exception}');
      debugPrint('${details.stack}');
      // Ignorar fallos de red previstos en modo offline.
      if (isConnectivityError(details.exception)) return;
      // Ignorar aserciones transitorias de constraints en primer frame.
      if (details.exception.toString().contains('crossAxisExtent > 0.0')) {
        return;
      }
      final stackStr = details.stack?.toString() ?? '';
      if (stackStr.contains('rendering/sliver_') ||
          stackStr.contains('rendering/viewport.dart')) {
        return;
      }
      if (mounted) {
        showErrorSheet(
          context,
          details.exception,
          details.stack,
          title: 'Flutter Error',
        );
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    // Evitar renderizado mientras las dimensiones de pantalla sean 0.
    if (MediaQuery.sizeOf(context) == Size.zero) {
      return const SizedBox.shrink();
    }
    return widget.child;
  }
}
