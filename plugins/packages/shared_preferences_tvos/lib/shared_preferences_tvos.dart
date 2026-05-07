// Copyright 2026 The FlutterTV Authors. All rights reserved.
// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/services.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

const String _channelName = 'plugins.fluttertv.dev/shared_preferences_tvos';
const MethodChannel _channel = MethodChannel(_channelName);

// ---------------------------------------------------------------------------
// Legacy synchronous platform (SharedPreferences.getInstance())
// ---------------------------------------------------------------------------

/// The tvOS implementation of [SharedPreferencesStorePlatform].
///
/// Backed by `NSUserDefaults.standard`. Keys are namespaced with the
/// `flutter.` prefix, mirroring the behaviour of the upstream iOS /
/// macOS (`shared_preferences_foundation`) implementations.
class SharedPreferencesTvos extends SharedPreferencesStorePlatform {
  /// Registers this class as the default instance of
  /// [SharedPreferencesStorePlatform] and [SharedPreferencesAsyncPlatform].
  static void registerWith() {
    // ignore: avoid_print
    print('[tvos-diag] SharedPreferencesTvos.registerWith() entered');
    try {
      SharedPreferencesStorePlatform.instance = SharedPreferencesTvos();
      // ignore: avoid_print
      print('[tvos-diag] StorePlatform instance set');
    } catch (e, st) {
      // ignore: avoid_print
      print('[tvos-diag] StorePlatform set FAILED: $e\n$st');
    }
    try {
      SharedPreferencesAsyncPlatform.instance = SharedPreferencesAsyncTvos();
      // ignore: avoid_print
      print('[tvos-diag] AsyncPlatform instance set');
    } catch (e, st) {
      // ignore: avoid_print
      print('[tvos-diag] AsyncPlatform set FAILED: $e\n$st');
    }
  }

  @override
  Future<bool> clear() async {
    final bool? ok = await _channel.invokeMethod<bool>('clear');
    return ok ?? false;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    final Map<Object?, Object?>? raw =
        await _channel.invokeMethod<Map<Object?, Object?>>('getAll');
    if (raw == null) return <String, Object>{};
    return raw.map((k, v) => MapEntry(k! as String, v!));
  }

  @override
  Future<bool> remove(String key) async {
    final bool? ok = await _channel.invokeMethod<bool>(
        'remove', <String, Object?>{'key': key});
    return ok ?? false;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final bool? ok = await _channel.invokeMethod<bool>(
        'setValue', <String, Object?>{'type': valueType, 'key': key, 'value': value});
    return ok ?? false;
  }
}

// ---------------------------------------------------------------------------
// Async platform (SharedPreferencesAsync / SharedPreferencesWithCache)
// ---------------------------------------------------------------------------

/// The tvOS implementation of [SharedPreferencesAsyncPlatform].
///
/// Uses the same `NSUserDefaults`-backed method channel as
/// [SharedPreferencesTvos]. `NSUserDefaults` is synchronous; this class
/// wraps each call in a Future so that the async platform interface contract
/// is satisfied.
base class SharedPreferencesAsyncTvos extends SharedPreferencesAsyncPlatform {
  // ---- reads ----

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) =>
      _all(options).then((m) => m[key] as bool?);

  @override
  Future<double?> getDouble(String key, SharedPreferencesOptions options) =>
      _all(options).then((m) => (m[key] as num?)?.toDouble());

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) =>
      _all(options).then((m) => (m[key] as num?)?.toInt());

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) =>
      _all(options).then((m) => m[key] as String?);

  @override
  Future<List<String>?> getStringList(
          String key, SharedPreferencesOptions options) =>
      _all(options).then((m) => (m[key] as List?)?.cast<String>());

  // ---- writes ----

  @override
  Future<void> setBool(String key, bool value, SharedPreferencesOptions o) =>
      _set('Bool', key, value);

  @override
  Future<void> setDouble(
          String key, double value, SharedPreferencesOptions o) =>
      _set('Double', key, value);

  @override
  Future<void> setInt(String key, int value, SharedPreferencesOptions o) =>
      _set('Int', key, value);

  @override
  Future<void> setString(
          String key, String value, SharedPreferencesOptions o) =>
      _set('String', key, value);

  @override
  Future<void> setStringList(
          String key, List<String> value, SharedPreferencesOptions o) =>
      _set('StringList', key, value);

  // ---- bulk ops ----

  @override
  Future<void> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final Set<String>? allowList = parameters.filter.allowList;
    if (allowList == null) {
      await _channel.invokeMethod<void>('clear');
    } else {
      for (final String key in allowList) {
        await _channel.invokeMethod<void>('remove', <String, Object?>{'key': key});
      }
    }
  }

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final Map<String, Object> all = await _all(options);
    final Set<String>? allowList = parameters.filter.allowList;
    if (allowList == null) return all;
    return Map<String, Object>.fromEntries(
        all.entries.where((e) => allowList.contains(e.key)));
  }

  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final Set<String> keys = (await _all(options)).keys.toSet();
    final Set<String>? allowList = parameters.filter.allowList;
    if (allowList == null) return keys;
    return keys.intersection(allowList);
  }

  // ---- helpers ----

  Future<void> _set(String type, String key, Object value) =>
      _channel.invokeMethod<void>(
          'setValue', <String, Object?>{'type': type, 'key': key, 'value': value});

  Future<Map<String, Object>> _all(SharedPreferencesOptions options) async {
    final Map<Object?, Object?>? raw =
        await _channel.invokeMethod<Map<Object?, Object?>>('getAll');
    if (raw == null) return <String, Object>{};
    return raw.map((k, v) => MapEntry(k! as String, v!));
  }
}
