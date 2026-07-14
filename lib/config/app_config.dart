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

  // Model defaults — aligned with llama.cpp / adtc-profiler llama-bench (-t 4, -p 512 -n 128)
  static const int defaultContextSize = 4096;
  static const int defaultThreads = 4; // ADTC reference laptop: 4 vCPU; avoid HT oversubscription
  static const int defaultBatchSize = 2048; // llama-server default; was 512 (under-batched)
  static const int defaultUbatchSize = 512; // physical micro-batch (llama-server default)
  static const int defaultGpuLayers = 0; // CPU-only for competition hardware

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
