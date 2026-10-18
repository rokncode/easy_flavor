/// A `name { ... }` or `name(args) { ... }` block in a Gradle build script.
class GradleBlock {
  GradleBlock({
    required this.name,
    required this.args,
    required this.start,
    required this.open,
    required this.parent,
  });

  /// Identifier before the brace: `android`, `productFlavors`, `create`, `dev`.
  /// Empty for anonymous blocks such as lambdas.
  final String name;

  /// Text between the parentheses, if any (`"dev"` for `create("dev") {`).
  final String? args;

  /// Offset of the first character of [name] (or of `{` when unnamed).
  final int start;

  /// Offset of `{`.
  final int open;

  /// Offset of the matching `}`.
  late final int close;

  final GradleBlock? parent;
  final List<GradleBlock> children = [];

  /// Body text between the braces.
  String body(String source) => source.substring(open + 1, close);

  GradleBlock? child(String name) {
    for (final c in children) {
      if (c.name == name) return c;
    }
    return null;
  }

  @override
  String toString() => 'GradleBlock($name, $start..$close)';
}

/// Parses the block structure of a Groovy or Kotlin DSL Gradle script.
///
/// This is not a full parser: it only finds braces, while correctly skipping
/// comments, string literals (including triple-quoted strings and `${...}`
/// templates) and character literals, which is what makes brace matching
/// reliable. Returns the top-level blocks.
///
/// Throws [FormatException] if braces are unbalanced.
List<GradleBlock> parseGradleBlocks(String source) =>
    _GradleScanner(source).scan();

class _GradleScanner {
  _GradleScanner(this.s);

  final String s;
  int i = 0;

  List<GradleBlock> scan() {
    final roots = <GradleBlock>[];
    final stack = <GradleBlock>[];
    while (i < s.length) {
      final c = s[i];
      if (_startsWith('//')) {
        _skipLineComment();
      } else if (_startsWith('/*')) {
        _skipBlockComment();
      } else if (c == '"' || c == "'") {
        _skipString();
      } else if (c == '{') {
        final block = _namedBlockAt(i, stack.isEmpty ? null : stack.last);
        (stack.isEmpty ? roots : stack.last.children).add(block);
        stack.add(block);
        i++;
      } else if (c == '}') {
        if (stack.isEmpty) throw FormatException('Unexpected "}"', s, i);
        stack.removeLast().close = i;
        i++;
      } else {
        i++;
      }
    }
    if (stack.isNotEmpty) {
      throw FormatException('Unclosed "{"', s, stack.last.open);
    }
    return roots;
  }

  bool _startsWith(String p) => s.startsWith(p, i);

  void _skipLineComment() {
    final end = s.indexOf('\n', i);
    i = end == -1 ? s.length : end;
  }

  void _skipBlockComment() {
    final end = s.indexOf('*/', i + 2);
    if (end == -1) throw FormatException('Unclosed comment', s, i);
    i = end + 2;
  }

  /// Skips a string starting at [i] (which is a quote character).
  void _skipString() {
    final q = s[i];
    final triple = _startsWith(q * 3);
    final delimiter = triple ? q * 3 : q;
    // Groovy single-quoted strings have no templates; Kotlin has no
    // single-quoted strings (only char literals, which also have none).
    final templates = q == '"';
    final start = i;
    i += delimiter.length;
    while (i < s.length) {
      if (!triple && s[i] == r'\') {
        i += 2;
        continue;
      }
      if (_startsWith(delimiter)) {
        i += delimiter.length;
        return;
      }
      if (!triple && s[i] == '\n') {
        // Unterminated single-line string; treat the line end as its end so
        // a stray quote cannot swallow the rest of the file.
        return;
      }
      if (templates && _startsWith(r'${')) {
        i += 2;
        _skipTemplateExpression();
        continue;
      }
      i++;
    }
    throw FormatException('Unterminated string', s, start);
  }

  /// Skips to just after the `}` closing a `${` template expression.
  void _skipTemplateExpression() {
    var depth = 1;
    while (i < s.length) {
      final c = s[i];
      if (c == '"' || c == "'") {
        _skipString();
        continue;
      }
      if (c == '{') depth++;
      if (c == '}' && --depth == 0) {
        i++;
        return;
      }
      i++;
    }
  }

  /// Builds a block for the `{` at [brace], reading the name (and optional
  /// parenthesised arguments) that precede it.
  GradleBlock _namedBlockAt(int brace, GradleBlock? parent) {
    var j = brace - 1;
    while (j >= 0 && _isSpace(s[j])) {
      j--;
    }
    String? args;
    if (j >= 0 && s[j] == ')') {
      final close = j;
      var depth = 0;
      for (; j >= 0; j--) {
        if (s[j] == ')') depth++;
        if (s[j] == '(' && --depth == 0) break;
      }
      if (j < 0) {
        return GradleBlock(
          name: '',
          args: null,
          start: brace,
          open: brace,
          parent: parent,
        );
      }
      args = s.substring(j + 1, close).trim();
      j--;
      while (j >= 0 && _isSpace(s[j])) {
        j--;
      }
    }
    final end = j + 1;
    while (j >= 0 && _isIdentifierChar(s[j])) {
      j--;
    }
    final name = s.substring(j + 1, end);
    return GradleBlock(
      name: name,
      args: args,
      start: name.isEmpty ? brace : j + 1,
      open: brace,
      parent: parent,
    );
  }

  static bool _isSpace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r';

  static bool _isIdentifierChar(String c) {
    final u = c.codeUnitAt(0);
    return (u >= 0x30 && u <= 0x39) || // 0-9
        (u >= 0x41 && u <= 0x5a) || // A-Z
        (u >= 0x61 && u <= 0x7a) || // a-z
        c == '_' ||
        c == '.';
  }
}

/// Unquotes a Gradle string literal argument such as `"dev"` or `'dev'`.
/// Returns null if [text] is not a single simple literal.
String? unquoteGradleString(String text) {
  final t = text.trim();
  if (t.length < 2) return null;
  final q = t[0];
  if ((q != '"' && q != "'") || t[t.length - 1] != q) return null;
  final inner = t.substring(1, t.length - 1);
  if (inner.contains(q) || inner.contains(r'$')) return null;
  return inner;
}
