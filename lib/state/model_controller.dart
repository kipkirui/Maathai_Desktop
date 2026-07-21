import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../services/model_service.dart';
import '../services/model_load_progress.dart';
import '../services/app_log.dart';
import '../services/llm_service.dart';

enum ModelStatus { notLoaded, loading, ready, generating, error }

class ModelController extends ChangeNotifier {
  final ModelService modelService;
  final LlmService _llmService = LlmService();

  ModelStatus _status = ModelStatus.notLoaded;
  String? _loadedModelPath;
  String? _errorMessage;
  ModelLoadProgress _loadProgress = ModelLoadProgress.idle;

  ModelLoadProgress get loadProgress => _loadProgress;

  // Sampler settings
  double temperature = AppConfig.defaultTemperature;
  int topK = AppConfig.defaultTopK;
  double topP = AppConfig.defaultTopP;
  double repeatPenalty = AppConfig.defaultRepeatPenalty;
  int maxTokens = AppConfig.defaultMaxTokens;
  int threads = AppConfig.defaultThreads;
  int contextSize = AppConfig.defaultContextSize;

  ModelStatus get status => _status;
  String? get loadedModelPath => _loadedModelPath;
  String? get errorMessage => _errorMessage;
  bool get isReady => _status == ModelStatus.ready;
  bool get isGenerating => _status == ModelStatus.generating;
  LlmService get llmService => _llmService;

  ModelController({required this.modelService}) {
    _restoreSettings();
    _autoLoadDefaultModel();
  }

  Future<void> _restoreSettings() async {
    final prefs = await SharedPreferences.getInstance();
    temperature = prefs.getDouble('temperature') ?? AppConfig.defaultTemperature;
    topK = prefs.getInt('top_k') ?? AppConfig.defaultTopK;
    topP = prefs.getDouble('top_p') ?? AppConfig.defaultTopP;
    repeatPenalty = prefs.getDouble('repeat_penalty') ?? AppConfig.defaultRepeatPenalty;
    maxTokens = prefs.getInt('max_tokens') ?? AppConfig.defaultMaxTokens;
    threads = prefs.getInt('threads') ?? AppConfig.defaultThreads;
    contextSize = prefs.getInt('context_size') ?? AppConfig.defaultContextSize;
    notifyListeners();
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('temperature', temperature);
    await prefs.setInt('top_k', topK);
    await prefs.setDouble('top_p', topP);
    await prefs.setDouble('repeat_penalty', repeatPenalty);
    await prefs.setInt('max_tokens', maxTokens);
    await prefs.setInt('threads', threads);
    await prefs.setInt('context_size', contextSize);
  }

  Future<void> _autoLoadDefaultModel() async {
    final models = await modelService.listModels();
    if (models.isEmpty) return;
    // Prefer the competition model, then first available
    final preferred = models.firstWhere(
      (m) => m.filename.contains('qwen2.5') || m.filename.contains('qwen'),
      orElse: () => models.first,
    );
    await loadModel(preferred.path);
  }

  Future<void> loadModel(String modelPath) async {
    final started = DateTime.now();
    AppLog.info('Model', 'loadModel: $modelPath');
    _status = ModelStatus.loading;
    _errorMessage = null;
    if (!_loadProgress.isActive) {
      _loadProgress = ModelLoadProgress(
        phase: ModelLoadPhase.loadingServer,
        filename: modelPath.split(Platform.pathSeparator).last,
      );
    } else {
      _loadProgress = ModelLoadProgress(
        phase: ModelLoadPhase.loadingServer,
        filename: _loadProgress.filename ?? modelPath.split(Platform.pathSeparator).last,
      );
    }
    notifyListeners();

    try {
      await _llmService.startServer(
        modelPath: modelPath,
        port: AppConfig.llamaServerPort,
        contextSize: contextSize,
        threads: threads,
        threadsBatch: AppConfig.defaultThreadsBatch,
        gpuLayers: AppConfig.defaultGpuLayers,
        batchSize: AppConfig.defaultBatchSize,
        ubatchSize: AppConfig.defaultUbatchSize,
        flashAttn: AppConfig.defaultFlashAttn,
        mlock: AppConfig.defaultMlock,
        processPrio: AppConfig.defaultProcessPrio,
        cacheTypeK: AppConfig.defaultCacheTypeK,
        cacheTypeV: AppConfig.defaultCacheTypeV,
      );
      _loadedModelPath = modelPath;
      _status = ModelStatus.ready;
      AppLog.timed('Model', 'loadModel ready', started);
    } catch (e) {
      _status = ModelStatus.error;
      _errorMessage = e.toString();
      AppLog.error('Model', 'loadModel failed', error: e);
    } finally {
      _loadProgress = ModelLoadProgress.idle;
    }
    notifyListeners();
  }

  /// Copy an external GGUF into the models folder, then load it.
  Future<void> importModel(String sourcePath) async {
    final filename = sourcePath.split(Platform.pathSeparator).last;
    _status = ModelStatus.loading;
    _errorMessage = null;
    _loadProgress = ModelLoadProgress(
      phase: ModelLoadPhase.copying,
      fraction: 0,
      filename: filename,
    );
    notifyListeners();

    try {
      final destPath = await modelService.importModelFile(
        sourcePath,
        onProgress: (progress, bytesCopied, totalBytes) {
          _loadProgress = ModelLoadProgress(
            phase: ModelLoadPhase.copying,
            fraction: progress.clamp(0.0, 1.0),
            bytesCopied: bytesCopied,
            totalBytes: totalBytes,
            filename: filename,
          );
          notifyListeners();
        },
      );
      await loadModel(destPath);
    } catch (e) {
      _status = ModelStatus.error;
      _errorMessage = e.toString();
      _loadProgress = ModelLoadProgress.idle;
      notifyListeners();
    }
  }

  Future<void> unloadModel() async {
    await _llmService.stopServer();
    _loadedModelPath = null;
    _status = ModelStatus.notLoaded;
    notifyListeners();
  }

  Stream<String> generateStream(String prompt) {
    _status = ModelStatus.generating;
    notifyListeners();

    final stream = _llmService.generateStream(
      prompt: prompt,
      maxTokens: maxTokens,
      temperature: temperature,
      topK: topK,
      topP: topP,
      repeatPenalty: repeatPenalty,
    );

    return stream.transform(
      StreamTransformer<String, String>.fromHandlers(
        handleDone: (sink) {
          _status = ModelStatus.ready;
          notifyListeners();
          sink.close();
        },
        handleError: (error, stack, sink) {
          _status = ModelStatus.error;
          _errorMessage = error.toString();
          notifyListeners();
          sink.addError(error, stack);
        },
      ),
    );
  }

  Future<void> cancelGeneration() async {
    await _llmService.cancelGeneration();
    _status = ModelStatus.ready;
    notifyListeners();
  }

  @override
  void dispose() {
    _llmService.stopServer();
    super.dispose();
  }
}
