import 'dart:convert';

/// File model for the revision manifest.
/// Corresponds to the structure of the "files" table in the database.
typedef FileEntry = ({
String path,          // Relative path: "element/data/file.dat"
String md5,           // MD5 hash of the contents
int size,             // Size in bytes
String type,          // 'element' | 'launcher' | 'patcher'
DateTime addedAt,     // Time of adding to revision
});

/// Extension for database mapping.
extension FileEntryDb on FileEntry {
  Map<String, dynamic> toDbMap(int revision) => {
    'added': addedAt.millisecondsSinceEpoch ~/ 1000,
    'size': size,
    'revision': revision,
    'md5': md5,
    'type': type,
    'folder': path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '',
    'folder_base64': _toBase64(path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : ''),
    'file': path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path,
    'file_base64': _toBase64(path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path),
  };

  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  static String _toBase64(String value) {
    return _bytesToBase64(utf8.encode(value)).replaceAll('=', '');
  }

  static String _bytesToBase64(List<int> bytes) => String.fromCharCodes(
    bytes.map((b) => _alphabet.codeUnitAt(b >> 2)).toList()
  );
}