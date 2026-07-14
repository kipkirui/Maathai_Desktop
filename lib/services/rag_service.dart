import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';

import 'knowledge_asset_loader.dart';

/// TF-IDF based offline retrieval over the agricultural knowledge base.
///
/// Design goals:
/// - No external dependencies (pure Dart)
/// - Sub-50ms retrieval on 150+ documents
/// - Good recall for agricultural terminology (crop names, pests, diseases)
class RagService {
  final List<_Document> _documents = [];
  Map<String, double> _idf = {};
  bool _initialized = false;

  bool get isInitialized => _initialized;
  int get documentCount => _documents.length;

  Future<void> initialize() async {
    await _loadAssetDirectory('assets/knowledge_base/crops');
    await _loadAssetDirectory('assets/knowledge_base/pests');
    await _loadAssetDirectory('assets/knowledge_base/soil');
    await _loadAssetDirectory('assets/knowledge_base/markets');
    await _loadAssetDirectory('assets/knowledge_base/calendars');
    await _loadAssetDirectory('assets/knowledge_base/livestock');

    _buildIdf();
    _initialized = true;
  }

  Future<void> _loadAssetDirectory(String assetPath) async {
    try {
      final assetKeys = await KnowledgeAssetLoader.listJsonAssets(assetPath);

      for (final key in assetKeys) {
        try {
          final jsonString = await rootBundle.loadString(key);
          final List<dynamic> entries = json.decode(jsonString);

          for (final entry in entries) {
            if (entry is Map<String, dynamic>) {
              _documents.add(_Document.fromJson(entry, key));
            }
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {}
  }

  void _buildIdf() {
    final df = <String, int>{};
    for (final doc in _documents) {
      for (final term in doc.terms.keys) {
        df[term] = (df[term] ?? 0) + 1;
      }
    }
    final n = _documents.length.toDouble();
    _idf = {
      for (final entry in df.entries)
        entry.key: log((n + 1) / (entry.value + 1)) + 1.0
    };
  }

  /// Retrieve top-k most relevant passages for a query.
  Future<List<String>> retrieve({
    required String query,
    int topK = 3,
    String language = 'en',
    double minScore = 0.05,
  }) async {
    if (!_initialized || _documents.isEmpty) return [];

    final queryTerms = _tokenize(query);
    if (queryTerms.isEmpty) return [];

    // Score each document
    final scores = <int, double>{};
    for (int i = 0; i < _documents.length; i++) {
      scores[i] = _cosineSimilarity(queryTerms, _documents[i].terms);
    }

    // Sort by score descending
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ranked
        .where((e) => e.value >= minScore)
        .take(topK)
        .map((e) => _documents[e.key].passage(language))
        .where((p) => p.isNotEmpty)
        .toList();
  }

  double _cosineSimilarity(
    Map<String, double> query,
    Map<String, double> docTf,
  ) {
    double dot = 0;
    double queryNorm = 0;
    double docNorm = 0;

    for (final entry in query.entries) {
      final idf = _idf[entry.key] ?? 1.0;
      final qTfIdf = entry.value * idf;
      final dTfIdf = (docTf[entry.key] ?? 0) * idf;
      dot += qTfIdf * dTfIdf;
      queryNorm += qTfIdf * qTfIdf;
    }
    for (final entry in docTf.entries) {
      final idf = _idf[entry.key] ?? 1.0;
      docNorm += (entry.value * idf) * (entry.value * idf);
    }

    if (queryNorm == 0 || docNorm == 0) return 0;
    return dot / (sqrt(queryNorm) * sqrt(docNorm));
  }

  Map<String, double> _tokenize(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !_stopWords.contains(w))
        .toList();

    final tf = <String, double>{};
    for (final word in words) {
      // Stem: remove common suffixes
      final stemmed = _stem(word);
      tf[stemmed] = (tf[stemmed] ?? 0) + 1;
    }
    // Normalize TF
    if (words.isNotEmpty) {
      for (final key in tf.keys) {
        tf[key] = tf[key]! / words.length;
      }
    }
    return tf;
  }

  String _stem(String word) {
    return stemWord(word);
  }

  static const _stopWords = {
    'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
    'of', 'with', 'by', 'from', 'is', 'are', 'was', 'were', 'be', 'been',
    'has', 'have', 'had', 'do', 'does', 'did', 'will', 'would', 'could',
    'should', 'may', 'might', 'can', 'this', 'that', 'these', 'those',
    'it', 'its', 'my', 'your', 'our', 'their', 'what', 'how', 'when',
    'where', 'why', 'which', 'who', 'all', 'also', 'not', 'more', 'very',
  };
}

/// English stemmer shared by query tokenization and document indexing.
String stemWord(String word) {
  if (word.endsWith('ing') && word.length > 5) return word.substring(0, word.length - 3);
  if (word.endsWith('tion') && word.length > 5) return word.substring(0, word.length - 4);
  if (word.endsWith('ment') && word.length > 5) return word.substring(0, word.length - 4);
  if (word.endsWith('ness') && word.length > 5) return word.substring(0, word.length - 4);
  if (word.endsWith('ies') && word.length > 4) return '${word.substring(0, word.length - 3)}y';
  if (word.endsWith('es') && word.length > 4) return word.substring(0, word.length - 2);
  if (word.endsWith('ed') && word.length > 4) return word.substring(0, word.length - 2);
  if (word.endsWith('er') && word.length > 4) return word.substring(0, word.length - 2);
  if (word.endsWith('s') && word.length > 3) return word.substring(0, word.length - 1);
  return word;
}

class _Document {
  final String id;
  final String title;
  final String category;
  final String contentEn;
  final String? contentSw;
  final Map<String, double> terms;

  _Document({
    required this.id,
    required this.title,
    required this.category,
    required this.contentEn,
    this.contentSw,
    required this.terms,
  });

  factory _Document.fromJson(Map<String, dynamic> json, String assetKey) {
    final content = json['content'] as String? ?? '';
    final contentSw = json['content_sw'] as String?;
    final category = assetKey.split('/').reversed.skip(1).first;

    // Build TF map from title, tags, and English content (matches Python retriever).
    final tags = (json['tags'] as List<dynamic>?)
            ?.map((t) => t.toString())
            .join(' ') ??
        '';
    final fullText = '${json['title'] ?? ''} $tags $content'.toLowerCase();
    final words = fullText
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && !RagService._stopWords.contains(w))
        .map(stemWord)
        .toList();

    final tf = <String, double>{};
    for (final word in words) {
      tf[word] = (tf[word] ?? 0) + 1;
    }
    if (words.isNotEmpty) {
      for (final k in tf.keys) {
        tf[k] = tf[k]! / words.length;
      }
    }

    return _Document(
      id: json['id'] as String? ?? assetKey,
      title: json['title'] as String? ?? '',
      category: category,
      contentEn: content,
      contentSw: contentSw,
      terms: tf,
    );
  }

  String passage(String language) {
    final content = (language == 'sw' && contentSw != null)
        ? contentSw!
        : contentEn;
    // Trim to avoid excessive token usage
    final trimmed = content.length > 800 ? '${content.substring(0, 800)}…' : content;
    return '[$category: $title]\n$trimmed';
  }
}
