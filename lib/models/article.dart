class Article {
  const Article({
    this.id,
    required this.feedId,
    required this.title,
    this.link,
    this.author,
    this.publishedAt,
    this.contentHtml,
    this.summary,
    this.imageUrl,
    this.categories,
    this.isRead = false,
    this.isFavorite = false,
    this.isReadLater = false,
    this.fetchedAt,
  });

  final int? id;
  final int feedId;
  final String title;
  final String? link;
  final String? author;
  final DateTime? publishedAt;
  final String? contentHtml;
  final String? summary;
  final String? imageUrl;
  final List<String>? categories;
  final bool isRead;
  final bool isFavorite;
  final bool isReadLater;
  final DateTime? fetchedAt;

  Article copyWith({
    int? id,
    int? feedId,
    String? title,
    String? link,
    String? author,
    DateTime? publishedAt,
    String? contentHtml,
    String? summary,
    String? imageUrl,
    List<String>? categories,
    bool? isRead,
    bool? isFavorite,
    bool? isReadLater,
    DateTime? fetchedAt,
  }) {
    return Article(
      id: id ?? this.id,
      feedId: feedId ?? this.feedId,
      title: title ?? this.title,
      link: link ?? this.link,
      author: author ?? this.author,
      publishedAt: publishedAt ?? this.publishedAt,
      contentHtml: contentHtml ?? this.contentHtml,
      summary: summary ?? this.summary,
      imageUrl: imageUrl ?? this.imageUrl,
      categories: categories ?? this.categories,
      isRead: isRead ?? this.isRead,
      isFavorite: isFavorite ?? this.isFavorite,
      isReadLater: isReadLater ?? this.isReadLater,
      fetchedAt: fetchedAt ?? this.fetchedAt,
    );
  }

  factory Article.fromMap(Map<String, Object?> map) {
    final rawCategories = map['categories'] as String?;
    return Article(
      id: map['id'] as int?,
      feedId: map['feed_id'] as int,
      title: map['title'] as String,
      link: map['link'] as String?,
      author: map['author'] as String?,
      publishedAt: map['published_at'] == null
          ? null
          : DateTime.tryParse(map['published_at']! as String),
      contentHtml: map['content'] as String?,
      summary: map['summary'] as String?,
      imageUrl: map['image_url'] as String?,
      categories: rawCategories == null || rawCategories.isEmpty
          ? null
          : rawCategories.split('|'),
      isRead: (map['is_read'] as int? ?? 0) == 1,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      isReadLater: (map['is_read_later'] as int? ?? 0) == 1,
      fetchedAt: map['fetched_at'] == null
          ? null
          : DateTime.tryParse(map['fetched_at']! as String),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'feed_id': feedId,
      'title': title,
      'link': link,
      'author': author,
      'published_at': publishedAt?.toIso8601String(),
      'content': contentHtml,
      'summary': summary,
      'image_url': imageUrl,
      'categories': categories?.join('|'),
      'is_read': isRead ? 1 : 0,
      'is_favorite': isFavorite ? 1 : 0,
      'is_read_later': isReadLater ? 1 : 0,
      'fetched_at': fetchedAt?.toIso8601String(),
    };
  }

  /// 简单排序比较器：最新发布在前。
  static int byNewest(Article a, Article b) {
    final at =
        a.publishedAt ?? a.fetchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt =
        b.publishedAt ?? b.fetchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bt.compareTo(at);
  }
}
