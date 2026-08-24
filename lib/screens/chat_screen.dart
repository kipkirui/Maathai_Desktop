import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/chat_controller.dart';
import '../state/model_controller.dart';
import '../state/translation_controller.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/context_panel.dart';
import '../widgets/model_status_bar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  final FocusNode _keyboardFocus = FocusNode();
  bool _contextPanelOpen = true;
  ChatController? _chatController;
  DateTime? _lastScrollAt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.read<ChatController>();
    if (!identical(_chatController, next)) {
      _chatController?.removeListener(_onChatChanged);
      _chatController = next;
      _chatController!.addListener(_onChatChanged);
    }
  }

  @override
  void dispose() {
    _chatController?.removeListener(_onChatChanged);
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _onChatChanged() {
    if (!mounted) return;
    final now = DateTime.now();
    if (_lastScrollAt != null &&
        now.difference(_lastScrollAt!) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastScrollAt = now;
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      // jumpTo avoids animated layout churn during streaming.
      _scrollController.jumpTo(target);
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    final chatController = context.read<ChatController>();
    _inputController.clear();
    _inputFocus.requestFocus();

    await chatController.sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chatController = context.watch<ChatController>();
    final modelStatus = context.select<ModelController, ModelStatus>(
      (mc) => mc.status,
    );
    final isGenerating = context.select<ModelController, bool>(
      (mc) => mc.isGenerating,
    );
    final t = context.watch<TranslationController>();

    final messages = chatController.messages;

    return Row(
      children: [
        // Main chat area
        Expanded(
          child: Column(
            children: [
              ModelStatusBar(status: modelStatus),
              // Chat messages
              Expanded(
                child: messages.isEmpty
                    ? _buildEmptyState(t)
                    : ListView.builder(
                        controller: _scrollController,
                        addAutomaticKeepAlives: false,
                        addRepaintBoundaries: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (ctx, i) {
                          final msg = messages[i];
                          return RepaintBoundary(
                            child: ChatBubble(
                              key: ValueKey(msg.id),
                              message: msg,
                            ),
                          );
                        },
                      ),
              ),
              // Input area
              _buildInputArea(context, isGenerating, t),
            ],
          ),
        ),
        // Context panel (collapsible)
        if (_contextPanelOpen) ...[
          const VerticalDivider(width: 1),
          SizedBox(
            width: 260,
            child: ContextPanel(
              onClose: () => setState(() => _contextPanelOpen = false),
            ),
          ),
        ],
        if (!_contextPanelOpen)
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Open context panel',
            onPressed: () => setState(() => _contextPanelOpen = true),
          ),
      ],
    );
  }

  Widget _buildEmptyState(TranslationController t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.eco, size: 72, color: Color(0xFF2E7D32)),
          const SizedBox(height: 16),
          Text(
            t.t('chat_empty_title'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            t.t('chat_empty_subtitle'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 32),
          // Quick starter questions
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              t.t('quick_q1'),
              t.t('quick_q2'),
              t.t('quick_q3'),
              t.t('quick_q4'),
            ].map((question) => _StarterChip(
                  label: question,
                  onTap: () {
                    _inputController.text = question;
                    _sendMessage();
                  },
                )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(
    BuildContext context,
    bool isGenerating,
    TranslationController t,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Clear chat
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: t.t('clear_chat'),
            onPressed: () => context.read<ChatController>().clearChat(),
          ),
          const SizedBox(width: 8),
          // Text input
          Expanded(
            child: KeyboardListener(
              focusNode: _keyboardFocus,
              onKeyEvent: (event) {
                if (event is KeyDownEvent) {
                  final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter;
                  final isShift = HardwareKeyboard.instance.isShiftPressed;
                  final isCtrl = HardwareKeyboard.instance.isControlPressed;
                  if (isEnter && !isShift && !isGenerating) {
                    _sendMessage();
                  } else if (isEnter && isCtrl && !isGenerating) {
                    _sendMessage();
                  }
                }
              },
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocus,
                maxLines: 5,
                minLines: 1,
                onSubmitted: (_) {
                  if (!isGenerating) _sendMessage();
                },
                decoration: InputDecoration(
                  hintText: t.t('chat_placeholder'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                enabled: !isGenerating,
                textInputAction: TextInputAction.send,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send / Stop button
          if (isGenerating)
            FilledButton.icon(
              onPressed: () => context.read<ChatController>().cancelGeneration(),
              icon: const Icon(Icons.stop),
              label: Text(t.t('stop')),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            )
          else
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _inputController,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                return FilledButton.icon(
                  onPressed: hasText ? _sendMessage : null,
                  icon: const Icon(Icons.send),
                  label: Text(t.t('send')),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _StarterChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _StarterChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
      onPressed: onTap,
      side: BorderSide(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
      ),
    );
  }
}
