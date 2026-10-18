/// Reader and writer for Xcode `project.pbxproj` files (the OpenStep
/// property-list dialect Xcode uses).
///
/// Values are `String`, `List<Object>` or `Map<String, Object>` (insertion
/// ordered). [PbxProject.encode] reproduces Xcode's own formatting (sections
/// per `isa`, single-line `PBXBuildFile`/`PBXFileReference` entries, the
/// `/* comment */` annotations after object ids), so an unmodified project
/// round-trips byte for byte and edits produce minimal diffs.
library;

class PbxParseException implements Exception {
  PbxParseException(this.message, this.offset);

  final String message;
  final int offset;

  @override
  String toString() => 'PbxParseException: $message (at offset $offset)';
}

typedef PbxObject = Map<String, Object>;

class PbxProject {
  PbxProject._(this.root, this._comments)
    : _parsedIds = {...(root['objects']! as Map<String, Object>).keys};

  /// Parses project.pbxproj [source].
  factory PbxProject.parse(String source) {
    final parser = _Parser(source);
    final root = parser.parseDocument();
    if (root['objects'] is! Map || root['rootObject'] is! String) {
      throw PbxParseException(
        'Not an Xcode project (no objects/rootObject)',
        0,
      );
    }
    return PbxProject._(root, parser.comments)
      .._compactSections.addAll(
        RegExp(
          r'[^\n]\n/\* Begin (\w+) section \*/',
        ).allMatches(source).map((m) => m.group(1)!),
      );
  }

  /// Sections written without the blank line Xcode puts before them (some
  /// tools, e.g. Flutter's Swift Package Manager migration, omit it).
  final _compactSections = <String>{};

  final Map<String, Object> root;

  /// `/* annotation */` written after each object id.
  final Map<String, String> _comments;

  /// Ids present when parsed; their relative order is preserved on write.
  final Set<String> _parsedIds;

  Map<String, Object> get objects => root['objects']! as Map<String, Object>;

  String get rootObjectId => root['rootObject']! as String;

  PbxObject get rootObject => object(rootObjectId)!;

  PbxObject? object(String id) => objects[id] as PbxObject?;

  String? comment(String id) => _comments[id];

  /// Adds [object] under [id] with annotation [comment]. Keys are written in
  /// the order given; Xcode's convention is `isa` first, then alphabetical.
  void add(String id, PbxObject object, {String? comment}) {
    objects[id] = object;
    if (comment != null) _comments[id] = comment;
  }

  void remove(String id) {
    objects.remove(id);
    _comments.remove(id);
  }

  /// Ids and objects with the given `isa`.
  Iterable<MapEntry<String, PbxObject>> ofType(String isa) sync* {
    for (final e in objects.entries) {
      final o = e.value;
      if (o is Map && o['isa'] == isa) yield MapEntry(e.key, o as PbxObject);
    }
  }

  /// A new 24-hex-digit object id derived from [seed], so repeated runs
  /// produce the same ids. Collisions with existing objects are avoided.
  String newId(String seed) {
    for (var attempt = 0; ; attempt++) {
      final id = _hashId('$seed#$attempt');
      if (!objects.containsKey(id)) return id;
    }
  }

  String encode() => _Writer(this).write();
}

// ---------------------------------------------------------------------------
// Parsing

class _Parser {
  _Parser(this.s);

  final String s;
  int i = 0;
  final comments = <String, String>{};

  Map<String, Object> parseDocument() {
    _skip();
    final value = _value();
    _skip();
    if (i != s.length) {
      throw PbxParseException('Unexpected trailing content', i);
    }
    if (value is! Map<String, Object>) {
      throw PbxParseException('Top level must be a dictionary', 0);
    }
    return value;
  }

  Object _value() {
    _skip();
    if (i >= s.length) throw PbxParseException('Unexpected end of file', i);
    final c = s[i];
    if (c == '{') return _dict();
    if (c == '(') return _array();
    return _string();
  }

  Map<String, Object> _dict() {
    i++; // {
    final map = <String, Object>{};
    while (true) {
      _skip();
      if (i >= s.length) throw PbxParseException('Unclosed dictionary', i);
      if (s[i] == '}') {
        i++;
        return map;
      }
      final key = _string();
      _skip();
      _expect('=');
      final value = _value();
      _skip();
      _expect(';');
      map[key] = value;
    }
  }

