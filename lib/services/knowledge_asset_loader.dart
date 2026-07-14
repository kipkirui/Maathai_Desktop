import 'package:flutter/services.dart';

/// Lists bundled asset paths — uses AssetManifest API (AssetManifest.json removed in Flutter 3.19+).
class KnowledgeAssetLoader {
  static Future<List<String>> listJsonAssets(String directoryPrefix) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    return manifest
        .listAssets()
        .where(
          (path) =>
              path.startsWith(directoryPrefix) && path.endsWith('.json'),
        )
        .toList()
      ..sort();
  }
}
