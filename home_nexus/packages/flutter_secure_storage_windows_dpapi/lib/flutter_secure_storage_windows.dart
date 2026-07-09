import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:win32/win32.dart';

/// Dart-only Windows secure storage: values are encrypted per-user with
/// DPAPI (CryptProtectData) and stored as base64 blobs in a JSON file under
/// %APPDATA%. Same guarantees as the upstream implementation, no native
/// build step.
class FlutterSecureStorageWindows extends FlutterSecureStoragePlatform {
  static void registerWith() {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWindows();
  }

  File get _file {
    final appData = Platform.environment['APPDATA'] ??
        Directory.systemTemp.path;
    return File('$appData\\home_nexus\\secure_store.json');
  }

  Map<String, String> _load() {
    try {
      final raw = _file.readAsStringSync();
      return (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  void _save(Map<String, String> data) {
    _file.parent.createSync(recursive: true);
    _file.writeAsStringSync(jsonEncode(data));
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    final data = _load();
    data[key] = base64Encode(_protect(utf8.encode(value)));
    _save(data);
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    final blob = _load()[key];
    if (blob == null) return null;
    try {
      return utf8.decode(_unprotect(base64Decode(blob)));
    } catch (_) {
      return null; // undecryptable (other user/machine): treat as absent
    }
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      _load().containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    final data = _load()..remove(key);
    _save(data);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    _save({});
  }

  @override
  Future<Map<String, String>> readAll(
      {required Map<String, String> options}) async {
    final out = <String, String>{};
    for (final entry in _load().entries) {
      try {
        out[entry.key] = utf8.decode(_unprotect(base64Decode(entry.value)));
      } catch (_) {}
    }
    return out;
  }

  Uint8List _protect(List<int> data) =>
      _dpapi(Uint8List.fromList(data), encrypt: true);

  Uint8List _unprotect(Uint8List data) => _dpapi(data, encrypt: false);

  Uint8List _dpapi(Uint8List input, {required bool encrypt}) {
    final blobIn = calloc<CRYPT_INTEGER_BLOB>();
    final blobOut = calloc<CRYPT_INTEGER_BLOB>();
    final pData = calloc<Uint8>(input.length);
    pData.asTypedList(input.length).setAll(0, input);
    blobIn.ref.cbData = input.length;
    blobIn.ref.pbData = pData;
    try {
      final ok = encrypt
          ? CryptProtectData(
              blobIn, nullptr, nullptr, nullptr, nullptr, 0, blobOut)
          : CryptUnprotectData(
              blobIn, nullptr, nullptr, nullptr, nullptr, 0, blobOut);
      if (ok == 0) {
        throw StateError('DPAPI ${encrypt ? 'protect' : 'unprotect'} failed '
            '(${GetLastError()})');
      }
      final out = Uint8List.fromList(
          blobOut.ref.pbData.asTypedList(blobOut.ref.cbData));
      LocalFree(blobOut.ref.pbData.cast());
      return out;
    } finally {
      calloc.free(pData);
      calloc.free(blobIn);
      calloc.free(blobOut);
    }
  }
}
