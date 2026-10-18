import 'package:easy_flavor/src/ios/pbxproj.dart';
import 'package:test/test.dart';

import '../helpers/fixtures.dart';

void main() {
  for (final fixture in ['fresh_kts', 'cocoapods']) {
    test('round-trips the $fixture project byte for byte', () {
      final dir = copyFixture(fixture);
      final source = read(dir, 'ios/Runner.xcodeproj/project.pbxproj');
      expect(PbxProject.parse(source).encode(), source);
    });
  }

  const minimal = '''
// !\$*UTF8*\$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 54;
	objects = {

/* Begin PBXFileReference section */
		BBBB /* b.txt */ = {isa = PBXFileReference; path = b.txt; sourceTree = "<group>"; };
		AAAA /* a.txt */ = {isa = PBXFileReference; path = a.txt; sourceTree = "<group>"; };
/* End PBXFileReference section */
/* Begin PBXGroup section */
		CCCC = {
			isa = PBXGroup;
			children = (
				AAAA /* a.txt */,
				BBBB /* b.txt */,
			);
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXProject section */
		DDDD /* Project object */ = {
			isa = PBXProject;
			mainGroup = CCCC;
			targets = (
			);
		};
/* End PBXProject section */
	};
	rootObject = DDDD /* Project object */;
}
''';

  test('keeps unsorted sections, compact spacing and unannotated ids', () {
    expect(PbxProject.parse(minimal).encode(), minimal);
  });

  test('new objects are appended to unsorted sections', () {
    final pbx = PbxProject.parse(minimal)
      ..add('0000', {
        'isa': 'PBXFileReference',
        'path': 'z.txt',
      }, comment: 'z.txt');
    expect(
      pbx.encode(),
      contains(
        'AAAA /* a.txt */ = {isa = PBXFileReference; path = a.txt; sourceTree = "<group>"; };\n'
        '\t\t0000 /* z.txt */ = {isa = PBXFileReference; path = z.txt; };\n',
      ),
    );
  });

  test('new objects are sorted into sorted sections; new sections are added', () {
    final pbx = PbxProject.parse(minimal)
      ..add('CCC0', {
        'isa': 'PBXGroup',
        'children': <Object>[],
        'sourceTree': '<group>',
      }, comment: 'G')
      ..add('EEEE', {
        'isa': 'XCBuildConfiguration',
        'buildSettings': <String, Object>{},
        'name': 'Debug',
      }, comment: 'Debug');
    final out = pbx.encode();
    expect(out.indexOf('CCC0 /* G */'), lessThan(out.indexOf('CCCC = {')));
    expect(
      out,
      contains(
        '\n/* Begin XCBuildConfiguration section */\n\t\tEEEE /* Debug */ = {\n',
      ),
    );
    expect(
      PbxProject.parse(out).encode(),
      out,
      reason: 'output re-parses identically',
    );
  });

  test('quotes and escapes strings like Xcode', () {
    final pbx = PbxProject.parse(minimal);
    pbx.object('AAAA')!
      ..['a'] = r'$(inherited)'
      ..['b'] = 'apple-generic'
      ..['c'] = 'https://example.com'
      ..['d'] = 'say "hi"\n'
      ..['e'] = ''
      ..['f'] = 'Flutter/Debug.xcconfig';
    final out = pbx.encode();
    expect(
      out,
      contains(
        r'a = "$(inherited)"; b = "apple-generic"; c = "https://example.com"; '
        r'd = "say \"hi\"\n"; e = ""; f = Flutter/Debug.xcconfig; ',
      ),
    );
    final back = PbxProject.parse(out).object('AAAA')!;
    expect(back['d'], 'say "hi"\n');
    expect(back['e'], '');
  });

  test('ids are deterministic, 24 hex digits, and avoid collisions', () {
    final pbx = PbxProject.parse(minimal);
    final id = pbx.newId('seed');
    expect(id, matches(RegExp(r'^[0-9A-F]{24}$')));
    expect(PbxProject.parse(minimal).newId('seed'), id);
    pbx.add(id, {'isa': 'PBXGroup'});
    expect(pbx.newId('seed'), isNot(id));
  });

  test('rejects malformed input', () {
    for (final bad in ['{', '{ a = ; }', '{ a = (b, }', '{ a = "x; }', '{}']) {
      expect(
        () => PbxProject.parse(bad),
        throwsA(isA<PbxParseException>()),
        reason: bad,
      );
    }
  });
}
