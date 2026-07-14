import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TranslationController extends ChangeNotifier {
  String _locale = 'en';
  Map<String, String> _strings = {};

  String get locale => _locale;
  bool get isSwahili => _locale == 'sw';

  TranslationController() {
    _load('en');
  }

  String t(String key) => _strings[key] ?? key;

  Future<void> setLocale(String locale) async {
    if (_locale == locale) return;
    await _load(locale);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale);
  }

  Future<void> _load(String locale) async {
    try {
      final jsonString = await rootBundle.loadString('assets/i18n/$locale.json');
      final Map<String, dynamic> raw = json.decode(jsonString);
      _strings = raw.map((k, v) => MapEntry(k, v.toString()));
      _locale = locale;
      notifyListeners();
    } catch (_) {
      // Fallback: keep existing strings
    }
  }
}
