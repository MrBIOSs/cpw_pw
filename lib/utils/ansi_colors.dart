import 'package:ansicolor/ansicolor.dart';

/// General color schemes for CLI output.
/// Cached `AnsiPen` instances to avoid unnecessary allocations.
final class AnsiColors {
  const AnsiColors._();

  static final heading = AnsiPen()..white(bold: true);
  static final command = AnsiPen()..green();
  static final description = AnsiPen()..cyan();
  static final error = AnsiPen()..red(bold: true);
  static final warning = AnsiPen()..yellow();
  static final success = AnsiPen()..green(bold: true);
  static final dim = AnsiPen()..gray(level: 0.5);
  static final monochrome = AnsiPen();
}