  List<Object> _array() {
    i++; // (
    final list = <Object>[];
    while (true) {
      _skip();
      if (i >= s.length) throw PbxParseException('Unclosed array', i);
      if (s[i] == ')') {
        i++;
        return list;
      }
      list.add(_value());
      _skip();
      if (i < s.length && s[i] == ',') {
        i++;
      } else {
        _skip();
        _expect(')', consume: false);
      }
    }
  }

  String _string() {
    if (s[i] == '"') return _quoted();
    final start = i;
    while (i < s.length && _isUnquotedChar(s.codeUnitAt(i))) {
      i++;
    }
    if (i == start) throw PbxParseException('Unexpected "${s[i]}"', i);
    final value = s.substring(start, i);
    _captureComment(value);
    return value;
  }

  String _quoted() {
    final start = i;
    i++; // "
    final b = StringBuffer();
    while (true) {
      if (i >= s.length) throw PbxParseException('Unterminated string', start);
      final c = s[i];
      if (c == '"') {
        i++;
        break;
      }
      if (c == r'\') {
        i++;
        if (i >= s.length) throw PbxParseException('Bad escape', i);
        final e = s[i];
        switch (e) {
          case 'n':
            b.write('\n');
          case 't':
            b.write('\t');
          case 'r':
            b.write('\r');
          case '"':
          case r'\':
          case "'":
            b.write(e);
          case 'U':
            final hex = s.substring(i + 1, i + 5);
            b.writeCharCode(int.parse(hex, radix: 16));
            i += 4;
          default:
            b.write(e);
        }
        i++;
        continue;
      }
      b.write(c);
      i++;
    }
    return b.toString();
  }

  /// Records `ID /* comment */` so annotations survive a round trip.
  void _captureComment(String token) {
    var j = i;
    while (j < s.length && (s[j] == ' ' || s[j] == '\t')) {
      j++;
    }
    if (!s.startsWith('/*', j)) return;
    final end = s.indexOf('*/', j + 2);
    if (end == -1) return;
    comments.putIfAbsent(token, () => s.substring(j + 2, end).trim());
  }

  void _skip() {
    while (i < s.length) {
      final c = s[i];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        i++;
      } else if (s.startsWith('//', i)) {
        final end = s.indexOf('\n', i);
        i = end == -1 ? s.length : end + 1;
      } else if (s.startsWith('/*', i)) {
        final end = s.indexOf('*/', i + 2);
        if (end == -1) throw PbxParseException('Unclosed comment', i);
        i = end + 2;
      } else {
        return;
      }
    }
  }

  void _expect(String c, {bool consume = true}) {
    if (i >= s.length || s[i] != c) {
      throw PbxParseException('Expected "$c"', i);
    }
    if (consume) i++;
  }
}

// Characters that may appear in an unquoted string.
bool _isUnquotedChar(int u) =>
    (u >= 0x30 && u <= 0x39) || // 0-9
    (u >= 0x41 && u <= 0x5a) || // A-Z
    (u >= 0x61 && u <= 0x7a) || // a-z
    u == 0x5f || // _
    u == 0x24 || // $
    u == 0x2f || // /
    u == 0x3a || // :
    u == 0x2e || // .
    u == 0x2d; // - (read leniently; Xcode quotes it when writing)

// Characters Xcode writes without quotes.
bool _isWriteSafeChar(int u) => _isUnquotedChar(u) && u != 0x2d;

// ---------------------------------------------------------------------------
// Writing

/// Keys whose values are object ids that Xcode writes without annotation.
const _unannotatedKeys = {'remoteGlobalIDString', 'TestTargetID'};

/// Object types Xcode writes on a single line.
const _singleLineTypes = {'PBXBuildFile', 'PBXFileReference'};

class _Writer {
  _Writer(this.project);

  final PbxProject project;
  final b = StringBuffer();

  String write() {
    b.write('// !\$*UTF8*\$!\n{\n');
    project.root.forEach((key, value) {
      b.write('\t${_str(key)} = ');
      if (key == 'objects') {
        _objects();
      } else {
        _value(value, 1, annotate: true);
      }
      b.write(';\n');
    });
    b.write('}\n');
    return b.toString();
  }

