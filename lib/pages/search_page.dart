import 'dart:async';
import 'package:flutter/material.dart';
import '../models/anime.dart';
import '../services/api_service.dart';
import '../widgets/anime_card.dart';
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
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;

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
      if (mounted) {
        _fetchPage(refresh: true);
      }
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
    if (refresh) {
      setState(() {
        _loading = true;
        _page = 1;
        _hasMore = true;
      });
    }

    final query = _ctrl.text.trim();
    try {
      final List<AnimeBasic> results;
      if (query.isNotEmpty) {
        results = await ApiService.fetchCatalog(
          search: query,
          page: _page,
        );
      } else {
        results = await ApiService.fetchCatalog(
          order: 'latest_released',
          genres: _selectedGenres.isNotEmpty ? _selectedGenres.toList() : null,
          status: _selectedStatus,
          page: _page,
        );
      }

      if (!mounted) return;
      setState(() {
        if (refresh) {
          _items = results;
        } else {
          _items.addAll(results);
        }
        _loading = false;
        _loadingMore = false;
        if (results.length < 20) {
          _hasMore = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (refresh) _items = [];
        _loading = false;
        _loadingMore = false;
        _hasMore = false;
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
      backgroundColor: const Color(0xFF110e1a),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                            color: Color(0xFFe8e4f0),
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
                              style: TextStyle(color: Color(0xFFef4444)),
                            ),
                          ),
                      ],
                    ),
                    const Divider(color: Color(0xFF1e1832)),
                    const SizedBox(height: 8),

                    Expanded(
                      child: ListView(
                        children: [
                          // Status section
                          const Text(
                            'Estado',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6d6488),
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
                                  setModalState(() => tempStatus = 'finalizado');
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Genre section (Multiple selection)
                          Row(
                            children: [
                              const Text(
                                'Géneros',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6d6488),
                                ),
                              ),
                              if (tempGenres.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF8b5cf6),
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
                                final isSelected =
                                    tempGenres.contains(g.slug);
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
                          backgroundColor: const Color(0xFF8b5cf6),
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
                              fontWeight: FontWeight.bold, fontSize: 15),
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

  static Widget _buildChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF8b5cf6) : const Color(0xFF191428),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFF8b5cf6)
                : const Color(0xFF2d2448),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : const Color(0xFFb8b2cb),
          ),
        ),
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

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_focusNode.hasFocus) _focusNode.unfocus();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catálogo'),
        ),
        body: Column(
          children: [
            // Search & filter bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focusNode,
                      onSubmitted: (_) => _focusNode.unfocus(),
                      style: const TextStyle(color: Color(0xFFe8e4f0)),
                      decoration: InputDecoration(
                        hintText: 'Buscar anime...',
                        hintStyle: const TextStyle(color: Color(0xFF6d6488)),
                        filled: true,
                        fillColor: const Color(0xFF110e1a),
                        prefixIcon: const Icon(Icons.search,
                            color: Color(0xFF6d6488)),
                        suffixIcon: query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close,
                                    color: Color(0xFF6d6488), size: 18),
                                onPressed: () {
                                  _ctrl.clear();
                                  _focusNode.unfocus();
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFF1e1832)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFF1e1832)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFF8b5cf6)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Filter button
                  InkWell(
                    onTap: _showFilterModal,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 48,
                      width: 48,
                      decoration: BoxDecoration(
                        color: _hasActiveFilters
                            ? const Color(0xFF8b5cf6)
                            : const Color(0xFF110e1a),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _hasActiveFilters
                              ? const Color(0xFF8b5cf6)
                              : const Color(0xFF1e1832),
                        ),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            color: _hasActiveFilters
                                ? Colors.white
                                : const Color(0xFF6d6488),
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
                                    color: Color(0xFF8b5cf6),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Active filter chips row (when not in search mode)
            if (!showingSearch && _hasActiveFilters)
              Container(
                height: 38,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    if (_selectedStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InputChip(
                          label: Text(_statusName(_selectedStatus!)),
                          labelStyle: const TextStyle(
                              fontSize: 12, color: Colors.white),
                          backgroundColor:
                              const Color(0xFF8b5cf6).withValues(alpha: 0.25),
                          deleteIcon: const Icon(Icons.close,
                              size: 14, color: Colors.white70),
                          side: const BorderSide(color: Color(0xFF8b5cf6)),
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
                              fontSize: 12, color: Colors.white),
                          backgroundColor:
                              const Color(0xFF8b5cf6).withValues(alpha: 0.25),
                          deleteIcon: const Icon(Icons.close,
                              size: 14, color: Colors.white70),
                          side: const BorderSide(color: Color(0xFF8b5cf6)),
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
                      child: const Text(
                        'Limpiar todo',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF6d6488)),
                      ),
                    ),
                  ],
                ),
              ),

            // Catalog / Search Grid
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: Color(0xFF8b5cf6)),
                    )
                  : _items.isEmpty
                      ? Center(
                          child: Text(
                            showingSearch
                                ? 'Sin resultados para "$query"'
                                : 'No se encontraron animes',
                            style: const TextStyle(color: Color(0xFF6d6488)),
                          ),
                        )
                      : RefreshIndicator(
                          color: const Color(0xFF8b5cf6),
                          onRefresh: () => _fetchPage(refresh: true),
                          child: GridView.builder(
                            controller: _scrollController,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 200,
                              childAspectRatio: 0.65,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                            ),
                            itemCount: _items.length + (_loadingMore ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (i >= _items.length) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF8b5cf6),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              return AnimeCard(
                                anime: _items[i],
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        DetailPage(slug: _items[i].slug),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

