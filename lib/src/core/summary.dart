import 'package:mason_logger/mason_logger.dart';

import '../config/easy_flavor_config.dart';
import 'change_set.dart';

/// Prints the flavor table.
void printFlavorTable(Logger logger, EasyFlavorConfig config) {
  final headers = [
    'Flavor',
    'App name',
    'Android applicationId',
    'iOS bundle id',
    if (config.firebase) 'Firebase project',
  ];
  final rows = [
    for (final f in config.flavors)
      [
        f.name,
        f.appName,
        f.androidId,
        f.iosBundleId,
        if (config.firebase) f.firebaseProjectId ?? '(prompt)',
      ],
  ];
  final widths = [
    for (var i = 0; i < headers.length; i++)
      [
        headers[i],
        ...rows.map((r) => r[i]),
      ].map((s) => s.length).reduce((a, b) => a > b ? a : b),
  ];
  String line(List<String> cells) => [
    for (var i = 0; i < cells.length; i++) cells[i].padRight(widths[i]),
  ].join('  ').trimRight();

  logger
    ..info(styleBold.wrap(line(headers)))
    ..info(widths.map((w) => '-' * w).join('  '));
  for (final r in rows) {
    logger.info(line(r));
  }
}

/// Prints `flutter run` commands for every flavor.
void printRunCommands(Logger logger, EasyFlavorConfig config) {
  logger.info('');
  logger.info(styleBold.wrap('Run your flavors:'));
  for (final f in config.flavors) {
    logger.info('  flutter run --flavor ${f.name} -t lib/main_${f.name}.dart');
  }
}

/// Prints the planned changes, one line per file.
void printChanges(Logger logger, ChangeSet changes) {
  if (changes.isEmpty) {
    logger.info('No changes needed; the project is already up to date.');
    return;
  }
  for (final c in changes.changes) {
    final tag = switch (c.kind) {
      ChangeKind.create => green.wrap('create'),
      ChangeKind.modify => yellow.wrap('modify'),
      ChangeKind.delete => red.wrap('delete'),
    };
    final reason = c.reason == null ? '' : darkGray.wrap('  (${c.reason})');
    logger.info('  $tag  ${c.path}$reason');
  }
  for (final c in changes.commands) {
    logger.info(
      '  ${lightMagenta.wrap('run   ')}  ${c.display}${darkGray.wrap('  (${c.reason})')}',
    );
  }
}
