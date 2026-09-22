// 领域取值类型（T012 提升，架构第 4 节）。
//
// 这些枚举是**产品规则的可执行形式**（阅读三态互斥、身份判定顺序、正文完整性
// 四态、引用获取方式），被 UI 控件、用例与存储共同引用。放在 core 使
// features 层可以在不依赖 infrastructure 的前提下使用它们。
library;

export 'article_identity.dart';
export 'backup.dart';
export 'article_catalog.dart';
export 'article_search.dart';
export 'article_summary.dart';
export 'article_translation.dart';
export 'article_import.dart';
export 'citation_access.dart';
export 'news_run.dart';
export 'news_schedule.dart';
export 'news_verification.dart';
export 'document_tree.dart';
export 'feed_catalog.dart';
export 'feed_deletion.dart';
export 'feed_fetch.dart';
export 'feed_groups.dart';
export 'feed_store_port.dart';
export 'feed_refresh.dart';
export 'group_collapse.dart';
export 'image_header.dart';
export 'media_cache.dart';
export 'network_conditions.dart';
export 'news_config.dart';
export 'news_prompt.dart';
export 'reading_state.dart';
export 'reading_session.dart';
export 'reading_stats.dart';
export 'reading_stats_store.dart';
export 'remote_deletion.dart';
export 'stable_id.dart';
export 'sync_article_key.dart';
export 'sync_first_merge.dart';
export 'sync_local_store.dart';
export 'sync_projection.dart';
export 'sync_snapshot.dart';
export 'sync_status.dart';
export 'sync_store.dart';
export 'sync_transport.dart';
export 'three_way_merge.dart';
export 'url_secrets.dart';
export 'url_guard.dart';
export 'webdav.dart';
