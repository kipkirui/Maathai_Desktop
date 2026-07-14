import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../services/knowledge_asset_loader.dart';
import '../state/translation_controller.dart';

class _KnowledgeEntry {
  final String id;
  final String title;
  final String content;
  final String? contentSw;
  final String category;
  final List<String> tags;

  _KnowledgeEntry({
    required this.id,
    required this.title,
    required this.content,
    this.contentSw,
    required this.category,
    required this.tags,
  });
}

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> {
  List<_KnowledgeEntry> _allEntries = [];
  List<_KnowledgeEntry> _filtered = [];
  _KnowledgeEntry? _selected;
  final TextEditingController _search = TextEditingController();
  String _activeCategory = 'all';
  bool _loading = true;

  static const _categories = [
    {'key': 'all', 'label': 'All', 'icon': Icons.apps},
    {'key': 'crops', 'label': 'Crops', 'icon': Icons.grass},
    {'key': 'pests', 'label': 'Pests & Diseases', 'icon': Icons.bug_report_outlined},
    {'key': 'soil', 'label': 'Soil', 'icon': Icons.terrain_outlined},
    {'key': 'markets', 'label': 'Markets', 'icon': Icons.store_outlined},
    {'key': 'calendars', 'label': 'Calendars', 'icon': Icons.calendar_month_outlined},
    {'key': 'livestock', 'label': 'Livestock', 'icon': Icons.pets_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _search.addListener(_filterEntries);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    final entries = <_KnowledgeEntry>[];

    for (final category in ['crops', 'pests', 'soil', 'markets', 'calendars', 'livestock']) {
      final assetKeys = await KnowledgeAssetLoader.listJsonAssets(
        'assets/knowledge_base/$category',
      );

      for (final key in assetKeys) {
        try {
          final jsonStr = await rootBundle.loadString(key);
          final List<dynamic> list = json.decode(jsonStr);
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              entries.add(_KnowledgeEntry(
                id: item['id'] as String? ?? key,
                title: item['title'] as String? ?? '',
                content: item['content'] as String? ?? '',
                contentSw: item['content_sw'] as String?,
                category: category,
                tags: (item['tags'] as List<dynamic>?)
                        ?.map((t) => t.toString())
                        .toList() ??
                    [],
              ));
            }
          }
        } catch (_) {}
      }
    }

    setState(() {
      _allEntries = entries;
      _filtered = entries;
      _loading = false;
    });
  }

  void _filterEntries() {
    final query = _search.text.toLowerCase();
    setState(() {
      _filtered = _allEntries.where((e) {
        final matchCategory =
            _activeCategory == 'all' || e.category == _activeCategory;
        final matchSearch = query.isEmpty ||
            e.title.toLowerCase().contains(query) ||
            e.content.toLowerCase().contains(query) ||
            e.tags.any((t) => t.toLowerCase().contains(query));
        return matchCategory && matchSearch;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<TranslationController>();

    return Scaffold(
      appBar: AppBar(title: Text(t.t('nav_knowledge'))),
      body: Row(
        children: [
          // Sidebar: categories + search + list
          SizedBox(
            width: 280,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: t.t('search_knowledge'),
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                ),
                // Category filter
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: _categories.map((cat) {
                      final active = _activeCategory == cat['key'] as String;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(cat['label'] as String),
                          selected: active,
                          onSelected: (_) {
                            setState(() => _activeCategory = cat['key'] as String);
                            _filterEntries();
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _filtered.isEmpty
                          ? Center(child: Text(t.t('no_results')))
                          : ListView.builder(
                              itemCount: _filtered.length,
                              itemBuilder: (ctx, i) {
                                final entry = _filtered[i];
                                final selected = _selected?.id == entry.id;
                                return ListTile(
                                  title: Text(
                                    entry.title,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    entry.category,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  selected: selected,
                                  onTap: () =>
                                      setState(() => _selected = entry),
                                  dense: true,
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Detail panel
          Expanded(
            child: _selected == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.menu_book_outlined,
                            size: 72, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          t.t('knowledge_select_hint'),
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  )
                : _EntryDetailView(
                    entry: _selected!,
                    showSwahili: t.isSwahili,
                  ),
          ),
        ],
      ),
    );
  }
}

class _EntryDetailView extends StatelessWidget {
  final _KnowledgeEntry entry;
  final bool showSwahili;

  const _EntryDetailView({required this.entry, required this.showSwahili});

  @override
  Widget build(BuildContext context) {
    final content = (showSwahili && entry.contentSw != null)
        ? entry.contentSw!
        : entry.content;

    return Scaffold(
      appBar: AppBar(
        title: Text(entry.title),
        automaticallyImplyLeading: false,
        actions: [
          Chip(
            label: Text(entry.category),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Markdown(
        data: content,
        padding: const EdgeInsets.all(24),
      ),
    );
  }
}
