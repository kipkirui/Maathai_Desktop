import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../services/chat_storage_service.dart';
import '../services/app_log.dart';
import '../services/rag_service.dart';
import '../services/prompt_service.dart';
import '../state/model_controller.dart';

enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isStreaming;
  final List<String> ragPassages;

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isStreaming = false,
    this.ragPassages = const [],
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? content,
    bool? isStreaming,
    List<String>? ragPassages,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      ragPassages: ragPassages ?? this.ragPassages,
    );
  }
}

class FarmContext {
  final String? region;
  final String? crop;
  final String? season;
  final String? language;

  const FarmContext({
    this.region,
    this.crop,
    this.season,
    this.language = 'en',
  });

  FarmContext copyWith({
    String? region,
    String? crop,
    String? season,
    String? language,
  }) {
    return FarmContext(
      region: region ?? this.region,
      crop: crop ?? this.crop,
      season: season ?? this.season,
      language: language ?? this.language,
    );
  }

  bool get hasContext => region != null || crop != null || season != null;
}

class ChatController extends ChangeNotifier {
  final RagService ragService;
  final ModelController modelController;
  final ChatStorageService storage;
  final PromptService _promptService = PromptService();

  final List<ChatMessage> _messages = [];
  FarmContext _farmContext = const FarmContext();
  StreamSubscription<String>? _activeGeneration;
  bool _isCancelled = false;
  bool _restored = false;
  DateTime? _lastUiNotify;
  Timer? _notifyFlushTimer;

  static const _notifyInterval = Duration(milliseconds: 80);

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  FarmContext get farmContext => _farmContext;
  bool get isGenerating => modelController.isGenerating;
  bool get isRestored => _restored;

  ChatController({
    required this.ragService,
    required this.modelController,
    required this.storage,
  });

  Future<void> restoreFromStorage() async {
    _farmContext = await storage.loadFarmContext();
    final saved = await storage.loadMessages();
    _messages
      ..clear()
      ..addAll(saved);
    _restored = true;
    notifyListeners();
  }

  void updateFarmContext(FarmContext context) {
    _farmContext = context;
    unawaited(storage.saveFarmContext(context));
    notifyListeners();
  }

  Future<void> sendMessage(String userText) async {
    if (userText.trim().isEmpty) return;
    if (!modelController.isReady) {
      AppLog.warn('Chat', 'sendMessage ignored — model not ready');
      return;
    }

    final started = DateTime.now();
    AppLog.info('Chat', 'sendMessage: "${userText.trim().substring(0, userText.trim().length.clamp(0, 80))}"');

    final userMsg = ChatMessage(
      role: MessageRole.user,
      content: userText.trim(),
    );
    _messages.add(userMsg);
    await storage.saveMessage(userMsg);
    notifyListeners();

    final ragStarted = DateTime.now();
    final passages = await ragService.retrieve(
      query: userText,
      topK: 3,
      language: _farmContext.language ?? 'en',
    );
    AppLog.timed('Chat', 'RAG retrieve (${passages.length} passages)', ragStarted);

    final promptStarted = DateTime.now();
    final prompt = _promptService.build(
      userMessage: userText,
      history: _messages.where((m) => !m.isStreaming).toList(),
      ragPassages: passages,
      farmContext: _farmContext,
    );
    AppLog.timed('Chat', 'prompt built (${prompt.length} chars)', promptStarted);

    final assistantMsg = ChatMessage(
      role: MessageRole.assistant,
      content: '',
      isStreaming: true,
      ragPassages: passages,
    );
    _messages.add(assistantMsg);
    notifyListeners();
    AppLog.info('Chat', 'generation started');

    _isCancelled = false;
    final buffer = StringBuffer();
    final assistantId = assistantMsg.id;

    _activeGeneration = modelController.generateStream(prompt).listen(
      (token) {
        if (_isCancelled) return;
        buffer.write(token);
        _updateAssistantMessage(
          assistantId,
          buffer.toString(),
          isStreaming: true,
          passages: passages,
        );
      },
      onDone: () async {
        _flushNotifyTimer();
        AppLog.timed('Chat', 'generation complete', started);
        final finalMsg = _updateAssistantMessage(
          assistantId,
          buffer.toString(),
          isStreaming: false,
          passages: passages,
          forceNotify: true,
        );
        if (finalMsg != null) {
          await storage.saveMessage(finalMsg);
        }
      },
      onError: (error) async {
        _flushNotifyTimer();
        AppLog.error('Chat', 'generation error', error: error);
        final content = buffer.isNotEmpty
            ? '${buffer.toString()}\n\n_[Generation interrupted]_'
            : '_Error: ${error.toString()}_';
        final finalMsg = _updateAssistantMessage(
          assistantId,
          content,
          isStreaming: false,
          passages: passages,
          forceNotify: true,
        );
        if (finalMsg != null) {
          await storage.saveMessage(finalMsg);
        }
      },
    );
  }

  ChatMessage? _updateAssistantMessage(
    String id,
    String content, {
    required bool isStreaming,
    required List<String> passages,
    bool forceNotify = false,
  }) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx < 0) return null;

    final updated = _messages[idx].copyWith(
      content: content,
      isStreaming: isStreaming,
      ragPassages: passages,
    );
    _messages[idx] = updated;

    if (forceNotify || !isStreaming) {
      _flushNotifyTimer();
      notifyListeners();
    } else {
      _scheduleThrottledNotify();
    }
    return updated;
  }

  void _scheduleThrottledNotify() {
    final now = DateTime.now();
    if (_lastUiNotify == null ||
        now.difference(_lastUiNotify!) >= _notifyInterval) {
      _lastUiNotify = now;
      notifyListeners();
      return;
    }

    _notifyFlushTimer ??= Timer(_notifyInterval, () {
      _notifyFlushTimer = null;
      _lastUiNotify = DateTime.now();
      notifyListeners();
    });
  }

  void _flushNotifyTimer() {
    _notifyFlushTimer?.cancel();
    _notifyFlushTimer = null;
    _lastUiNotify = null;
  }

  Future<void> cancelGeneration() async {
    _isCancelled = true;
    await _activeGeneration?.cancel();
    await modelController.cancelGeneration();
    _flushNotifyTimer();

    final idx = _messages.lastIndexWhere((m) => m.isStreaming);
    if (idx >= 0) {
      final updated = _messages[idx].copyWith(isStreaming: false);
      _messages[idx] = updated;
      if (updated.content.isNotEmpty) {
        await storage.saveMessage(updated);
      } else {
        _messages.removeAt(idx);
        await storage.deleteMessage(updated.id);
      }
      notifyListeners();
    }
  }

  Future<void> clearChat() async {
    _messages.clear();
    await storage.clearMessages();
    notifyListeners();
  }

  String exportAsMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('# Maathai Desktop — Conversation Export\n');
    buffer.writeln(
      '**Context:** ${_farmContext.region ?? "—"} · '
      '${_farmContext.crop ?? "—"} · ${_farmContext.season ?? "—"}\n',
    );
    buffer.writeln('---\n');
    for (final msg in _messages) {
      if (msg.role == MessageRole.user) {
        buffer.writeln('**You:** ${msg.content}\n');
      } else if (msg.role == MessageRole.assistant) {
        buffer.writeln('**Maathai AI:**\n\n${msg.content}\n');
        buffer.writeln('---\n');
      }
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    _flushNotifyTimer();
    _activeGeneration?.cancel();
    super.dispose();
  }
}
