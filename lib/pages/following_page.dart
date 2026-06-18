import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/api_service.dart';
import 'detail_page.dart';

class FollowingPage extends StatefulWidget {
  const FollowingPage({super.key});

  @override
  State<FollowingPage> createState() => FollowingPageState();
}

class FollowingPageState extends State<FollowingPage> {
  List<FollowedAnime> _following = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
      appBar: AppBar(title: const Text('Mi lista')),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF8b5cf6)))
        : _following.isEmpty
          ? const Center(child: Text('Sin animes seguidos', style: TextStyle(color: Color(0xFF6d6488))))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.6,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _following.length,
              itemBuilder: (ctx, i) {
                final f = _following[i];
                return GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => DetailPage(slug: f.animeSlug),
                  )),
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
                              // Favorite badge
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
                              // Delete button
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
}
