import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'crypto.dart';

/// Storing keys in a local JSON file.
/// Format: { "key": "value", }
final class FileKeyStorage implements IKeyStorage {
  FileKeyStorage({required String baseDir})
      : _filePath = path.join(baseDir, 'config', 'keys.json');

  final String _filePath;

  @override
  bool hasKeys() {
    final file = File(_filePath);
    return file.existsSync();
  }

  @override
  Future<RsaKeyPair> load() async {
    final file = File(_filePath);
    if (!file.existsSync()) {
      throw const KeyNotFoundException();
    }

    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      return (
      p: BigInt.parse(json['p'] as String),
      q: BigInt.parse(json['q'] as String),
      modulus: BigInt.parse(json['modulus'] as String),
      publicExponent: BigInt.parse(json['publicExponent'] as String),
      privateExponent: BigInt.parse(json['privateExponent'] as String),
      publicKeyPem: json['publicKeyPem'] as String,
      privateKeyPem: json['privateKeyPem'] as String,
      );
    } on FormatException catch (e) {
      throw KeyStorageException('Failed to parse keys file: $e');
    } on FileSystemException catch (e) {
      throw KeyStorageException('Failed to read keys file: $e');
    }
  }

  @override
  Future<void> save(RsaKeyPair keys) async {
    await Directory(path.dirname(_filePath)).create(recursive: true);

    final json = {
      'p': keys.p.toString(),
      'q': keys.q.toString(),
      'modulus': keys.modulus.toString(),
      'publicExponent': keys.publicExponent.toString(),
      'privateExponent': keys.privateExponent.toString(),
      'publicKeyPem': keys.publicKeyPem,
      'privateKeyPem': keys.privateKeyPem,
      'generatedAt': DateTime.now().toIso8601String(),
    };

    final tmpPath = '$_filePath.tmp';
    final file = File(tmpPath);

    await file.writeAsString(jsonEncode(json));
    await file.rename(_filePath);
  }

  @override
  Future<void> delete() async {
    final file = File(_filePath);
    if (file.existsSync()) {
      await file.delete();
    }
  }
}