class AnimeBasic {
  final int id;
  final String title;
  final String synopsis;
  final String? poster;
  final String slug;
  final String? startDate;
  final String category;
  final int? latestEpisodeId;
  final int? latestEpisodeNumber;

  AnimeBasic({
    required this.id,
    required this.title,
    required this.synopsis,
    this.poster,
    required this.slug,
    this.startDate,
    required this.category,
    this.latestEpisodeId,
    this.latestEpisodeNumber,
  });

  factory AnimeBasic.fromJson(Map<String, dynamic> j) => AnimeBasic(
    id: j['id'] ?? 0,
    title: j['title'] ?? '',
    synopsis: j['synopsis'] ?? '',
    poster: j['poster'],
    slug: j['slug'] ?? '',
    startDate: j['start_date'],
    category: j['category'] ?? '',
    latestEpisodeId: j['latest_episode_id'],
    latestEpisodeNumber: j['latest_episode_number'],
  );
}

class AnimeDetail {
  final int id;
  final String title;
  final String? aka;
  final String synopsis;
  final String? poster;
  final String? backdrop;
  final String status;
  final String? startDate;
  final String? endDate;
  final String category;
  final List<Genre> genres;
  final int episodesCount;
  final String slug;
  final List<EpisodeBasic> episodes;
  final bool mature;

  AnimeDetail({
    required this.id,
    required this.title,
    this.aka,
    required this.synopsis,
    this.poster,
    this.backdrop,
    required this.status,
    this.startDate,
    this.endDate,
    required this.category,
    required this.genres,
    required this.episodesCount,
    required this.slug,
    required this.episodes,
    required this.mature,
  });

  factory AnimeDetail.fromJson(Map<String, dynamic> j) => AnimeDetail(
    id: j['id'] ?? 0,
    title: j['title'] ?? '',
    aka: j['aka'],
    synopsis: j['synopsis'] ?? '',
    poster: j['poster'],
    backdrop: j['backdrop'],
    status: j['status'] ?? '',
    startDate: j['start_date'],
    endDate: j['end_date'],
    category: j['category'] ?? '',
    genres: (j['genres'] as List? ?? []).map((g) => Genre.fromJson(g)).toList(),
    episodesCount: j['episodes_count'] ?? 0,
    slug: j['slug'] ?? '',
    episodes: (j['episodes'] as List? ?? []).map((e) => EpisodeBasic.fromJson(e)).toList(),
    mature: j['mature'] ?? false,
  );
}

class Genre {
  final int id;
  final String name;
  final String slug;

  Genre({required this.id, required this.name, required this.slug});

  factory Genre.fromJson(Map<String, dynamic> j) =>
    Genre(id: j['id'] ?? 0, name: j['name'] ?? '', slug: j['slug'] ?? '');
}

class EpisodeBasic {
  final int id;
  final int number;

  EpisodeBasic({required this.id, required this.number});

  factory EpisodeBasic.fromJson(Map<String, dynamic> j) =>
    EpisodeBasic(id: j['id'] ?? 0, number: j['number'] ?? 0);
}

class EpisodeDetail {
  final int id;
  final int mediaId;
  final String? title;
  final int number;
  final List<String> variants;
  final bool filler;
  final String? publishedAt;
  final List<ServerMirror> embeds;
  final List<ServerMirror> downloads;

  EpisodeDetail({
    required this.id,
    required this.mediaId,
    this.title,
    required this.number,
    required this.variants,
    required this.filler,
    this.publishedAt,
    required this.embeds,
    required this.downloads,
  });

  factory EpisodeDetail.fromJson(Map<String, dynamic> j) => EpisodeDetail(
    id: j['id'] ?? 0,
    mediaId: j['media_id'] ?? 0,
    title: j['title'],
    number: j['number'] ?? 0,
    variants: List<String>.from(j['variants'] ?? []),
    filler: j['filler'] ?? false,
    publishedAt: j['published_at'],
    embeds: (j['embeds'] as List? ?? []).map((e) => ServerMirror.fromJson(e)).toList(),
    downloads: (j['downloads'] as List? ?? []).map((e) => ServerMirror.fromJson(e)).toList(),
  );
}

class ServerMirror {
  final String server;
  final String url;
  final String variant;
  final bool? alive;

  ServerMirror({required this.server, required this.url, required this.variant, this.alive});

  factory ServerMirror.fromJson(Map<String, dynamic> j) => ServerMirror(
    server: j['server'] ?? '',
    url: j['url'] ?? '',
    variant: j['variant'] ?? '',
    alive: j['alive'],
  );
}

class RecentEpisode {
  final int animeId;
  final String animeTitle;
  final String animeSlug;
  final int episodeNumber;
  final int episodeId;
  final String? thumbnail;
  final String timeAgo;

  RecentEpisode({
    required this.animeId,
    required this.animeTitle,
    required this.animeSlug,
    required this.episodeNumber,
    required this.episodeId,
    this.thumbnail,
    required this.timeAgo,
  });

  factory RecentEpisode.fromJson(Map<String, dynamic> j) => RecentEpisode(
    animeId: j['anime_id'] ?? 0,
    animeTitle: j['anime_title'] ?? '',
    animeSlug: j['anime_slug'] ?? '',
    episodeNumber: j['episode_number'] ?? 0,
    episodeId: j['episode_id'] ?? 0,
    thumbnail: j['thumbnail'],
    timeAgo: j['time_ago'] ?? '',
  );
}

class HistoryEntry {
  final int animeId;
  final String animeSlug;
  final String animeTitle;
  final int episodeNumber;
  final String watchedAt;

  HistoryEntry({
    required this.animeId,
    required this.animeSlug,
    required this.animeTitle,
    required this.episodeNumber,
    required this.watchedAt,
  });

  String get posterUrl => 'https://cdn.animeav1.com/covers/$animeId.jpg';

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    animeId: j['anime_id'] ?? 0,
    animeSlug: j['anime_slug'] ?? '',
    animeTitle: j['anime_title'] ?? '',
    episodeNumber: j['episode_number'] ?? 0,
    watchedAt: j['watched_at'] ?? '',
  );
}

class FollowedAnime {
  final int animeId;
  final String animeTitle;
  final String animeSlug;
  final String followedAt;

  FollowedAnime({
    required this.animeId,
    required this.animeTitle,
    required this.animeSlug,
    required this.followedAt,
  });

  String get posterUrl => 'https://cdn.animeav1.com/covers/$animeId.jpg';

  factory FollowedAnime.fromJson(Map<String, dynamic> j) => FollowedAnime(
    animeId: j['anime_id'] ?? 0,
    animeTitle: j['anime_title'] ?? '',
    animeSlug: j['anime_slug'] ?? '',
    followedAt: j['followed_at'] ?? '',
  );
}
