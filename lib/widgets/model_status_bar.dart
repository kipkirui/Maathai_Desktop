import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/model_controller.dart';
import '../state/translation_controller.dart';
import 'model_load_progress.dart';

class ModelStatusBar extends StatelessWidget {
  final ModelStatus status;

  const ModelStatusBar({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final mc = context.watch<ModelController>();
    final t = context.watch<TranslationController>();

    final hideBanner =
        status == ModelStatus.ready || status == ModelStatus.generating;

    if (hideBanner) {
      // Keep a stable slot in the tree — removing the banner abruptly was
      // corrupting the Windows accessibility tree before ExcludeSemantics.
      return const SizedBox(width: double.infinity, height: 0);
    }

    if (mc.loadProgress.isActive) {
      return const ModelLoadProgressBar();
    }

    Color bgColor;
    Color textColor;
    String message;
    Widget? action;

    switch (status) {
      case ModelStatus.notLoaded:
        bgColor = Theme.of(context).colorScheme.errorContainer;
        textColor = Theme.of(context).colorScheme.onErrorContainer;
        message = t.t('no_model_loaded_banner');
        action = TextButton(
          onPressed: () {},
          child: Text(t.t('load_model')),
        );
      case ModelStatus.loading:
        bgColor = Theme.of(context).colorScheme.secondaryContainer;
        textColor = Theme.of(context).colorScheme.onSecondaryContainer;
        message = t.t('model_loading_banner');
        action = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case ModelStatus.error:
        bgColor = Theme.of(context).colorScheme.errorContainer;
        textColor = Theme.of(context).colorScheme.onErrorContainer;
        message = mc.errorMessage ?? t.t('model_error_banner');
        action = TextButton(
          onPressed: () => mc.loadModel(mc.loadedModelPath ?? ''),
          child: Text(t.t('retry')),
        );
      default:
        return const SizedBox.shrink();
    }

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: textColor, fontSize: 13),
            ),
          ),
          action,
        ],
      ),
    );
  }
}
