import 'package:flutter_test/flutter_test.dart';
import 'package:maathai_desktop/services/prompt_service.dart';
import 'package:maathai_desktop/state/chat_controller.dart';

void main() {
  group('PromptService', () {
    late PromptService promptService;

    setUp(() {
      promptService = PromptService();
    });

    test('builds prompt with ChatML format for Qwen2.5', () {
      final prompt = promptService.build(
        userMessage: 'Why are my maize leaves yellow?',
        history: [],
        ragPassages: [],
        farmContext: const FarmContext(),
      );

      expect(prompt, contains('<|im_start|>system'));
      expect(prompt, contains('<|im_end|>'));
      expect(prompt, contains('<|im_start|>user'));
      expect(prompt, contains('Why are my maize leaves yellow?'));
      expect(prompt, contains('<|im_start|>assistant'));
    });

    test('injects farm context when provided', () {
      final prompt = promptService.build(
        userMessage: 'What should I spray?',
        history: [],
        ragPassages: [],
        farmContext: const FarmContext(
          region: 'Kenya - Nakuru',
          crop: 'Maize',
          season: 'Long Rains (Mar–May)',
        ),
      );

      expect(prompt, contains('Kenya - Nakuru'));
      expect(prompt, contains('Maize'));
    });

    test('injects RAG passages into prompt', () {
      final prompt = promptService.build(
        userMessage: 'How do I treat nitrogen deficiency?',
        history: [],
        ragPassages: [
          'crops: Maize Nutrient Deficiency\nApply CAN at 50 kg/ha immediately.',
        ],
        farmContext: const FarmContext(),
      );

      expect(prompt, contains('CAN at 50 kg/ha'));
      expect(prompt, contains('Relevant agricultural knowledge'));
    });

    test('uses Swahili system prompt when language is sw', () {
      final prompt = promptService.build(
        userMessage: 'Mahindi yangu yana magonjwa gani?',
        history: [],
        ragPassages: [],
        farmContext: const FarmContext(language: 'sw'),
      );

      expect(prompt, contains('Kiswahili'));
    });

    test('prompt stays within token budget with long history', () {
      final history = List.generate(
        50,
        (i) => ChatMessage(
          role: i.isEven ? MessageRole.user : MessageRole.assistant,
          content: 'Message $i: ${'word ' * 50}',
        ),
      );

      final prompt = promptService.build(
        userMessage: 'Current question',
        history: history,
        ragPassages: [],
        farmContext: const FarmContext(),
      );

      // Rough token count: prompt should be under context size
      final estimatedTokens = prompt.length ~/ 4;
      expect(estimatedTokens, lessThan(4096));
    });
  });
}
