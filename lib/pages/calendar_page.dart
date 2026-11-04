import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';
import '../ui/tokens.dart';
import '../ui/widgets/ambient_page.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/poster_card.dart';
import '../ui/widgets/skeletons.dart';
import '../widgets/tv_focusable.dart';
import 'detail_page.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  Map<String, List<AnimeBasic>> _grouped = {};
  List<String> _days = [];
  Set<String> _followedSlugs = {};
  int _selectedDay = 0;
  bool _loading = true;

  static const _dayNames = [
    'Domingo',
    'Lunes',
    'Martes',
    'Miercoles',
    'Jueves',
    'Viernes',
    'Sabado',
  ];
  static const _dayOrder = [
    'Lunes',
    'Martes',
    'Miercoles',
    'Jueves',
    'Viernes',
    'Sabado',
    'Domingo',
    'Proximamente',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    SyncService.stateVersion.addListener(_loadFollowed);
  }

  @override
  void dispose() {
    SyncService.stateVersion.removeListener(_loadFollowed);
    super.dispose();
  }

  Future<void> _loadFollowed() async {
    try {
      final f = await ApiService.fetchFollowed();
      if (mounted) {
        setState(() {
          _followedSlugs = f.map((e) => e.animeSlug).toSet();
        });
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    await _loadFollowed();
    while (mounted) {
      try {
        final sched = await ApiService.fetchSchedule();
        final grouped = <String, List<AnimeBasic>>{};
        for (final a in sched) {
          String day = 'Proximamente';
          final timeStr = a.latestEpisodeCreatedAt ?? a.startDate ?? '';
          if (timeStr.isNotEmpty) {
            try {
              final clean = timeStr.split('+').first.split('.').first;
              final dt = DateTime.parse(clean).toUtc();
              day = _dayNames[dt.weekday % 7];
            } catch (_) {
              if (a.startDate != null) {
                try {
                  final dt = DateTime.parse(a.startDate!);
                  day = _dayNames[dt.weekday % 7];
                } catch (_) {}
              }
            }
          }
          grouped.putIfAbsent(day, () => []).add(a);
        }

        for (final entry in grouped.entries) {
          entry.value.sort((a, b) {
            final ca = a.latestEpisodeCreatedAt ?? '';
            final cb = b.latestEpisodeCreatedAt ?? '';
            if (ca.isEmpty && cb.isEmpty) return 0;
            if (ca.isEmpty) return 1;
            if (cb.isEmpty) return -1;
            return cb.compareTo(ca);
          });
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
        return;
      } catch (e) {
        debugPrint('CALENDAR RETRY: $e');
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AmbientPage(
      imageUrl: _ambientImage,
      opacity: 0.50,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: AppColors.bg.withValues(alpha: 0.62),
              surfaceTintColor: Colors.transparent,
              title: const Text('Horario de emisión'),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: _buildDaySelector(),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: AppSpace.md),
                  child: SkeletonPosterGrid(),
                ),
              )
            else if (_days.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'Sin horario disponible',
                  message: 'No hay emisiones programadas por ahora.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.page,
                  AppSpace.md,
                  AppSpace.page,
                  AppLayout.bottomGutter,
                ),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: AppLayout.posterExtentFor(context),
                    childAspectRatio: AppLayout.posterAspect,
                    crossAxisSpacing: AppSpace.md,
                    mainAxisSpacing: AppSpace.lg,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final day = _days[_selectedDay];
                      final list = _grouped[day] ?? const <AnimeBasic>[];
                      if (i >= list.length) return const SizedBox.shrink();
                      final a = list[i];
                      return PosterCard(
                        title: a.title,
                        imageUrl: a.poster,
                        badge: a.latestEpisodeNumber != null
                            ? 'Ep ${a.latestEpisodeNumber}'
                            : null,
                        subtitle: a.category,
                        favorite: _followedSlugs.contains(a.slug),
                        onTap: () => Navigator.push(
                          ctx,
                          MaterialPageRoute(
                            builder: (_) => DetailPage(slug: a.slug),
                          ),
                        ),
                      );
                    },
                    childCount:
                        (_grouped[_days[_selectedDay]] ?? const []).length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Selector de días; vive en el `bottom` del SliverAppBar y se fija con él.
  Widget _buildDaySelector() {
    final total = MediaQuery.sizeOf(context).width;
    final canExpand = total >= (_days.length * 75);
    if (canExpand) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.sm,
        ),
        child: Row(
          children: [
            for (var i = 0; i < _days.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _buildDayTab(i, isExpanded: true),
                ),
              ),
          ],
        ),
      );
    }
    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.sm,
        ),
        itemCount: _days.length,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
          child: _buildDayTab(i, isExpanded: false),
        ),
      ),
    );
  }

  /// Portada del primer anime del día seleccionado.
  String? get _ambientImage {
    if (_days.isEmpty) return null;
    final list = _grouped[_days[_selectedDay]] ?? const <AnimeBasic>[];
    return list.isNotEmpty ? list.first.poster : null;
  }

  Widget _buildDayTab(int i, {required bool isExpanded}) {
    final isActive = i == _selectedDay;
    final title = _days[i];
    return TvFocusable(
      onTap: () => setState(() => _selectedDay = i),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: AnimatedContainer(
        duration: AppMotion.base,
        curve: AppMotion.curve,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: isExpanded ? AppSpace.xs : AppSpace.md + 2,
          vertical: AppSpace.sm + 1,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.22)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.7)
                : AppColors.outline,
          ),
        ),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: isActive ? AppColors.primaryBright : AppColors.textSecondary,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
