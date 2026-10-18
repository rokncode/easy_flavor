import 'dart:io';

import 'package:easy_flavor/easy_flavor.dart';

Future<void> main(List<String> args) async {
  final code = await EasyFlavorCommandRunner().run(args);
  await Future.wait([stdout.close(), stderr.close()]);
  exit(code);
}
