abstract final class Utils {
  /// Safely converts any dynamic value to an integer (int).
  /// If the value is null or unparsable, returns 0.
  static int parseInt(dynamic value) {
    if (value is int) return value;
    if (value == null) return 0;
    return int.tryParse(value.toString()) ?? 0;
  }
}