import 'package:easy_flavor/src/android/gradle_parser.dart';
import 'package:test/test.dart';

void main() {
  test('finds nested named blocks with arguments', () {
    const src = '''
android {
    defaultConfig { applicationId = "a" }
    productFlavors {
        create("dev") { dimension = "x" }
        prod { }
    }
}
''';
    final android = parseGradleBlocks(src).single;
    expect(android.name, 'android');
    expect(android.children.map((c) => c.name), [
      'defaultConfig',
      'productFlavors',
    ]);
    final flavors = android.child('productFlavors')!.children;
    expect(
      [for (final f in flavors) (f.name, f.args)],
      [('create', '"dev"'), ('prod', null)],
    );
    expect(src.substring(android.open, android.close + 1), startsWith('{'));
    expect(src[android.close], '}');
  });

  test('ignores braces in strings, templates and comments', () {
    const src = r'''
// } comment brace
/* { block comment */
val a = "}"
val b = "${listOf("}").first()}"
val c = """
  { triple
"""
def d = '{'
android {
    x "{${foo { "}" }}"
}
''';
    final blocks = parseGradleBlocks(src);
    expect(blocks.map((b) => b.name), ['android']);
  });

  test('dotted receivers are part of the name; bare braces are anonymous', () {
    final blocks = parseGradleBlocks('a { list.forEach { it -> } }\n{ }');
    expect(blocks.first.children.single.name, 'list.forEach');
    expect(blocks.last.name, '');
  });

  test('unbalanced braces throw', () {
    expect(() => parseGradleBlocks('android {'), throwsFormatException);
    expect(() => parseGradleBlocks('}'), throwsFormatException);
  });

  test('unquoteGradleString', () {
    expect(unquoteGradleString('"dev"'), 'dev');
    expect(unquoteGradleString(" 'dev' "), 'dev');
    expect(unquoteGradleString(r'"$x"'), isNull);
    expect(unquoteGradleString('dev'), isNull);
  });
}
