import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/api_service.dart';
import 'detail_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<HistoryEntry> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final h = await ApiService.fetchHistory();
      setState(() { _history = h; _loading = false; });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial')),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF8b5cf6)))
        : _history.isEmpty
          ? const Center(child: Text('Sin historial', style: TextStyle(color: Color(0xFF6d6488))))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _history.length,
              itemBuilder: (ctx, i) {
                final h = _history[i];
                return Card(
                  color: const Color(0xFF110e1a),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 45, height: 65,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a1530),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.play_circle_outline, color: Color(0xFF8b5cf6)),
                    ),
                    title: Text(h.animeTitle, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFe8e4f0))),
                    subtitle: Text('Episodio ${h.episodeNumber}', style: const TextStyle(color: Color(0xFF6d6488), fontSize: 12)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFF6d6488), size: 20),
                      onPressed: () async {
                        await ApiService.deleteHistory(h.animeSlug);
                        _load();
                      },
                    ),
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => DetailPage(slug: h.animeSlug),
                    )),
                  ),
                );
              },
            ),
    );
  }
}
