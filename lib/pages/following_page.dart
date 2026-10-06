import 'package:flutter/material.dart';

import '../models/anime.dart';
import '../services/api_service.dart';
import '../services/download_service.dart';
import '../widgets/tv_focusable.dart';
import 'detail_page.dart';
import 'downloads_page.dart';

class FollowingPage extends StatefulWidget {
  const FollowingPage({super.key});

  @override
  State<FollowingPage> createState() => FollowingPageState();
}

/// Vista de lista con pestañas de seguimiento y descargas locales.
class FollowingPageState extends State<FollowingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  List<FollowedAnime> _following = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void refresh() => _load();

  Future<void> _load() async {
    try {
      final f = await ApiService.fetchFollowed();
      setState(() { _following = f; _loading = false; });
    } catch (e) {
      debugPrint('FOLLOWING ERROR: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _unfollowWithConfirm(FollowedAnime f) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF110e1a),
        title: const Text('Eliminar de favoritos', style: TextStyle(color: Color(0xFFe8e4f0))),
        content: Text('¿Eliminar "${f.animeTitle}" de tu lista?', style: const TextStyle(color: Color(0xFFa99fc0))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF6d6488))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Color(0xFFef4444))),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ApiService.unfollow(f.animeId);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi lista'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: const Color(0xFF8b5cf6),
          labelColor: const Color(0xFFa78bfa),
          unselectedLabelColor: const Color(0xFF6d6488),
          dividerColor: Colors.transparent,
          tabs: const [
            Tab(
              height: 40,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.favorite, size: 16),
                  SizedBox(width: 6),
                  Text('Favoritos'),
                ],
              ),
            ),
            Tab(
              height: 40,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_for_offline_outlined, size: 16),
                  SizedBox(width: 6),
                  Text('Descargas'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildFollowingGrid(),
          const DownloadsPage(),
        ],
      ),
    );
  }

  Widget _buildFollowingGrid() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF8b5cf6)));
    }
    if (_following.isEmpty) {
      return const Center(child: Text('Sin animes seguidos', style: TextStyle(color: Color(0xFF6d6488))));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF8b5cf6),
      child: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          childAspectRatio: 0.6,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _following.length + _queuedCount(),
        itemBuilder: (ctx, i) {
          if (i >= _following.length) {
            final slug = _queuedOnlySlugs()[i - _following.length];
            return _queuedCard(slug);
          }
          final f = _following[i];
          return TvFocusable(
            onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => DetailPage(slug: f.animeSlug),
            )),
            borderRadius: BorderRadius.circular(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF110e1a),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(f.posterUrl, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.favorite, color: Color(0xFFef4444), size: 40))),
                        Positioned(
                          top: 6, left: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFef4444).withValues(alpha: 0.9),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.favorite, color: Colors.white, size: 14),
                          ),
                        ),
                        Positioned(
                          top: 4, right: 4,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _unfollowWithConfirm(f),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(f.animeTitle, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFFe8e4f0), height: 1.3)),
              ],
            ),
          );
        },
      ),
    );
  }

  // Animes con descargas en progreso sin archivos locales completados.
  DownloadService get _dl => DownloadService.instance;

  int _queuedCount() => _queuedOnlySlugs().length;

  List<String> _queuedOnlySlugs() {
    final out = <String>[];
    for (final key in _dl.progress.value.keys) {
      final slug = key.split('#').first;
      if (!_dl.downloadedSlugs().contains(slug) && !out.contains(slug)) {
        out.add(slug);
      }
    }
    return out;
  }

  Widget _queuedCard(String slug) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF110e1a),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFf59e0b).withValues(alpha: 0.5)),
            ),
            child: const Center(
              child: SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2.6, color: Color(0xFFf59e0b)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Descargando…', maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFFf59e0b), height: 1.3)),
      ],
    );
  }
}
