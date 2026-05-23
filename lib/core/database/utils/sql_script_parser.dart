abstract final class SqlScriptParser {
  /// Splits an SQL script into separate independent queries.
  ///
  /// Correctly handles:
  /// - Single-line comments ("--", '#') at the beginning and middle of lines.
  /// - Multi-line comments (/* ... */).
  /// - Semicolons ';' within string literals (`'...'`, `"..."`).
  static List<String> splitQueries(String script) {
    final queries = <String>[];
    final buffer = StringBuffer();

    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inMultiLineComment = false;

    final lines = script.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (!inMultiLineComment && (trimmed.startsWith('--') || trimmed.startsWith('#'))) {
        continue;
      }

      for (var j = 0; j < line.length; j++) {
        final char = line[j];
        final nextChar = (j + 1 < line.length) ? line[j + 1] : '';

        if (inMultiLineComment) {
          if (char == '*' && nextChar == '/') {
            inMultiLineComment = false;
            j++;
          }
          continue;
        }

        if (!inSingleQuote && !inDoubleQuote) {
          if ((char == '-' && nextChar == '-') || char == '#') {
            break;
          }
          if (char == '/' && nextChar == '*') {
            inMultiLineComment = true;
            j++;
            continue;
          }
        }

        if (char == "'" && !inDoubleQuote) {
          final isEscaped = j > 0 && line[j - 1] == r'\';
          if (!isEscaped) inSingleQuote = !inSingleQuote;
        } else if (char == '"' && !inSingleQuote) {
          final isEscaped = j > 0 && line[j - 1] == r'\';
          if (!isEscaped) inDoubleQuote = !inDoubleQuote;
        }

        if (char == ';' && !inSingleQuote && !inDoubleQuote) {
          final query = buffer.toString().trim();
          if (query.isNotEmpty) {
            queries.add(query);
          }
          buffer.clear();
        } else {
          buffer.write(char);
        }
      }

      if (buffer.isNotEmpty && !inMultiLineComment) {
        buffer.write('\n');
      }
    }

    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      queries.add(remaining);
    }

    return queries;
  }
}