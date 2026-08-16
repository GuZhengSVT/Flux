import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'media/media_kit_init.dart';
import 'providers/core_providers.dart';
import 'providers/settings_provider.dart';
import 'services/notification_service.dart';
import 'services/storage_cleanup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final supportDir = await getApplicationSupportDirectory();
  final db = AppDatabase.open(p.join(supportDir.path, 'flux.sqlite3'));
  final settings = await SettingsController.load();

  await NotificationService.instance.initialize();
  await ensureMediaKitInitialized();
  await const StorageCleanupService().run(db, settings.value);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        settingsControllerProvider.overrideWith((ref) => settings),
      ],
      child: const FluxApp(),
    ),
  );
}
