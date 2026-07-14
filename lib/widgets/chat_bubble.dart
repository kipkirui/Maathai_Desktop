import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../state/chat_controller.dart';
import '../utils/platform_ui.dart';
import 'typing_indicator.dart';

class ChatBubble extends StatefulWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  State<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<ChatBubble> {
  bool _showRagSources = false;
  bool _thinkExpanded = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final isUser = msg.role == MessageRole.user;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        top: 8,
        bottom: 8,
        left: isUser ? 64 : 0,
        right: isUser ? 0 : 64,
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Role label
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
            child: Text(
              isUser ? 'You' : 'Maathai AI',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Bubble
          Container(
            decoration: BoxDecoration(
              color: isUser
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16).copyWith(
                bottomRight: isUser ? const Radius.circular(4) : null,
                bottomLeft: !isUser ? const Radius.circular(4) : null,
              ),
              border: Border.all(
                color: isUser
                    ? theme.colorScheme.primary.withValues(alpha: 0.2)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: isUser
                ? Text(msg.content)
                : _buildAssistantContent(msg, theme),
          ),
          // Action row (assistant only)
          if (!isUser && !msg.isStreaming)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Row(
                children: [
                  _ActionButton(
                    icon: Icons.copy_outlined,
                    tooltip: 'Copy',
                    onTap: () =>
                        Clipboard.setData(ClipboardData(text: msg.content)),
                  ),
                  if (msg.ragPassages.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _ActionButton(
                      icon: Icons.info_outline,
                      tooltip: 'View sources',
                      onTap: () =>
                          setState(() => _showRagSources = !_showRagSources),
                    ),
                  ],
                ],
              ),
            ),
          // RAG sources (expandable)
          if (_showRagSources && msg.ragPassages.isNotEmpty)
            _RagSourcesPanel(passages: msg.ragPassages),
        ],
      ),
    );
  }

  Widget _buildAssistantContent(ChatMessage msg, ThemeData theme) {
    if (msg.isStreaming) {
      if (msg.content.isEmpty) {
        return const TypingIndicator();
      }
      // Plain text while streaming — avoids heavy a11y nodes on Windows.
      return Text(
        msg.content,
        style: theme.textTheme.bodyMedium,
      );
    }

    // Parse thinking blocks in completed responses
    final content = msg.content;
    final thinkRegex = RegExp(r'<think>(.*?)</think>', dotAll: true);
    final thinkMatch = thinkRegex.firstMatch(content);

    if (thinkMatch != null) {
      final thinkContent = thinkMatch.group(1)?.trim() ?? '';
      final mainContent = content
          .replaceFirst(thinkRegex, '')
          .trim();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Collapsible thinking block
          GestureDetector(
            onTap: () => setState(() => _thinkExpanded = !_thinkExpanded),
            child: Row(
              children: [
                Icon(
                  _thinkExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  'Thinking...',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          if (_thinkExpanded)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                thinkContent,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (mainContent.isNotEmpty)
            MarkdownBody(
              data: mainContent,
              selectable: !useWindowsA11yWorkaround,
            ),
        ],
      );
    }

    return MarkdownBody(
      data: content,
      selectable: !useWindowsA11yWorkaround,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _RagSourcesPanel extends StatelessWidget {
  final List<String> passages;

  const _RagSourcesPanel({required this.passages});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiaryContainer,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Knowledge sources used:',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          ...passages.map((p) {
            final firstLine = p.split('\n').first;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '• $firstLine',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            );
          }),
        ],
      ),
    );
  }
}
