import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/api_service.dart';
import '../widgets/anime_card.dart';
import 'detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  List<AnimeBasic> _results = [];
  bool _loading = false;
  bool _searched = false;

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() { _loading = true; _searched = true; });
    try {
      final results = await ApiService.search(q);
      setState(() { _results = results; _loading = false; });
    } catch (e) {
      setState(() { _results = []; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: const TextStyle(color: Color(0xFFe8e4f0)),
                    decoration: InputDecoration(
                      hintText: 'Buscar anime...',
                      hintStyle: const TextStyle(color: Color(0xFF6d6488)),
                      filled: true,
                      fillColor: const Color(0xFF110e1a),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1e1832)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF1e1832)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF8b5cf6)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _search,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8b5cf6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  child: const Text('Buscar', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF8b5cf6)))
              : _results.isEmpty && _searched
                ? const Center(child: Text('Sin resultados', style: TextStyle(color: Color(0xFF6d6488))))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      childAspectRatio: 0.65,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) => AnimeCard(
                      anime: _results[i],
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => DetailPage(slug: _results[i].slug),
                      )),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
