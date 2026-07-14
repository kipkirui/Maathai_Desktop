import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/chat_controller.dart';
import '../state/translation_controller.dart';

class ContextPanel extends StatefulWidget {
  final VoidCallback onClose;

  const ContextPanel({super.key, required this.onClose});

  @override
  State<ContextPanel> createState() => _ContextPanelState();
}

class _ContextPanelState extends State<ContextPanel> {
  static const _regions = [
    'Kenya - Central',
    'Kenya - Rift Valley',
    'Kenya - Western',
    'Kenya - Coast',
    'Tanzania - Arusha',
    'Tanzania - Kilimanjaro',
    'Tanzania - Mwanza',
    'Uganda - Central',
    'Uganda - Western',
    'Ethiopia - Oromia',
    'Rwanda - Kigali',
    'Nigeria - Kano',
    'Ghana - Ashanti',
  ];

  static const _crops = [
    'Maize',
    'Cassava',
    'Beans',
    'Sorghum',
    'Millet',
    'Sweet Potato',
    'Tomato',
    'Kale (Sukuma Wiki)',
    'Tea',
    'Coffee',
    'Banana',
    'Groundnut',
    'Soybean',
    'Wheat',
  ];

  static const _seasons = [
    'Long Rains (Mar–May)',
    'Short Rains (Oct–Dec)',
    'Dry Season',
    'Highland Season',
  ];

  @override
  Widget build(BuildContext context) {
    final chatController = context.watch<ChatController>();
    final t = context.watch<TranslationController>();
    final ctx = chatController.farmContext;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              const Icon(Icons.agriculture, size: 18, color: Color(0xFF2E7D32)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.t('context_panel_title'),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: widget.onClose,
                tooltip: 'Close context panel',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            t.t('context_panel_subtitle'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const Divider(height: 24),
        // Region
        _DropdownField(
          label: t.t('context_region'),
          icon: Icons.location_on_outlined,
          value: ctx.region,
          items: _regions,
          onChanged: (v) => chatController.updateFarmContext(
            ctx.copyWith(region: v),
          ),
        ),
        const SizedBox(height: 12),
        // Crop
        _DropdownField(
          label: t.t('context_crop'),
          icon: Icons.grass,
          value: ctx.crop,
          items: _crops,
          onChanged: (v) => chatController.updateFarmContext(
            ctx.copyWith(crop: v),
          ),
        ),
        const SizedBox(height: 12),
        // Season
        _DropdownField(
          label: t.t('context_season'),
          icon: Icons.wb_sunny_outlined,
          value: ctx.season,
          items: _seasons,
          onChanged: (v) => chatController.updateFarmContext(
            ctx.copyWith(season: v),
          ),
        ),
        const SizedBox(height: 16),
        // Clear context
        if (ctx.hasContext)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => chatController.updateFarmContext(
                FarmContext(language: ctx.language),
              ),
              icon: const Icon(Icons.clear, size: 16),
              label: Text(t.t('clear_context')),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 36),
              ),
            ),
          ),
        const Spacer(),
        // Status indicator
        Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Active context',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                if (!ctx.hasContext)
                  Text(
                    'No context set — responses will be general',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  )
                else ...[
                  if (ctx.region != null) _ContextChip(ctx.region!),
                  if (ctx.crop != null) _ContextChip(ctx.crop!),
                  if (ctx.season != null) _ContextChip(ctx.season!),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        hint: const Text('Select...'),
        isExpanded: true,
        items: [
          const DropdownMenuItem(value: null, child: Text('None')),
          ...items.map((item) => DropdownMenuItem(
                value: item,
                child: Text(item, overflow: TextOverflow.ellipsis),
              )),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _ContextChip extends StatelessWidget {
  final String label;
  const _ContextChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 12, color: Color(0xFF2E7D32)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
