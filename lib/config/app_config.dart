class AppConfig {
  AppConfig._();

  static const String appName = 'Maathai Desktop';
  static const String appVersion = '1.0.0';
  static const String appDescription =
      'Offline AI agriculture advisor for the laptop Africa already has.';

  // llama-server default settings
  static const int llamaServerPort = 8080;
  static const String llamaServerHost = 'localhost';
  static const String llamaServerUrl = 'http://$llamaServerHost:$llamaServerPort';

  // Model defaults — tuned via scripts/benchmark_*_wsl.sh against Qwen2.5-3B Q4_K_M
  // ADTC profiler uses llama-bench -t 4 -p 512 -n 128; keep threads at 4 for eval parity.
  static const int defaultContextSize = 4096;
  static const int defaultThreads = 4; // ADTC 4 vCPU; >4 hurts TPS on this class of laptop
  static const int defaultThreadsBatch = 4; // match prompt/batch processing to gen threads
  static const int defaultBatchSize = 2048; // best TPS in sweep (512→6.6, 1024→7.5, 2048→8–9)
  static const int defaultUbatchSize = 512; // llama.cpp physical micro-batch default
  static const int defaultGpuLayers = 0; // CPU-only for competition hardware
  static const bool defaultFlashAttn = true; // +~15% gen TPS vs flash-attn off in WSL sweep
  static const bool defaultMlock = true; // keep weights resident; peak RSS still ~3.3 GB ≪ 7 GB
  static const int defaultProcessPrio = 1; // medium; improves scheduling under UI load
  // KV cache: f16 is fastest here; q8_0 saves RAM (~same TPS). Keep f16 for Sperf.
  static const String defaultCacheTypeK = 'f16';
  static const String defaultCacheTypeV = 'f16';

  // Generation defaults
  static const double defaultTemperature = 0.7;
  static const int defaultTopK = 40;
  static const double defaultTopP = 0.95;
  static const double defaultRepeatPenalty = 1.1;
  static const int defaultMaxTokens = 512;

  // RAG settings
  static const int ragTopK = 3;
  static const int ragMaxPassageTokens = 400;
  static const double ragMinScore = 0.05;

  // Context token budget (fraction of context window)
  static const double systemPromptBudget = 0.25;
  static const double ragBudget = 0.30;
  static const double historyBudget = 0.35;

  // Competition model
  static const String defaultModelFilename = 'qwen2.5-3b-instruct-q4_k_m.gguf';

  // Supported languages
  static const List<Map<String, String>> supportedLanguages = [
    {'code': 'en', 'name': 'English', 'nativeName': 'English'},
    {'code': 'sw', 'name': 'Swahili', 'nativeName': 'Kiswahili'},
  ];
}
