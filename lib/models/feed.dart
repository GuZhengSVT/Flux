class Feed {
  const Feed({
    this.id,
    required this.title,
    required this.url,
    this.siteUrl,
    this.description,
    this.category,
    this.iconUrl,
    this.lastFetchedAt,
    this.isFavorite = false,
    this.rating = 0,
    this.isPinned = false,
  });

  final int? id;
  final String title;
  final String url;
  final String? siteUrl;
  final String? description;
  final String? category;
  final String? iconUrl;
  final DateTime? lastFetchedAt;
  final bool isFavorite;
  final int rating;
  final bool isPinned;

  Feed copyWith({
    int? id,
    String? title,
    String? url,
    String? siteUrl,
    String? description,
    String? category,
    String? iconUrl,
    DateTime? lastFetchedAt,
    bool? isFavorite,
    int? rating,
    bool? isPinned,
  }) {
    return Feed(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      siteUrl: siteUrl ?? this.siteUrl,
      description: description ?? this.description,
      category: category ?? this.category,
      iconUrl: iconUrl ?? this.iconUrl,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      rating: rating ?? this.rating,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  factory Feed.fromMap(Map<String, Object?> map) {
    return Feed(
      id: map['id'] as int?,
      title: map['title'] as String,
      url: map['url'] as String,
      siteUrl: map['site_url'] as String?,
      description: map['description'] as String?,
      category: map['category'] as String?,
      iconUrl: map['icon_url'] as String?,
      lastFetchedAt: map['last_fetched_at'] == null
          ? null
          : DateTime.tryParse(map['last_fetched_at']! as String),
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      rating: map['rating'] as int? ?? 0,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
    );
  }

}
