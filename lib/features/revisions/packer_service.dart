import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:cpw_pw/core/logger/logger_service.dart';

/// The result of packing the file.
typedef PackResult = ({
int uncompressedSize,
int packedSize,
String md5,
});

/// File packer.
/// Format: [4 bytes: little-endian uncompressed size][deflate-compressed data]
class PackerService {
  /// Packs a file from source to target.
  /// Returns the size of the packed file and its MD5 (for writing to the database).
  Future<PackResult> pack(File source, File target) async {
    log.fine('Packing: ${source.path} to ${target.path}');

    final inputBytes = await source.readAsBytes();
    final uncompressedSize = inputBytes.length;
    final compressor = ZLibEncoder(level: 1);
    final compressedList = compressor.convert(inputBytes);
    final compressedBytes = Uint8List.fromList(compressedList);
    final outputBytes = uncompressedSize <= compressedBytes.length
        ? inputBytes
        : compressedBytes;

    await target.parent.create(recursive: true);

    // [4-byte LE size][data]
    final sink = target.openWrite();

    // 4-byte little-endian source file size
    final sizeBuffer = ByteData(4)
      ..setInt32(0, uncompressedSize, Endian.little);

    sink
      ..add(sizeBuffer.buffer.asUint8List())
      ..add(outputBytes);

    await sink.flush();
    await sink.close();

    final md5 = await _calculateMd5(target);
    final packedSize = await target.length();

    log.fine('Packed: ${source.path} ($uncompressedSize to $packedSize bytes, MD5: $md5)');

    return (
    uncompressedSize: uncompressedSize,
    packedSize: packedSize,
    md5: md5,
    );
  }

  Future<String> _calculateMd5(File file) async {
    final digest = MD5Digest()..reset();

    await for (final chunk in file.openRead()) {
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      digest.update(bytes, 0, bytes.length);
    }

    final hash = Uint8List(digest.digestSize);
    digest.doFinal(hash, 0);

    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}