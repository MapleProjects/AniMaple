import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/api_service.dart';
import 'detail_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  Map<String, List<AnimeBasic>> _grouped = {};
  List<String> _days = [];
  int _selectedDay = 0;
  bool _loading = true;

  static const _dayNames = ['Domingo','Lunes','Martes','Miercoles','Jueves','Viernes','Sabado'];
  static const _dayOrder = ['Lunes','Martes','Miercoles','Jueves','Viernes','Sabado','Domingo','Proximamente'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sched = await ApiService.fetchSchedule();
      final grouped = <String, List<AnimeBasic>>{};
      for (final a in sched) {
        String day = 'Proximamente';
        if (a.startDate != null) {
          try {
            final dt = DateTime.parse(a.startDate!);
            day = _dayNames[dt.weekday % 7]; // weekday 1=Mon, 7=Sun → index
          } catch (_) {}
        }
        grouped.putIfAbsent(day, () => []).add(a);
      }
      final days = _dayOrder.where((d) => grouped.containsKey(d)).toList();
      final today = _dayNames[DateTime.now().weekday % 7];
      final todayIdx = days.indexOf(today);
      setState(() {
        _grouped = grouped;
        _days = days;
        _selectedDay = todayIdx >= 0 ? todayIdx : 0;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Horario de emisión')),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF8b5cf6)))
        : _days.isEmpty
          ? const Center(child: Text('Sin datos', style: TextStyle(color: Color(0xFF6d6488))))
          : Column(
              children: [
                // Day tabs
                SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _days.length,
                    itemBuilder: (ctx, i) {
                      final isActive = i == _selectedDay;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(_days[i]),
                          selected: isActive,
                          onSelected: (_) => setState(() => _selectedDay = i),
                          selectedColor: const Color(0xFF8b5cf6),
                          backgroundColor: const Color(0xFF110e1a),
                          labelStyle: TextStyle(
                            color: isActive ? Colors.white : const Color(0xFFa99fc0),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          side: const BorderSide(color: Color(0xFF1e1832)),
                        ),
                      );
                    },
                  ),
                ),
                // Anime list for selected day
                Expanded(
                  child: Builder(
                    builder: (ctx) {
                      final day = _days[_selectedDay];
                      final animeList = _grouped[day] ?? [];
                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: animeList.length,
                        itemBuilder: (ctx, i) {
                          final a = animeList[i];
                          return Card(
                            color: const Color(0xFF110e1a),
                            margin: const EdgeInsets.only(bottom: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => DetailPage(slug: a.slug),
                              )),
                              child: Row(
                                children: [
                                  // Poster
                                  ClipRRect(
                                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                                    child: a.poster != null
                                      ? Image.network(a.poster!, width: 80, height: 110, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(width: 80, height: 110, color: const Color(0xFF1a1530), child: const Icon(Icons.image, color: Color(0xFF4a4260))))
                                      : Container(width: 80, height: 110, color: const Color(0xFF1a1530), child: const Icon(Icons.image, color: Color(0xFF4a4260))),
                                  ),
                                  // Info
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFFe8e4f0))),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF8b5cf6).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(a.category, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFa78bfa))),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
