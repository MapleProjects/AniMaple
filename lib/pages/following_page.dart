import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/api_service.dart';
import 'detail_page.dart';

class FollowingPage extends StatefulWidget {
  const FollowingPage({super.key});

  @override
  State<FollowingPage> createState() => _FollowingPageState();
}

class _FollowingPageState extends State<FollowingPage> {
  List<FollowedAnime> _following = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await ApiService.fetchFollowed();
      setState(() { _following = f; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
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
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _following.length,
              itemBuilder: (ctx, i) {
                final f = _following[i];
                return Card(
                  color: const Color(0xFF110e1a),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.favorite, color: Color(0xFFef4444)),
                    title: Text(f.animeTitle, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFe8e4f0))),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Color(0xFF6d6488), size: 20),
                      onPressed: () async {
                        await ApiService.unfollow(f.animeId);
                        _load();
                      },
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => DetailPage(slug: f.animeSlug),
                    )),
                  ),
                );
              },
            ),
    );
  }
}
