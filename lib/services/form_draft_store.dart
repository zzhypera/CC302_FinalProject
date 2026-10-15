import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores one form's unsaved values without affecting other drafts.
class FormDraftStore {
  const FormDraftStore(this.key);

  final String key;

  Future<Map<String, dynamic>?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw == null) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    return decoded;
  }

  Future<void> save(Map<String, dynamic> values) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, jsonEncode(values));
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }
}
