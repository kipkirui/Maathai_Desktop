import 'package:flutter_test/flutter_test.dart';

import 'package:maathai_desktop/config/app_config.dart';

void main() {
  test('desktop app identity and competition model', () {
    expect(AppConfig.appName, 'Maathai Desktop');
    expect(AppConfig.defaultModelFilename, 'qwen2.5-3b-instruct-q4_k_m.gguf');
    expect(AppConfig.supportedLanguages.map((e) => e['code']), containsAll(['en', 'sw']));
    expect(AppConfig.defaultProcessPrio, 0);
    expect(AppConfig.defaultMaxTokens, 256);
  });
}
