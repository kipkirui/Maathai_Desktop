import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import 'app_log.dart';

/// Manages the llama-server subprocess and streams inference results.
///
/// The app spawns `llama-server` as a child process and communicates
/// with its OpenAI-compatible HTTP API on localhost. This approach:
/// - Uses the exact same llama.cpp binary that the ADTC profiler evaluates
/// - Works cross-platform (Linux, Windows, macOS) with one code path
/// - Supports token streaming via Server-Sent Events
class LlmService {
  Process? _serverProcess;
  int _port = AppConfig.llamaServerPort;
  bool _serverReady = false;
  StreamSubscription<String>? _serverLogSub;

  bool get isServerRunning => _serverProcess != null && _serverReady;

  String get _baseUrl => 'http://${AppConfig.llamaServerHost}:$_port';

  /// Starts `llama-server` with the given model.
  /// Waits up to [timeoutSeconds] for the server to become ready.
  Future<void> startServer({
    required String modelPath,
    int port = AppConfig.llamaServerPort,
    int contextSize = AppConfig.defaultContextSize,
    int threads = AppConfig.defaultThreads,
    int threadsBatch = AppConfig.defaultThreadsBatch,
    int gpuLayers = AppConfig.defaultGpuLayers,
    int batchSize = AppConfig.defaultBatchSize,
    int ubatchSize = AppConfig.defaultUbatchSize,
    bool flashAttn = AppConfig.defaultFlashAttn,
    bool mlock = AppConfig.defaultMlock,
    int processPrio = AppConfig.defaultProcessPrio,
    String cacheTypeK = AppConfig.defaultCacheTypeK,
    String cacheTypeV = AppConfig.defaultCacheTypeV,
    int timeoutSeconds = 60,
  }) async {
    await stopServer();

    _port = port;
    _serverReady = false;

    // Find the llama-server binary (PATH or bundled)
    final binary = await _findLlamaBinary();
    if (binary == null) {
      throw LlmServiceException(
        'llama-server not found.\n'
        'Install llama.cpp and ensure llama-server is on your PATH.\n'
        'See: https://github.com/ggml-org/llama.cpp',
      );
    }

    final args = <String>[
      '--model', modelPath,
      '--host', AppConfig.llamaServerHost,
      '--port', port.toString(),
      '--ctx-size', contextSize.toString(),
      '--threads', threads.toString(),
      '--threads-batch', threadsBatch.toString(),
      '--n-gpu-layers', gpuLayers.toString(),
      '--batch-size', batchSize.toString(),
      '--ubatch-size', ubatchSize.toString(),
      '--flash-attn', flashAttn ? 'on' : 'off',
      '--cache-type-k', cacheTypeK,
      '--cache-type-v', cacheTypeV,
      '--prio', processPrio.toString(),
      // mmap left enabled (faster TPS than --no-mmap in sweeps)
      if (mlock) '--mlock',
      '--log-disable',
    ];

    // Cap BLAS/OpenMP to the same thread budget so they don't oversubscribe
    // the 4 vCPUs the ADTC profiler / laptop profile expose.
    final env = <String, String>{
      ...Platform.environment,
      'OMP_NUM_THREADS': threads.toString(),
      'OPENBLAS_NUM_THREADS': threads.toString(),
      'GGML_BLAS_NUM_THREADS': threads.toString(),
      'MKL_NUM_THREADS': threads.toString(),
    };

    _serverProcess = await Process.start(binary, args, environment: env);
    AppLog.info(
      'LlmService',
      'Started llama-server: $binary '
      '(t=$threads tb=$threadsBatch b=$batchSize ub=$ubatchSize '
      'fa=${flashAttn ? 'on' : 'off'} mlock=$mlock prio=$processPrio)',
    );

    // Forward server stderr to console in debug mode
    _serverLogSub = _serverProcess!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty) return;
      AppLog.info('llama-server', line);
    });

    // Poll until server accepts connections
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    final readyStarted = DateTime.now();
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (await _pingServer()) {
        _serverReady = true;
        AppLog.timed('LlmService', 'llama-server ready', readyStarted);
        return;
      }
      // Check if process died
      // ignore: invalid_use_of_visible_for_testing_member
      if (_serverProcess == null) break;
    }

    throw LlmServiceException(
      'llama-server did not become ready within ${timeoutSeconds}s.\n'
      'Check that the model path is valid: $modelPath',
    );
  }

  Future<bool> _pingServer() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _findLlamaBinary() async {
    final localNames = Platform.isWindows
        ? ['llama-server.exe', 'llama-server']
        : ['llama-server'];

    // 1. Bundled with repo (scripts/install_llama_server_windows.ps1)
    for (final name in localNames) {
      final bundled = p.join(Directory.current.path, 'tools', 'llama', name);
      if (await File(bundled).exists()) return bundled;
    }

    // 2. Next to Flutter executable (release builds)
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      for (final name in localNames) {
        final nearExe = p.join(exeDir, 'tools', 'llama', name);
        if (await File(nearExe).exists()) return nearExe;
      }
    } catch (_) {}

    // 3. System PATH
    if (Platform.isWindows) {
      try {
        final result = await Process.run('where', [localNames.first]);
        if (result.exitCode == 0) {
          return (result.stdout as String).trim().split('\n').first.trim();
        }
      } catch (_) {}
    } else {
      for (final name in localNames) {
        try {
          final result = await Process.run('which', [name]);
          if (result.exitCode == 0) {
            return (result.stdout as String).trim();
          }
        } catch (_) {}
      }
    }

    // 4. Relative paths (Linux dev / competition layout)
    for (final name in localNames) {
      final relative = p.join('llama.cpp', 'build', 'bin', name);
      if (await File(relative).exists()) return relative;
    }

    return null;
  }

  /// Streams tokens from llama-server via Server-Sent Events.
  Stream<String> generateStream({
    required String prompt,
    int maxTokens = AppConfig.defaultMaxTokens,
    double temperature = AppConfig.defaultTemperature,
    int topK = AppConfig.defaultTopK,
    double topP = AppConfig.defaultTopP,
    double repeatPenalty = AppConfig.defaultRepeatPenalty,
  }) async* {
    if (!isServerRunning) {
      throw LlmServiceException('Model server is not running. Load a model first.');
    }

    final body = jsonEncode({
      'prompt': prompt,
      'n_predict': maxTokens,
      'temperature': temperature,
      'top_k': topK,
      'top_p': topP,
      'repeat_penalty': repeatPenalty,
      'stream': true,
      'stop': ['\n### Human:', '\n### User:', '<|im_end|>', '</s>'],
    });

    final request = http.Request('POST', Uri.parse('$_baseUrl/completion'));
    request.headers['Content-Type'] = 'application/json';
    request.body = body;

    http.StreamedResponse? response;
    final requestStarted = DateTime.now();
    AppLog.info('LlmService', 'POST /completion (prompt ${prompt.length} chars)');
    try {
      response = await request.send().timeout(const Duration(minutes: 5));
    } catch (e) {
      AppLog.error('LlmService', 'Failed to connect to llama-server', error: e);
      throw LlmServiceException('Failed to connect to llama-server: $e');
    }

    if (response.statusCode != 200) {
      final errorBody = await response.stream.bytesToString();
      AppLog.error('LlmService', 'HTTP ${response.statusCode}: $errorBody');
      throw LlmServiceException(
        'llama-server returned ${response.statusCode}: $errorBody',
      );
    }

    var firstTokenLogged = false;
    var tokenCount = 0;
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      // SSE format: "data: {...}\n\n"
      for (final line in chunk.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final jsonStr = trimmed.substring(5).trim();
        if (jsonStr.isEmpty || jsonStr == '[DONE]') continue;

        try {
          final Map<String, dynamic> data = jsonDecode(jsonStr);
          final token = data['content'] as String? ?? '';
          final stop = data['stop'] as bool? ?? false;
          if (token.isNotEmpty) {
            if (!firstTokenLogged) {
              firstTokenLogged = true;
              AppLog.timed('LlmService', 'first token', requestStarted);
            }
            tokenCount++;
            yield token;
          }
          if (stop) {
            AppLog.info('LlmService', 'stream done ($tokenCount tokens)');
            return;
          }
        } catch (_) {
          continue;
        }
      }
    }
  }

  Future<void> cancelGeneration() async {
    // llama-server: interrupt by sending stop signal or just let it drain
    try {
      await http.post(
        Uri.parse('$_baseUrl/cancel'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> stopServer() async {
    _serverReady = false;
    await _serverLogSub?.cancel();
    _serverLogSub = null;
    final process = _serverProcess;
    _serverProcess = null;
    if (process != null) {
      AppLog.info('LlmService', 'Stopping llama-server');
      if (Platform.isWindows) {
        process.kill();
      } else {
        process.kill(ProcessSignal.sigterm);
      }
    }
  }
}

class LlmServiceException implements Exception {
  final String message;
  LlmServiceException(this.message);

  @override
  String toString() => 'LlmServiceException: $message';
}
