import '../state/chat_controller.dart';
import '../config/app_config.dart';

/// Assembles the full prompt string for llama-server.
///
/// Token budget management:
///   system prompt   ≤ 25% of context
///   RAG passages    ≤ 30% of context
///   history         ≤ 35% of context (oldest messages dropped first)
///   current user    remaining
class PromptService {
  static const _systemPromptEn = '''You are Maathai, an offline AI agriculture advisor for smallholder farmers in Africa. You have deep expertise in:
- East and West African crops, varieties, and farming systems
- Pest and disease identification, prevention, and treatment
- Soil health, fertilizers, and organic farming practices
- Planting calendars and seasonal timing
- Post-harvest handling and market pricing

Always give practical, actionable advice suited to smallholder farmers with limited resources. Cite specific inputs, dosages, and timing. When a treatment is needed, provide both chemical and organic options where available.

When context about the farm (region, crop, season) is provided, tailor your advice to those specific conditions.''';

  static const _systemPromptSw = '''Wewe ni Maathai, mshauri wa kilimo wa AI ambaye anafanya kazi bila mtandao kwa wakulima wadogo Afrika. Una ujuzi mkubwa katika:
- Mazao ya Afrika Mashariki na Magharibi, aina, na mifumo ya kilimo
- Utambuzi, kuzuia, na kutibu wadudu na magonjwa
- Afya ya udongo, mbolea, na kilimo-hai
- Kalenda za upanzi na muda wa msimu
- Utunzaji baada ya mavuno na bei za masoko

Daima toa ushauri wa vitendo unaofaa kwa wakulima wadogo wenye rasilimali chache. Taja pembejeo mahususi, kipimo, na wakati. Unapotoa ushauri wa matibabu, toa chaguzi za kemikali na za kikaboni inapowezekana.

Jibu kwa Kiswahili safi na rahisi kuelewa.''';

  /// Approximate tokens from character count (1 token ≈ 4 chars for English).
  int _estimateTokens(String text) => (text.length / 4).ceil();

  String build({
    required String userMessage,
    required List<ChatMessage> history,
    required List<String> ragPassages,
    required FarmContext farmContext,
  }) {
    final isSwahili = farmContext.language == 'sw';
    final systemPrompt = isSwahili ? _systemPromptSw : _systemPromptEn;

    // Build context section
    final contextLines = <String>[];
    if (farmContext.region != null) contextLines.add('Region: ${farmContext.region}');
    if (farmContext.crop != null) contextLines.add('Active crop: ${farmContext.crop}');
    if (farmContext.season != null) contextLines.add('Season: ${farmContext.season}');

    final contextSection = contextLines.isNotEmpty
        ? '\n\nFarm context:\n${contextLines.join('\n')}'
        : '';

    // RAG knowledge passages
    final ragSection = ragPassages.isNotEmpty
        ? '\n\nRelevant agricultural knowledge:\n${ragPassages.map((p) => '---\n$p').join('\n')}\n---'
        : '';

    // Estimate token budgets
    final totalBudget = AppConfig.defaultContextSize;
    final systemTokens = _estimateTokens(systemPrompt + contextSection + ragSection);
    final userTokens = _estimateTokens(userMessage);
    final reservedForGeneration = AppConfig.defaultMaxTokens;
    final historyBudget = totalBudget - systemTokens - userTokens - reservedForGeneration;

    // Build history within budget (drop oldest first)
    final historyParts = <String>[];
    int usedTokens = 0;
    // Exclude the current user message and streaming assistant msg
    final relevantHistory = history
        .where((m) =>
            m.role != MessageRole.system &&
            !m.isStreaming &&
            m.content.isNotEmpty)
        .toList();

    for (int i = relevantHistory.length - 2; i >= 0; i--) {
      final msg = relevantHistory[i];
      final roleLabel = msg.role == MessageRole.user ? 'Human' : 'Assistant';
      final line = '$roleLabel: ${msg.content}';
      final tokens = _estimateTokens(line);
      if (usedTokens + tokens > historyBudget) break;
      historyParts.insert(0, line);
      usedTokens += tokens;
    }

    final historySection = historyParts.isNotEmpty
        ? '\n\n${historyParts.join('\n')}'
        : '';

    // Assemble full prompt in ChatML format (compatible with Qwen2.5)
    final buffer = StringBuffer();
    buffer.write('<|im_start|>system\n');
    buffer.write(systemPrompt);
    buffer.write(contextSection);
    buffer.write(ragSection);
    buffer.write('\n<|im_end|>\n');

    if (historySection.isNotEmpty) {
      // Reformat history as ChatML turns
      for (final line in historyParts) {
        if (line.startsWith('Human:')) {
          buffer.write('<|im_start|>user\n${line.substring(7).trim()}\n<|im_end|>\n');
        } else if (line.startsWith('Assistant:')) {
          buffer.write('<|im_start|>assistant\n${line.substring(10).trim()}\n<|im_end|>\n');
        }
      }
    }

    buffer.write('<|im_start|>user\n$userMessage\n<|im_end|>\n');
    buffer.write('<|im_start|>assistant\n');

    return buffer.toString();
  }
}
