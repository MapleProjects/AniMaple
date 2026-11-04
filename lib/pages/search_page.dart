import 'dart:async';
import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/api_service.dart';
import '../ui/tokens.dart';
import '../ui/widgets/ambient_page.dart';
import '../ui/widgets/empty_state.dart';
import '../ui/widgets/glass_app_bar.dart';
import '../ui/widgets/poster_card.dart';
import '../ui/widgets/skeletons.dart';
import '../widgets/tv_focusable.dart';
import 'detail_page.dart';

class CatalogGenre {
  final String name;
  final String slug;
  const CatalogGenre(this.name, this.slug);
}

const List<CatalogGenre> kCatalogGenres = [
  CatalogGenre('Acción', 'accion'),
  CatalogGenre('Antropomórfico', 'antropomorfico'),
  CatalogGenre('Artes Marciales', 'artes-marciales'),
  CatalogGenre('Aventura', 'aventura'),
  CatalogGenre('Carreras', 'carreras'),
  CatalogGenre('Ciencia Ficción', 'ciencia-ficcion'),
  CatalogGenre('Comedia', 'comedia'),
  CatalogGenre('Deportes', 'deportes'),
  CatalogGenre('Detectives', 'detectives'),
  CatalogGenre('Drama', 'drama'),
  CatalogGenre('Ecchi', 'ecchi'),
  CatalogGenre('Elenco Adulto', 'elenco-adulto'),
  CatalogGenre('Escolares', 'escolares'),
  CatalogGenre('Espacial', 'espacial'),
  CatalogGenre('Fantasía', 'fantasia'),
  CatalogGenre('Gore', 'gore'),
  CatalogGenre('Gourmet', 'gourmet'),
  CatalogGenre('Harem', 'harem'),
  CatalogGenre('Histórico', 'historico'),
  CatalogGenre('Idols (Hombre)', 'idols-hombre'),
  CatalogGenre('Idols (Mujer)', 'idols-mujer'),
  CatalogGenre('Infantil', 'infantil'),
  CatalogGenre('Isekai', 'isekai'),
  CatalogGenre('Josei', 'josei'),
  CatalogGenre('Juegos Estrategia', 'juegos-estrategia'),
  CatalogGenre('Mahou Shoujo', 'mahou-shoujo'),
  CatalogGenre('Mecha', 'mecha'),
  CatalogGenre('Militar', 'militar'),
  CatalogGenre('Misterio', 'misterio'),
  CatalogGenre('Mitología', 'mitologia'),
  CatalogGenre('Música', 'musica'),
  CatalogGenre('Parodia', 'parodia'),
  CatalogGenre('Psicológico', 'psicologico'),
  CatalogGenre('Recuentos de la Vida', 'recuentos-de-la-vida'),
  CatalogGenre('Romance', 'romance'),
  CatalogGenre('Samurai', 'samurai'),
  CatalogGenre('Seinen', 'seinen'),
  CatalogGenre('Shoujo', 'shoujo'),
  CatalogGenre('Shoujo Ai', 'shoujo-ai'),
  CatalogGenre('Shounen', 'shounen'),
  CatalogGenre('Shounen Ai', 'shounen-ai'),
  CatalogGenre('Sobrenatural', 'sobrenatural'),
  CatalogGenre('Superpoderes', 'superpoderes'),
  CatalogGenre('Suspenso', 'suspenso'),
  CatalogGenre('Terror', 'terror'),
  CatalogGenre('Vampiros', 'vampiros'),
];

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with WidgetsBindingObserver {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  bool _keyboardWasOpen = false;

  List<AnimeBasic> _items = [];
  bool _loading = true;
  bool _refreshing = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  String _lastFetchedQuery = '';
  String? _lastFetchedStatus;
  Set<String> _lastFetchedGenres = {};
  int _requestSeq = 0;
  int _refreshTick = 0;

  bool _filtersOrQueryChanged() {
    final sameGenres =
        _lastFetchedGenres.length == _selectedGenres.length &&
        _lastFetchedGenres.containsAll(_selectedGenres);
    return _lastFetchedQuery != _ctrl.text.trim() ||
        _lastFetchedStatus != _selectedStatus ||
        !sameGenres;
  }

  String? _selectedStatus; // 'emision' or 'finalizado'
  Set<String> _selectedGenres = {}; // multi-genre slugs

  bool get _hasActiveFilters =>
      _selectedStatus != null || _selectedGenres.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _ctrl.addListener(_onSearchChanged);
    _fetchPage(refresh: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _ctrl.removeListener(_onSearchChanged);
    _ctrl.dispose();
    _focusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottomInset = View.of(context).viewInsets.bottom;
    final isOpen = bottomInset > 0;
    if (_keyboardWasOpen && !isOpen && _focusNode.hasFocus) {
      _focusNode.unfocus();
    }
    _keyboardWasOpen = isOpen;
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      if (!_filtersOrQueryChanged()) return;
      _fetchPage(refresh: true);
    });
  }

  void _onScroll() {
    if (_focusNode.hasFocus) {
      _focusNode.unfocus();
    }
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (currentScroll >= maxScroll - 250) {
      _loadMore();
    }
  }

  Future<void> _fetchPage({bool refresh = false}) async {
    final query = _ctrl.text.trim();
    final int seq = ++_requestSeq;

    if (refresh) {
      setState(() {
        _page = 1;
        _hasMore = true;
        if (_items.isEmpty) {
          _loading = true;
        } else {
          _refreshing = true;
        }
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final List<AnimeBasic> results;
      if (query.isNotEmpty) {
        results = await ApiService.fetchCatalog(search: query, page: _page);
      } else {
        results = await ApiService.fetchCatalog(
          order: 'latest_released',
          genres: _selectedGenres.isNotEmpty ? _selectedGenres.toList() : null,
          status: _selectedStatus,
          page: _page,
        );
      }

      if (!mounted || seq != _requestSeq) return;

      setState(() {
        if (refresh) {
          _items = results;
          _lastFetchedQuery = query;
          _lastFetchedStatus = _selectedStatus;
          _lastFetchedGenres = Set<String>.from(_selectedGenres);
          _page = 1;
          _refreshTick++;
        } else {
          _items.addAll(results);
        }
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        if (results.length < 20) {
          _hasMore = false;
        }
      });

      if (refresh && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        if (refresh && _items.isEmpty) _items = [];
        _loading = false;
        _refreshing = false;
        _loadingMore = false;
        if (refresh) _hasMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _page++;
    });
    await _fetchPage(refresh: false);
  }

  void _clearFilters() {
    setState(() {
      _selectedStatus = null;
      _selectedGenres.clear();
    });
    _fetchPage(refresh: true);
  }

  void _showFilterModal() {
    if (_focusNode.hasFocus) {
      _focusNode.unfocus();
    }

    String? tempStatus = _selectedStatus;
    Set<String> tempGenres = Set<String>.from(_selectedGenres);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final activeCount =
                (tempStatus != null ? 1 : 0) + tempGenres.length;

            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filtros',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.text,
                          ),
                        ),
                        if (activeCount > 0)
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                tempStatus = null;
                                tempGenres.clear();
                              });
                            },
                            child: const Text(
                              'Limpiar',
                              style: TextStyle(color: AppColors.danger),
                            ),
                          ),
                      ],
                    ),
                    const Divider(color: AppColors.outline),
                    const SizedBox(height: 8),

                    Expanded(
                      child: ListView(
                        children: [
                          const Text(
                            'Estado',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildChoiceChip(
                                label: 'Todos',
                                selected: tempStatus == null,
                                onSelected: () {
                                  setModalState(() => tempStatus = null);
                                },
                              ),
                              _buildChoiceChip(
                                label: 'En emisión',
                                selected: tempStatus == 'emision',
                                onSelected: () {
                                  setModalState(() => tempStatus = 'emision');
                                },
                              ),
                              _buildChoiceChip(
                                label: 'Completado',
                                selected: tempStatus == 'finalizado',
                                onSelected: () {
                                  setModalState(
                                    () => tempStatus = 'finalizado',
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          Row(
                            children: [
                              const Text(
                                'Géneros',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              if (tempGenres.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${tempGenres.length}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildChoiceChip(
                                label: 'Todos',
                                selected: tempGenres.isEmpty,
                                onSelected: () {
                                  setModalState(() => tempGenres.clear());
                                },
                              ),
                              ...kCatalogGenres.map((g) {
                                final isSelected = tempGenres.contains(g.slug);
                                return _buildChoiceChip(
                                  label: g.name,
                                  selected: isSelected,
                                  onSelected: () {
                                    setModalState(() {
                                      if (isSelected) {
                                        tempGenres.remove(g.slug);
                                      } else {
                                        tempGenres.add(g.slug);
                                      }
                                    });
                                  },
                                );
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _selectedStatus = tempStatus;
                            _selectedGenres = Set.from(tempGenres);
                            if (_ctrl.text.isNotEmpty) {
                              _ctrl.clear();
                            }
                          });
                          _fetchPage(refresh: true);
                        },
                        child: Text(
                          activeCount > 0
                              ? 'Aplicar ($activeCount filtros)'
                              : 'Aplicar filtros',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
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
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.primary.withValues(alpha: 0.22),
      checkmarkColor: AppColors.primaryBright,
      side: BorderSide(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.6)
            : AppColors.outline,
      ),
      labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: selected ? AppColors.primaryBright : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
    );
  }

  String _genreName(String slug) {
    for (final g in kCatalogGenres) {
      if (g.slug == slug) return g.name;
    }
    return slug;
  }

  String _statusName(String status) {
    if (status == 'emision') return 'En emisión';
    if (status == 'finalizado') return 'Completado';
    return status;
  }

  @override
  Widget build(BuildContext context) {
    final query = _ctrl.text.trim();
    final showingSearch = query.isNotEmpty;
    final activeFilterCount =
        (_selectedStatus != null ? 1 : 0) + _selectedGenres.length;
    final showChips = !showingSearch && _hasActiveFilters;
    final headerHeight = 60.0 + (showChips ? 40.0 : 0.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_focusNode.hasFocus) _focusNode.unfocus();
      },
      child: AmbientPage(
        imageUrl: _items.isNotEmpty ? _items.first.poster : null,
        opacity: 0.50,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          resizeToAvoidBottomInset: false,
          appBar: GlassAppBar(
            title: const Text('Catálogo'),
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(headerHeight),
              child: _buildSearchHeader(
                query: query,
                showChips: showChips,
                activeFilterCount: activeFilterCount,
              ),
            ),
          ),
          body: AnimatedPadding(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: _buildResults(
              showingSearch: showingSearch,
              query: query,
              topInset: GlassAppBar.inset(context) + headerHeight,
            ),
          ),
        ),
      ),
    );
  }

  /// Buscador y chips activos: van dentro de la cabecera translúcida.
  Widget _buildSearchHeader({
    required String query,
    required bool showChips,
    required int activeFilterCount,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.xs,
            AppSpace.md,
            AppSpace.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focusNode,
                  onSubmitted: (_) => _focusNode.unfocus(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.text),
                  decoration: InputDecoration(
                    hintText: 'Buscar anime...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _ctrl.clear();
                              _focusNode.unfocus();
                            },
                          ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.md,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              _buildFilterButton(activeFilterCount),
            ],
          ),
        ),
        if (showChips) _buildActiveChips(),
      ],
    );
  }

  Widget _buildFilterButton(int activeFilterCount) {
    return TvFocusable(
      onTap: _showFilterModal,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        height: 48,
        width: 48,
        decoration: BoxDecoration(
          color: _hasActiveFilters
              ? AppColors.primary
              : AppColors.surface.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: _hasActiveFilters
                ? AppColors.primary
                : AppColors.outlineStrong,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.tune_rounded,
              color: _hasActiveFilters ? Colors.white : AppColors.textMuted,
              size: 22,
            ),
            if (_hasActiveFilters)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$activeFilterCount',
                    style: const TextStyle(
                      color: AppColors.primaryDeep,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveChips() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpace.md,
          0,
          AppSpace.md,
          AppSpace.sm,
        ),
        children: [
          if (_selectedStatus != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                label: Text(_statusName(_selectedStatus!)),
                labelStyle: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primaryBright,
                ),
                backgroundColor: AppColors.primary.withValues(alpha: 0.16),
                deleteIcon: const Icon(
                  Icons.close,
                  size: 14,
                  color: AppColors.primaryBright,
                ),
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.45),
                ),
                onDeleted: () {
                  setState(() => _selectedStatus = null);
                  _fetchPage(refresh: true);
                },
              ),
            ),
          ..._selectedGenres.map((slug) {
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InputChip(
                label: Text(_genreName(slug)),
                labelStyle: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primaryBright,
                ),
                backgroundColor: AppColors.primary.withValues(alpha: 0.16),
                deleteIcon: const Icon(
                  Icons.close,
                  size: 14,
                  color: AppColors.primaryBright,
                ),
                side: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.45),
                ),
                onDeleted: () {
                  setState(() => _selectedGenres.remove(slug));
                  _fetchPage(refresh: true);
                },
              ),
            );
          }),
          TextButton(
            onPressed: _clearFilters,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Limpiar todo', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildResults({
    required bool showingSearch,
    required String query,
    required double topInset,
  }) {
    if (_loading && _items.isEmpty) {
      return SingleChildScrollView(
        padding: EdgeInsets.only(top: topInset),
        child: const SkeletonPosterGrid(itemCount: 12),
      );
    }

    if (_items.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: topInset),
        child: EmptyState(
          icon: Icons.search_off_rounded,
          title: showingSearch
              ? 'Sin resultados para "$query"'
              : 'No se encontraron animes',
          message: showingSearch
              ? 'Prueba con otro nombre o quita los filtros.'
              : 'Ajusta los filtros para ampliar el catálogo.',
          actionLabel: _hasActiveFilters ? 'Limpiar filtros' : null,
          onAction: _hasActiveFilters ? _clearFilters : null,
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      key: ValueKey(_refreshTick),
      duration: AppMotion.slow,
      curve: AppMotion.curve,
      tween: Tween(begin: 0, end: 1),
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: Column(
        children: [
          if (_refreshing)
            const LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.primary,
              backgroundColor: AppColors.outline,
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 900;
                return RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  onRefresh: () => _fetchPage(refresh: true),
                  child: GridView.builder(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      AppSpace.page,
                      topInset + AppSpace.sm,
                      AppSpace.page,
                      AppLayout.bottomGutter,
                    ),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: wide
                          ? AppLayout.posterExtentWide
                          : AppLayout.posterExtent,
                      childAspectRatio: AppLayout.posterAspect,
                      crossAxisSpacing: AppSpace.md,
                      mainAxisSpacing: AppSpace.lg,
                    ),
                    itemCount: _items.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i >= _items.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(AppSpace.lg),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      final anime = _items[i];
                      return PosterCard(
                        title: anime.title,
                        imageUrl: anime.poster,
                        subtitle: anime.category,
                        badge: anime.latestEpisodeNumber != null
                            ? 'Ep ${anime.latestEpisodeNumber}'
                            : null,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DetailPage(slug: anime.slug),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
