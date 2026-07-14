/// Progress while copying or loading a GGUF model file.
enum ModelLoadPhase { idle, copying, loadingServer }

class ModelLoadProgress {
  final ModelLoadPhase phase;
  final double? fraction;
  final int bytesCopied;
  final int totalBytes;
  final String? filename;

  const ModelLoadProgress({
    this.phase = ModelLoadPhase.idle,
    this.fraction,
    this.bytesCopied = 0,
    this.totalBytes = 0,
    this.filename,
  });

  bool get isActive => phase != ModelLoadPhase.idle;

  static const idle = ModelLoadProgress();
}

String formatByteProgress(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
}
