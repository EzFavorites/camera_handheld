import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'camera_config.dart';

/// Persists CameraConfig.
/// Non-sensitive fields (ip, port, username, useSubStream) go to shared_preferences.
/// The password goes to flutter_secure_storage (Android Keystore / iOS Keychain / macOS Keychain)
/// so it is never written to disk in plaintext.
class CameraConfigStore {
  static const _key = 'camera_config';
  static const _passwordKey = 'camera_config_password';

  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<CameraConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    CameraConfig config;
    if (raw == null) {
      config = const CameraConfig();
    } else {
      try {
        config = CameraConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        config = const CameraConfig();
      }
    }

    // Merge password from secure storage (best-effort; ignore if unavailable).
    try {
      final password = await _secureStorage.read(key: _passwordKey);
      if (password != null) config = config.copyWith(password: password);
    } catch (_) {
      // Secure storage backend unavailable; keep default empty password.
    }
    return config;
  }

  static Future<void> save(CameraConfig config) async {
    final prefs = await SharedPreferences.getInstance();

    // Persist everything except the password (toPersistableJson omits it).
    final json = config.toPersistableJson();
    await prefs.setString(_key, jsonEncode(json));

    // Persist password in secure storage (best-effort).
    try {
      await _secureStorage.write(key: _passwordKey, value: config.password);
    } catch (_) {
      // Secure storage backend unavailable; password not persisted.
    }
  }
}
