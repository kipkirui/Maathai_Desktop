import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../config/app_config.dart';

class ModelInfo {
  final String path;
  final String filename;
  final int sizeBytes;
  final DateTime modified;

  ModelInfo({
    required this.path,
    required this.filename,
    required this.sizeBytes,
    required this.modified,
  });

  String get sizeLabel {
    if (sizeBytes > 1024 * 1024 * 1024) {
      return '${(sizeBytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(0)} MB';
  }

  bool get isDefaultCompetitionModel =>
      filename.contains('qwen2.5') || filename.contains('qwen');
}

class ModelService {
  late Directory _modelsDir;

  Future<void> initialize() async {
    // Primary: ./model/ relative to executable (competition path)
    // Fallback: app support directory
    final exe = File(Platform.resolvedExecutable);
    final repoRoot = exe.parent.parent; // typical flutter linux build layout
    final competitionModelDir = Directory(p.join(repoRoot.path, 'model'));

    if (await competitionModelDir.exists()) {
      _modelsDir = competitionModelDir;
    } else {
      final appDir = await getApplicationSupportDirectory();
      _modelsDir = Directory(p.join(appDir.path, 'models'));
      await _modelsDir.create(recursive: true);
    }

    // Also check the project root ./model directory
    final localModelDir = Directory(p.join(Directory.current.path, 'model'));
    if (await localModelDir.exists()) {
      _modelsDir = localModelDir;
    }
  }

  Directory get modelsDir => _modelsDir;

  Future<List<ModelInfo>> listModels() async {
    final models = <ModelInfo>[];

    // Scan primary models directory
    await _scanDirectory(_modelsDir, models);

    // Also scan the current directory (development convenience)
    if (_modelsDir.path != Directory.current.path) {
      final localModel = Directory(
        p.join(Directory.current.path, 'model'),
      );
      if (await localModel.exists() && localModel.path != _modelsDir.path) {
        await _scanDirectory(localModel, models);
      }
    }

    // Sort: competition model first, then by size descending
    models.sort((a, b) {
      if (a.isDefaultCompetitionModel) return -1;
      if (b.isDefaultCompetitionModel) return 1;
      return b.sizeBytes.compareTo(a.sizeBytes);
    });

    return models;
  }

  Future<void> _scanDirectory(Directory dir, List<ModelInfo> models) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.gguf')) {
        final stat = await entity.stat();
        models.add(ModelInfo(
          path: entity.path,
          filename: p.basename(entity.path),
          sizeBytes: stat.size,
          modified: stat.modified,
        ));
      }
    }
  }

  Future<ModelInfo?> findDefaultModel() async {
    final models = await listModels();
    if (models.isEmpty) return null;
    return models.firstWhere(
      (m) => m.filename == AppConfig.defaultModelFilename,
      orElse: () => models.first,
    );
  }

  /// Returns the path where the competition model should be placed.
  String get competitionModelPath =>
      p.join(_modelsDir.path, AppConfig.defaultModelFilename);

  bool get competitionModelExists =>
      File(competitionModelPath).existsSync();

  /// Copies a GGUF into the models directory with byte-level progress updates.
  /// Returns the destination path (unchanged if [sourcePath] is already in place).
  Future<String> importModelFile(
    String sourcePath, {
    void Function(double progress, int bytesCopied, int totalBytes)? onProgress,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('Model file not found', sourcePath);
    }

    await _modelsDir.create(recursive: true);
    final destPath = p.join(_modelsDir.path, p.basename(sourcePath));
    final dest = File(destPath);

    if (p.normalize(source.absolute.path) == p.normalize(dest.absolute.path)) {
      onProgress?.call(1.0, await source.length(), await source.length());
      return destPath;
    }

    final totalBytes = await source.length();
    if (totalBytes == 0) {
      throw FileSystemException('Model file is empty', sourcePath);
    }

    const chunkSize = 1024 * 1024;
    var bytesCopied = 0;
    final sink = dest.openWrite();

    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
        bytesCopied += chunk.length;
        onProgress?.call(bytesCopied / totalBytes, bytesCopied, totalBytes);
      }
      await sink.flush();
    } catch (e) {
      await sink.close();
      if (await dest.exists()) {
        await dest.delete();
      }
      rethrow;
    }
    await sink.close();

    onProgress?.call(1.0, totalBytes, totalBytes);
    return destPath;
  }
}
