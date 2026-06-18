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
          // Square thumbnail
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: const Color(0xFF110e1a),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  episode.thumbnail != null
                    ? Image.network(
                        episode.thumbnail!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF1a1530),
                          child: const Center(child: Icon(Icons.play_circle_outline, color: Color(0xFF4a4260), size: 32)),
                        ),
                      )
                    : Container(
                        color: const Color(0xFF1a1530),
                        child: const Center(child: Icon(Icons.play_circle_outline, color: Color(0xFF4a4260), size: 32)),
                      ),
                  // Episode badge
                  Positioned(
                    top: 6, left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8b5cf6).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('Ep ${episode.episodeNumber}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                  // Time badge
                  if (episode.timeAgo.isNotEmpty)
                    Positioned(
                      bottom: 6, right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(episode.timeAgo, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFFa99fc0))),
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
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFFe8e4f0), height: 1.3),
          ),
        ],
      ),
    );
  }
}
