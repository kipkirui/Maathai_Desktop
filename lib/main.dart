import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'services/app_log.dart';
import 'state/model_controller.dart';
import 'state/chat_controller.dart';
import 'state/theme_controller.dart';
import 'state/translation_controller.dart';
import 'services/model_service.dart';
import 'services/rag_service.dart';
import 'services/chat_storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppLog.initialize();
  AppLog.info('main', 'Starting Maathai Desktop');

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final modelService = ModelService();
  await modelService.initialize();
  AppLog.info('main', 'ModelService ready');

  final ragService = RagService();
  await ragService.initialize();
  AppLog.info('main', 'RagService ready (${ragService.documentCount} docs)');

  final chatStorage = ChatStorageService();
  await chatStorage.initialize();
  AppLog.info('main', 'ChatStorage ready');

  final modelController = ModelController(modelService: modelService);
  final chatController = ChatController(
    ragService: ragService,
    modelController: modelController,
    storage: chatStorage,
  );
  await chatController.restoreFromStorage();
  AppLog.info('main', 'Restored ${chatController.messages.length} chat messages');

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => TranslationController()),
        ChangeNotifierProvider.value(value: modelController),
        ChangeNotifierProvider.value(value: chatController),
      ],
      child: const MaathaiDesktopApp(),
    ),
  );
}
