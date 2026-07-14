import 'package:flutter_test/flutter_test.dart';
import 'package:maathai_desktop/services/rag_service.dart';

void main() {
  group('RagService', () {
    late RagService ragService;

    setUp(() {
      ragService = RagService();
    });

    test('initializes without error', () async {
      // In test environment, asset loading will gracefully fail
      // This tests that the service doesn't throw during init
      await expectLater(
        ragService.initialize(),
        completes,
      );
    });

    test('returns empty list when not initialized', () async {
      final results = await ragService.retrieve(query: 'maize yellow leaves');
      expect(results, isEmpty);
    });

    test('retrieve returns list (post-init)', () async {
      await ragService.initialize();
      // After init (even with no assets in test), should not throw
      final results = await ragService.retrieve(
        query: 'nitrogen deficiency maize yellow leaves',
        topK: 3,
      );
      expect(results, isA<List<String>>());
    });

    test('retrieve with Swahili language parameter', () async {
      await ragService.initialize();
      final results = await ragService.retrieve(
        query: 'mahindi majani njano',
        topK: 3,
        language: 'sw',
      );
      expect(results, isA<List<String>>());
    });
  });
}
