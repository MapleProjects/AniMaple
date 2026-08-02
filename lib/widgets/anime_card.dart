import 'package:flutter/material.dart';
import '../models/anime.dart';

class AnimeCard extends StatelessWidget {
  final AnimeBasic anime;
  final VoidCallback onTap;

  const AnimeCard({super.key, required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFF110e1a),
              ),
              clipBehavior: Clip.antiAlias,
              child: anime.poster != null
                ? Image.network(
                    anime.poster!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image, color: Color(0xFF4a4260)),
                    ),
                  )
                : const Center(
                    child: Icon(Icons.image, color: Color(0xFF4a4260)),
                  ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            anime.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFe8e4f0)),
          ),
          Text(
            anime.category,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6d6488)),
          ),
        ],
      ),
    );
  }
}
