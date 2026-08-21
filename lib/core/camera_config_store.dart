import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'camera_config.dart';

/// Persists CameraConfig to shared_preferences (plaintext, including password).
/// Simple and reliable — no Keychain/entitlement issues.
class CameraConfigStore {
  static const _key = 'camera_config';

  static Future<CameraConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const CameraConfig();
    try {
      return CameraConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const CameraConfig();
    }
  }

  static Future<void> save(CameraConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(config.toJson()));
  }
}