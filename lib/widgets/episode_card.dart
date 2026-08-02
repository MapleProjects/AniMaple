import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../pages/detail_page.dart';

class EpisodeCard extends StatelessWidget {
  final RecentEpisode episode;
  final VoidCallback? onTap;

  const EpisodeCard({super.key, required this.episode, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => DetailPage(slug: episode.animeSlug),
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
                  if (episode.thumbnail != null)
                    Image.network(
                      episode.thumbnail!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.play_circle_outline, color: Color(0xFF4a4260), size: 40)),
                    )
                  else
                    const Center(child: Icon(Icons.play_circle_outline, color: Color(0xFF4a4260), size: 40)),
                  Positioned(
                    top: 6, left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8b5cf6).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text('Ep ${episode.episodeNumber}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                  if (episode.timeAgo.isNotEmpty)
                    Positioned(
                      bottom: 6, right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(episode.timeAgo, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFa99fc0))),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            episode.animeTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFFe8e4f0), height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// Grid card matching animeav1 style — thumbnail with episode badge, time badge, title below
class EpisodeCardGrid extends StatelessWidget {
  final RecentEpisode episode;
  final VoidCallback? onTap;

  const EpisodeCardGrid({super.key, required this.episode, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => DetailPage(slug: episode.animeSlug),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail container
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF110e1a),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Poster image
                  if (episode.thumbnail != null)
                    Image.network(
                      episode.thumbnail!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.play_circle_outline, color: Color(0xFF4a4260), size: 40)),
                    )
                  else
                    const Center(child: Icon(Icons.play_circle_outline, color: Color(0xFF4a4260), size: 40)),
                  // Episode badge — bottom-left
                  Positioned(
                    bottom: 8, left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8b5cf6).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text('Episodio ${episode.episodeNumber}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                  // Time badge — bottom-right
                  if (episode.timeAgo.isNotEmpty)
                    Positioned(
                      bottom: 8, right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(episode.timeAgo, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFa99fc0))),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Title
          Text(
            episode.animeTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFFe8e4f0), height: 1.3),
          ),
        ],
      ),
    );
  }
}

/// Horizontal 16:9 landscape card for home page (kept for compatibility)
class EpisodeCardLandscape extends StatelessWidget {
  final RecentEpisode episode;
  final VoidCallback? onTap;

  const EpisodeCardLandscape({super.key, required this.episode, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => DetailPage(slug: episode.animeSlug),
      )),
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: const Color(0xFF110e1a),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 195,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (episode.thumbnail != null)
                    Image.network(
                      episode.thumbnail!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.play_circle_outline, color: Color(0xFF4a4260), size: 36)),
                    )
                  else
                    const Center(child: Icon(Icons.play_circle_outline, color: Color(0xFF4a4260), size: 36)),
                  Positioned(
                    top: 6, left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8b5cf6).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text('Ep ${episode.episodeNumber}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                  const Center(
                    child: Icon(Icons.play_circle_outline, color: Colors.white54, size: 36),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      episode.animeTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFFe8e4f0), height: 1.3),
                    ),
                    const SizedBox(height: 6),
                    if (episode.timeAgo.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(episode.timeAgo, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFa99fc0))),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
