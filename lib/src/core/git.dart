import 'process_runner.dart';

/// Working-tree state of the project, from `git status --porcelain`.
class GitStatus {
  const GitStatus({required this.isRepo, this.changes = const []});

  final bool isRepo;

  /// Porcelain lines for uncommitted (including untracked) changes.
  final List<String> changes;

  bool get isClean => isRepo && changes.isEmpty;
}

Future<GitStatus> readGitStatus(ProcessRunner runner, String root) async {
  try {
    final result = await runner.run('git', [
      '-C',
      root,
      'status',
      '--porcelain',
    ]);
    if (result.exitCode != 0) return const GitStatus(isRepo: false);
    return GitStatus(
      isRepo: true,
      changes: [
        for (final line in result.stdout.toString().split('\n'))
          if (line.trim().isNotEmpty) line,
      ],
    );
  } on Exception {
    return const GitStatus(isRepo: false);
  }
}
