import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/model_service.dart';
import '../state/model_controller.dart';
import '../state/translation_controller.dart';
import '../widgets/model_load_progress.dart';

class ModelsScreen extends StatefulWidget {
  const ModelsScreen({super.key});

  @override
  State<ModelsScreen> createState() => _ModelsScreenState();
}

class _ModelsScreenState extends State<ModelsScreen> {
  List<ModelInfo> _models = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final modelService = context.read<ModelController>().modelService;
    final models = await modelService.listModels();
    setState(() {
      _models = models;
      _loading = false;
    });
  }

  Future<void> _importModel() async {
    if (context.read<ModelController>().status == ModelStatus.loading) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gguf'],
      dialogTitle: 'Select GGUF model file',
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.first.path;
    if (path == null) return;

    final modelController = context.read<ModelController>();
    await modelController.importModel(path);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final modelController = context.watch<ModelController>();
    final t = context.watch<TranslationController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(t.t('nav_models')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
          FilledButton.icon(
            onPressed: _importModel,
            icon: const Icon(Icons.folder_open),
            label: Text(t.t('import_model')),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ModelLoadProgressBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _models.isEmpty
                    ? _buildEmpty(t)
                    : ListView.separated(
                        padding: const EdgeInsets.all(24),
                        itemCount: _models.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) => _ModelCard(
                          model: _models[i],
                          isLoaded:
                              _models[i].path == modelController.loadedModelPath,
                          isLoading: modelController.status == ModelStatus.loading,
                          onLoad: () => modelController.loadModel(_models[i].path),
                          onUnload: () => modelController.unloadModel(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(TranslationController t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.memory_outlined, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            t.t('no_models_title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            t.t('no_models_subtitle'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _importModel,
            icon: const Icon(Icons.folder_open),
            label: Text(t.t('import_model')),
          ),
          const SizedBox(height: 8),
          Text(
            'Or run: bash download_model.sh',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  final ModelInfo model;
  final bool isLoaded;
  final bool isLoading;
  final VoidCallback onLoad;
  final VoidCallback onUnload;

  const _ModelCard({
    required this.model,
    required this.isLoaded,
    required this.isLoading,
    required this.onLoad,
    required this.onUnload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCompetition = model.isDefaultCompetitionModel;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isLoaded
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.memory,
                color: isLoaded
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          model.filename,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCompetition) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ADTC',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    model.sizeLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    model.path,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Action button
            if (isLoaded)
              OutlinedButton(
                onPressed: onUnload,
                child: const Text('Unload'),
              )
            else
              FilledButton(
                onPressed: isLoading ? null : onLoad,
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Load'),
              ),
          ],
        ),
      ),
    );
  }
}