  void _objects() {
    final byType = <String, List<String>>{};
    project.objects.forEach((id, o) {
      final isa = (o as Map)['isa'] as String? ?? '';
      byType.putIfAbsent(isa, () => []).add(id);
    });
    final types = byType.keys.toList()..sort();
    b.write('{\n');
    for (final isa in types) {
      final ids = _sectionOrder(byType[isa]!);
      if (!project._compactSections.contains(isa)) b.write('\n');
      b.write('/* Begin $isa section */\n');
      for (final id in ids) {
        final o = project.objects[id]! as Map<String, Object>;
        b.write('\t\t${_ref(id)} = ');
        if (_singleLineTypes.contains(isa)) {
          _inline(o);
        } else {
          _dict(o, 2);
        }
        b.write(';\n');
      }
      b.write('/* End $isa section */\n');
    }
    b.write('\t}');
  }

  /// Xcode sorts objects by id within a section, but tools such as
  /// CocoaPods do not. Keep the parsed order; new objects are merged in
  /// sorted position if the section was sorted, otherwise appended.
  List<String> _sectionOrder(List<String> ids) {
    final parsed = [
      for (final id in ids)
        if (project._parsedIds.contains(id)) id,
    ];
    final added = [
      for (final id in ids)
        if (!project._parsedIds.contains(id)) id,
    ]..sort();
    var sorted = true;
    for (var i = 1; i < parsed.length; i++) {
      if (parsed[i - 1].compareTo(parsed[i]) > 0) {
        sorted = false;
        break;
      }
    }
    return sorted ? ([...parsed, ...added]..sort()) : [...parsed, ...added];
  }

  void _value(Object value, int indent, {required bool annotate}) {
    switch (value) {
      case final Map<String, Object> m:
        _dict(m, indent);
      case final List<Object> l:
        _array(l, indent);
      case final String s:
        b.write(annotate ? _ref(s) : _str(s));
      default:
        throw StateError('Unsupported value ${value.runtimeType}');
    }
  }

  void _dict(Map<String, Object> m, int indent) {
    final pad = '\t' * (indent + 1);
    b.write('{\n');
    m.forEach((key, value) {
      b.write('$pad${_str(key)} = ');
      _value(value, indent + 1, annotate: !_unannotatedKeys.contains(key));
      b.write(';\n');
    });
    b.write('${'\t' * indent}}');
  }

  void _array(List<Object> l, int indent) {
    final pad = '\t' * (indent + 1);
    b.write('(\n');
    for (final v in l) {
      b.write(pad);
      _value(v, indent + 1, annotate: true);
      b.write(',\n');
    }
    b.write('${'\t' * indent})');
  }

  void _inline(Object value) {
    switch (value) {
      case final Map<String, Object> m:
        b.write('{');
        m.forEach((key, v) {
          b.write('${_str(key)} = ');
          _inline(v);
          b.write('; ');
        });
        b.write('}');
      case final List<Object> l:
        b.write('(');
        for (final v in l) {
          _inline(v);
          b.write(', ');
        }
        b.write(')');
      case final String s:
        b.write(_ref(s));
    }
  }

  /// [s] followed by its annotation if it is an annotated object id.
  String _ref(String s) {
    final comment = project.objects.containsKey(s) ? project.comment(s) : null;
    return comment == null ? _str(s) : '${_str(s)} /* $comment */';
  }
}

/// Quotes [s] the way Xcode does.
String _str(String s) {
  if (s.isNotEmpty &&
      s.codeUnits.every(_isWriteSafeChar) &&
      !s.contains('//') &&
      !s.contains('/*')) {
    return s;
  }
  final b = StringBuffer('"');
  for (final r in s.runes) {
    switch (r) {
      case 0x22:
        b.write(r'\"');
      case 0x5c:
        b.write(r'\\');
      case 0x0a:
        b.write(r'\n');
      case 0x09:
        b.write(r'\t');
      default:
        b.writeCharCode(r);
    }
  }
  b.write('"');
  return b.toString();
}

/// Deterministic 96-bit id (24 uppercase hex digits) from three FNV-1a
/// hashes with different offsets.
String _hashId(String seed) {
  final parts = <String>[];
  for (final offset in [0x811c9dc5, 0x01000193, 0x5bd1e995]) {
    var h = offset;
    for (final u in seed.codeUnits) {
      h ^= u;
      h = (h * 0x01000193) & 0xffffffff;
    }
    parts.add(h.toRadixString(16).padLeft(8, '0'));
  }
  return parts.join().toUpperCase();
}
