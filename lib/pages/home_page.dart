import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/api_service.dart';
import '../widgets/episode_card.dart';
import 'detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<RecentEpisode> _episodes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final eps = await ApiService.fetchRecent();
      setState(() { _episodes = eps; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF8b5cf6), Color(0xFFec4899)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('AniMaple', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white)),
            ),
          ],
        ),
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF8b5cf6)))
        : _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Color(0xFFef4444))))
          : RefreshIndicator(
              color: const Color(0xFF8b5cf6),
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  // Hero banner
                  if (_episodes.isNotEmpty) SliverToBoxAdapter(
                    child: _HeroBanner(episode: _episodes.first),
                  ),
                  // Section header
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Episodios', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFe8e4f0))),
                          SizedBox(height: 4),
                          Text('RECIENTEMENTE ACTUALIZADO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF6d6488), letterSpacing: 1)),
                        ],
                      ),
                    ),
                  ),
                  // Episode grid
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        childAspectRatio: 0.6,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) => EpisodeCard(
                          episode: _episodes[i],
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => DetailPage(slug: _episodes[i].animeSlug),
                          )),
                        ),
                        childCount: _episodes.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final RecentEpisode episode;
  const _HeroBanner({required this.episode});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1a1530), Color(0xFF0a0812)],
        ),
      ),
      child: Stack(
        children: [
          if (episode.thumbnail != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  episode.thumbnail!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xFF0a0812)],
                ),
              ),
            ),
          ),
          Positioned(
            left: 20, bottom: 20, right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8b5cf6).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('Nuevo episodio', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFa78bfa))),
                ),
                const SizedBox(height: 8),
                Text(episode.animeTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 8),
                Row(children: [
                  _badge('Episodio ${episode.episodeNumber}', const Color(0xFF8b5cf6)),
                  const SizedBox(width: 8),
                  _badge(episode.timeAgo, const Color(0xFF3b82f6)),
                ]),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8b5cf6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Ver ahora', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
