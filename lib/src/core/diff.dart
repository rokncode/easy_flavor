import 'package:mason_logger/mason_logger.dart';

/// A unified diff of [before] -> [after] with [context] lines around each
/// change, colored when the terminal supports it.
String unifiedDiff(
  String before,
  String after, {
  required String path,
  int context = 3,
}) {
  final a = before.isEmpty ? <String>[] : before.split('\n');
  final b = after.isEmpty ? <String>[] : after.split('\n');
  final ops = _diff(a, b);

  final out = StringBuffer()
    ..writeln(styleBold.wrap('--- a/$path'))
    ..writeln(styleBold.wrap('+++ b/$path'));
  // Group operations into hunks around changes.
  var i = 0;
  while (i < ops.length) {
    if (ops[i].kind == _Kind.same) {
      i++;
      continue;
    }
    final start = (i - context).clamp(0, ops.length);
    var end = i;
    // Extend while further changes are within 2 * context lines.
    var lastChange = i;
    while (end < ops.length) {
      if (ops[end].kind != _Kind.same) lastChange = end;
      if (end - lastChange > 2 * context) break;
      end++;
    }
    end = (lastChange + context + 1).clamp(0, ops.length);
    final hunk = ops.sublist(start, end);
    final aStart = hunk.first.aLine;
    final bStart = hunk.first.bLine;
    final aLen = hunk.where((o) => o.kind != _Kind.add).length;
    final bLen = hunk.where((o) => o.kind != _Kind.remove).length;
    out.writeln(cyan.wrap('@@ -${aStart + 1},$aLen +${bStart + 1},$bLen @@'));
    for (final o in hunk) {
      switch (o.kind) {
        case _Kind.same:
          out.writeln(' ${o.text}');
        case _Kind.add:
          out.writeln(green.wrap('+${o.text}'));
        case _Kind.remove:
          out.writeln(red.wrap('-${o.text}'));
      }
    }
    i = end;
  }
  return out.toString().trimRight();
}

enum _Kind { same, add, remove }

class _Op {
  _Op(this.kind, this.text, this.aLine, this.bLine);

  final _Kind kind;
  final String text;

  /// Line numbers (0-based) in a and b where this op sits.
  final int aLine;
  final int bLine;
}

/// Line diff via LCS, after trimming the common prefix and suffix (which
/// keeps the table small for typical edits to large files).
List<_Op> _diff(List<String> a, List<String> b) {
  var prefix = 0;
  while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < a.length - prefix &&
      suffix < b.length - prefix &&
      a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
    suffix++;
  }
  final am = a.sublist(prefix, a.length - suffix);
  final bm = b.sublist(prefix, b.length - suffix);

  // lcs[i][j] = LCS length of am[i..] and bm[j..].
  final lcs = List.generate(
    am.length + 1,
    (_) => List.filled(bm.length + 1, 0),
  );
  for (var i = am.length - 1; i >= 0; i--) {
    for (var j = bm.length - 1; j >= 0; j--) {
      lcs[i][j] = am[i] == bm[j]
          ? lcs[i + 1][j + 1] + 1
          : (lcs[i + 1][j] >= lcs[i][j + 1] ? lcs[i + 1][j] : lcs[i][j + 1]);
    }
  }

  final ops = <_Op>[
    for (var k = 0; k < prefix; k++) _Op(_Kind.same, a[k], k, k),
  ];
  var i = 0, j = 0;
  while (i < am.length || j < bm.length) {
    if (i < am.length && j < bm.length && am[i] == bm[j]) {
      ops.add(_Op(_Kind.same, am[i], prefix + i, prefix + j));
      i++;
      j++;
    } else if (i < am.length &&
        (j == bm.length || lcs[i + 1][j] >= lcs[i][j + 1])) {
      // Removals before additions, like diff(1).
      ops.add(_Op(_Kind.remove, am[i], prefix + i, prefix + j));
      i++;
    } else {
      ops.add(_Op(_Kind.add, bm[j], prefix + i, prefix + j));
      j++;
    }
  }
  for (var k = 0; k < suffix; k++) {
    final ai = a.length - suffix + k, bi = b.length - suffix + k;
    ops.add(_Op(_Kind.same, a[ai], ai, bi));
  }
  return ops;
}
