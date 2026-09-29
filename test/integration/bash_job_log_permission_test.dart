/// Verifies that background bash job log files are created with owner-only
/// permissions (mode 0600) so sensitive command output (env vars, tokens)
/// cannot be read by other local users.
///
/// The test starts a real background job via [LocalExecutionEnv], waits for
/// the log file to exist, and asserts its mode bits.
@TestOn('vm')
@Tags(['io', 'integration'])
@Timeout(Duration(seconds: 30))
library;

import 'dart:io';

import 'package:flutter_agent_harness/io.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late LocalExecutionEnv env;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('job-log-perm-test-');
    // Resolve symlinks so the path the env uses matches stat paths exactly.
    tempDir = Directory(await tempDir.resolveSymbolicLinks());
    env = LocalExecutionEnv(cwd: tempDir.path);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'bash job log file is created with mode 0600 (owner-only)',
    () async {
      // Skip on Windows — chmod is a no-op there.
      if (Platform.isWindows) {
        return;
      }

      // Ensure the bash_jobs directory exists before the job starts —
      // ShellJobRegistry.start() normally calls createDir, but here we call
      // startShellJob directly.
      final logDir = Directory('${tempDir.path}/.fah/bash_jobs');
      await logDir.create(recursive: true);

      // Start a trivial background job.
      final result = await env.startShellJob(
        'echo "sensitive output"',
        id: 'sh-1-test',
        logPath: '${logDir.path}/sh-1-test.log',
      );
      expect(result.isOk, isTrue, reason: 'job should start: ${result.errorOrNull}');

      final job = result.valueOrNull!;
      final logFile = File(job.logPath);

      // Wait up to 2s for the log file to appear (the process writes it).
      for (var i = 0; i < 40; i++) {
        if (logFile.existsSync()) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      // Wait for the job to settle so chmod has fired.
      await job.settled;
      // Small extra delay to let the unawaited chmod future complete.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(logFile.existsSync(), isTrue, reason: 'log file should exist');

      // Read mode via `stat -f "%Lp"` (macOS) or `stat --format=%a` (Linux).
      late String mode;
      if (Platform.isMacOS) {
        final statResult =
            await Process.run('stat', ['-f', '%Lp', logFile.path]);
        mode = (statResult.stdout as String).trim();
      } else {
        final statResult =
            await Process.run('stat', ['--format=%a', logFile.path]);
        mode = (statResult.stdout as String).trim();
      }
      expect(
        mode,
        '600',
        reason:
            'bash job log should be owner-only (0600) to protect sensitive output',
      );
    },
  );
}
