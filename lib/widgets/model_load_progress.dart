import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/model_load_progress.dart';
import '../state/model_controller.dart';
import '../state/translation_controller.dart';

/// Linear progress for GGUF import (copy) and llama-server load.
class ModelLoadProgressBar extends StatelessWidget {
  const ModelLoadProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    final mc = context.watch<ModelController>();
    final progress = mc.loadProgress;
    if (!progress.isActive) return const SizedBox.shrink();

    final t = context.watch<TranslationController>();
    final theme = Theme.of(context);
    final filename = progress.filename ?? 'model.gguf';

    String title;
    if (progress.phase == ModelLoadPhase.copying) {
      final percent = ((progress.fraction ?? 0) * 100).round();
      title = t
          .t('model_import_copying')
          .replaceAll('{file}', filename)
          .replaceAll('{percent}', '$percent');
    } else {
      title = t.t('model_import_loading').replaceAll('{file}', filename);
    }

    final subtitle = progress.totalBytes > 0
        ? '${formatByteProgress(progress.bytesCopied)} / ${formatByteProgress(progress.totalBytes)}'
        : null;

    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ],
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress.phase == ModelLoadPhase.copying
                  ? progress.fraction
                  : null,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
