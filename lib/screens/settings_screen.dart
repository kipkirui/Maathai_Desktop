import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../state/model_controller.dart';
import '../state/theme_controller.dart';
import '../state/translation_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TranslationController>();

    return Scaffold(
      appBar: AppBar(title: Text(t.t('nav_settings'))),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _SectionHeader(title: t.t('settings_language')),
          _LanguageSetting(),
          const SizedBox(height: 24),
          _SectionHeader(title: t.t('settings_appearance')),
          _ThemeSetting(),
          const SizedBox(height: 24),
          _SectionHeader(title: t.t('settings_model')),
          _ModelSettings(),
          const SizedBox(height: 24),
          _SectionHeader(title: t.t('settings_about')),
          _AboutSection(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _LanguageSetting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.watch<TranslationController>();

    return Card(
      child: Column(
        children: AppConfig.supportedLanguages.map((lang) {
          return RadioListTile<String>(
            title: Text(lang['nativeName']!),
            subtitle: Text(lang['name']!),
            value: lang['code']!,
            groupValue: t.locale,
            onChanged: (code) => t.setLocale(code!),
          );
        }).toList(),
      ),
    );
  }
}

class _ThemeSetting extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final t = context.watch<TranslationController>();

    return Card(
      child: Column(
        children: [
          RadioListTile<ThemeMode>(
            title: Text(t.t('theme_system')),
            value: ThemeMode.system,
            groupValue: themeController.themeMode,
            onChanged: (v) => themeController.setThemeMode(v!),
          ),
          RadioListTile<ThemeMode>(
            title: Text(t.t('theme_light')),
            value: ThemeMode.light,
            groupValue: themeController.themeMode,
            onChanged: (v) => themeController.setThemeMode(v!),
          ),
          RadioListTile<ThemeMode>(
            title: Text(t.t('theme_dark')),
            value: ThemeMode.dark,
            groupValue: themeController.themeMode,
            onChanged: (v) => themeController.setThemeMode(v!),
          ),
        ],
      ),
    );
  }
}

class _ModelSettings extends StatefulWidget {
  @override
  State<_ModelSettings> createState() => _ModelSettingsState();
}

class _ModelSettingsState extends State<_ModelSettings> {
  @override
  Widget build(BuildContext context) {
    final mc = context.watch<ModelController>();
    final t = context.watch<TranslationController>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SliderRow(
              label: '${t.t('temperature')}: ${mc.temperature.toStringAsFixed(2)}',
              value: mc.temperature,
              min: 0.0,
              max: 2.0,
              onChanged: (v) {
                mc.temperature = v;
                mc.saveSettings();
              },
            ),
            _SliderRow(
              label: '${t.t('top_p')}: ${mc.topP.toStringAsFixed(2)}',
              value: mc.topP,
              min: 0.0,
              max: 1.0,
              onChanged: (v) {
                mc.topP = v;
                mc.saveSettings();
              },
            ),
            _SliderRow(
              label: '${t.t('max_tokens')}: ${mc.maxTokens}',
              value: mc.maxTokens.toDouble(),
              min: 64,
              max: 1024,
              divisions: 30,
              onChanged: (v) {
                mc.maxTokens = v.round();
                mc.saveSettings();
              },
            ),
            _SliderRow(
              label: '${t.t('threads')}: ${mc.threads}',
              value: mc.threads.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              onChanged: (v) {
                mc.threads = v.round();
                mc.saveSettings();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppConfig.appName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'v${AppConfig.appVersion} · ADTC 2026',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              AppConfig.appDescription,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              children: [
                Chip(label: Text('Agriculture domain')),
                Chip(label: Text('Offline RAG')),
                Chip(label: Text('Swahili support')),
                Chip(label: Text('llama.cpp')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
