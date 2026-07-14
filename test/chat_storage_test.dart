import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:maathai_desktop/services/chat_storage_service.dart';
import 'package:maathai_desktop/state/chat_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ChatStorageService', () {
    late ChatStorageService storage;

    setUp(() async {
      storage = ChatStorageService();
      await storage.initialize(databasePath: inMemoryDatabasePath);
    });

    tearDown(() async {
      await storage.close();
    });

    test('saves and loads messages in order', () async {
      final first = ChatMessage(
        id: 'm1',
        role: MessageRole.user,
        content: 'Why are my maize leaves yellow?',
      );
      final second = ChatMessage(
        id: 'm2',
        role: MessageRole.assistant,
        content: 'This may be nitrogen deficiency.',
        ragPassages: const ['Apply CAN 50 kg/ha'],
      );

      await storage.saveMessage(first);
      await storage.saveMessage(second);

      final loaded = await storage.loadMessages();
      expect(loaded.length, 2);
      expect(loaded.first.content, first.content);
      expect(loaded.last.ragPassages, second.ragPassages);
    });

    test('persists farm context', () async {
      const context = FarmContext(
        region: 'Nakuru',
        crop: 'Maize',
        season: 'Long rains',
        language: 'sw',
      );

      await storage.saveFarmContext(context);
      final loaded = await storage.loadFarmContext();

      expect(loaded.region, 'Nakuru');
      expect(loaded.crop, 'Maize');
      expect(loaded.season, 'Long rains');
      expect(loaded.language, 'sw');
    });

    test('clearMessages removes all chat history', () async {
      await storage.saveMessage(
        ChatMessage(role: MessageRole.user, content: 'Hello'),
      );
      await storage.clearMessages();

      final loaded = await storage.loadMessages();
      expect(loaded, isEmpty);
    });

    test('skips empty streaming assistant placeholders', () async {
      await storage.saveMessage(
        ChatMessage(
          role: MessageRole.assistant,
          content: '',
          isStreaming: true,
        ),
      );

      final loaded = await storage.loadMessages();
      expect(loaded, isEmpty);
    });
  });
}
