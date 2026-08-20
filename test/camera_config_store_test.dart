import 'dart:convert';

import 'package:camera_handheld/core/camera_config.dart';
import 'package:camera_handheld/core/camera_config_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// CameraConfigStore persists non-sensitive fields to shared_preferences and the
// password to flutter_secure_storage. Both backends are replaced with in-memory
// fakes via their respective test helpers.
void main() {
  setUp(() {
    // shared_preferences: empty in-memory store.
    SharedPreferences.setMockInitialValues({});
    // flutter_secure_storage: empty in-memory backing map.
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('save stores password only in secure storage, not shared_preferences',
      () async {
    const config = CameraConfig(
      ip: '10.0.0.5',
      port: 8554,
      username: 'operator',
      password: 's3cr3t',
      useSubStream: false,
    );
    await CameraConfigStore.save(config);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('camera_config');
    expect(raw, isNotNull);
    final json = jsonDecode(raw!) as Map<String, dynamic>;

    // The persisted blob must NOT contain the password.
    expect(json.containsKey('password'), isFalse);
    // Non-sensitive fields are persisted.
    expect(json['ip'], '10.0.0.5');
    expect(json['port'], 8554);
    expect(json['username'], 'operator');
    expect(json['useSubStream'], isFalse);

    // The password lives exclusively in secure storage.
    final storedPassword =
        await const FlutterSecureStorage().read(key: 'camera_config_password');
    expect(storedPassword, 's3cr3t');
  });

  test('load restores password from secure storage', () async {
    // Seed shared_preferences WITHOUT the password...
    SharedPreferences.setMockInitialValues({
      'camera_config': jsonEncode(<String, dynamic>{
        'ip': '10.0.0.5',
        'port': 8554,
        'username': 'operator',
        'useSubStream': false,
      }),
    });
    // ...and the password only in secure storage.
    FlutterSecureStorage.setMockInitialValues(
        {'camera_config_password': 's3cr3t'});

    final config = await CameraConfigStore.load();
    expect(config.ip, '10.0.0.5');
    expect(config.port, 8554);
    expect(config.username, 'operator');
    expect(config.useSubStream, isFalse);
    // Password must come back from secure storage, not from the prefs blob.
    expect(config.password, 's3cr3t');
  });

  test('load without a stored password defaults to empty string', () async {
    SharedPreferences.setMockInitialValues({
      'camera_config': jsonEncode(<String, dynamic>{
        'ip': '10.0.0.5',
        'username': 'operator',
      }),
    });
    // secure storage intentionally empty.
    final config = await CameraConfigStore.load();
    expect(config.password, '');
    expect(config.ip, '10.0.0.5');
    expect(config.username, 'operator');
  });
}
