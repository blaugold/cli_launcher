import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('run global version', () {
    final (:stdout, :stderr) = runExampleCli(workingDirectory: '.');

    expect(
      stdout,
      matches(
        RegExp(
          '.*Running v1 with local version null and global version 1.0.0.*',
        ),
      ),
    );
  });

  test('run global workspace version', () {
    final (:stdout, :stderr) = runExampleCli(
      workingDirectory: '.',
      executable: 'example_workspace',
    );

    expect(
      stdout,
      matches(
        RegExp(
          '.*Running workspace example with local version null and global version 1.0.0.*',
        ),
      ),
    );
  });

  group('run in Flutter workspace', () {
    const workspaceRoot = './fixture_packages/flutter_workspace';
    const sourcePackage = '$workspaceRoot/packages/example_flutter_workspace';
    const flutterPackage = '$workspaceRoot/packages/flutter_package';
    const executable = 'example_flutter_workspace';

    test('from workspace root', () {
      final (:stdout, :stderr) = runExampleCli(
        workingDirectory: workspaceRoot,
        executable: executable,
      );

      expect(
        stdout,
        matches(
          RegExp(
            '.*Running flutter workspace example with local version null and global version 1.0.0.*',
          ),
        ),
      );
    });

    test('from Flutter member package', () {
      final (:stdout, :stderr) = runExampleCli(
        workingDirectory: flutterPackage,
        executable: executable,
      );

      expect(
        stdout,
        matches(
          RegExp(
            '.*Running flutter workspace example with local version null and global version 1.0.0.*',
          ),
        ),
      );
    });

    test('from source package with up to date deps', () {
      _setFlutterWorkspaceUpToDateTimestamps(DateTime.now());

      final (:stdout, :stderr) = runExampleCli(
        workingDirectory: sourcePackage,
        executable: executable,
      );

      expect(
        stdout,
        matches(
          RegExp(
            '.*Running flutter workspace example with '
            'local version 1.0.0 and global version 1.0.0.*',
          ),
        ),
      );
    });

    test('from source package without pubspec.lock runs flutter pub get', () {
      final lockFile = File('$workspaceRoot/pubspec.lock');
      final hadLock = lockFile.existsSync();
      String? lockContents;
      if (hadLock) {
        lockContents = lockFile.readAsStringSync();
        lockFile.deleteSync();
      }

      try {
        final (:stdout, :stderr) = runExampleCli(
          workingDirectory: sourcePackage,
          executable: executable,
        );

        // pub get output is captured by cli_launcher, so check stderr where
        // debug output would appear, or just verify the CLI ran successfully
        // with the correct version (which requires pub get to have succeeded).
        expect(
          stdout,
          matches(
            RegExp(
              '.*Running flutter workspace example with '
              'local version 1.0.0 and global version 1.0.0.*',
            ),
          ),
        );
      } finally {
        // Restore the lock file so other tests aren't affected.
        if (hadLock) {
          lockFile.writeAsStringSync(lockContents!);
        }
      }
    });

    test('from source package with out of date deps runs flutter pub get', () {
      final pubspecFile = File('$sourcePackage/pubspec.yaml');
      final lockFile = File('$workspaceRoot/pubspec.lock');
      final pubspecTimestamp = DateTime.now();
      final lockTimestamp = pubspecTimestamp.subtract(const Duration(hours: 1));
      pubspecFile.setLastModifiedSync(pubspecTimestamp);
      lockFile.setLastModifiedSync(lockTimestamp);

      final (:stdout, :stderr) = runExampleCli(
        workingDirectory: sourcePackage,
        executable: executable,
      );

      // pub get output is captured by cli_launcher, so just verify the CLI
      // ran successfully with the correct version (which requires pub get to
      // have succeeded).
      expect(
        stdout,
        matches(
          RegExp(
            '.*Running flutter workspace example with '
            'local version 1.0.0 and global version 1.0.0.*',
          ),
        ),
      );
    });
  });

  group('run in source package', () {
    test('with same local and global version', () {
      final (:stdout, :stderr) = runExampleCli(
        workingDirectory: 'fixture_packages/example_v1',
      );

      expect(
        stdout,
        matches(
          RegExp(
            '.*Running v1 with local version 1.0.0 and global version 1.0.0.*',
          ),
        ),
      );
    });

    test('with different local and global version', () {
      final (:stdout, :stderr) = runExampleCli(
        workingDirectory: 'fixture_packages/example_v2',
      );

      expect(
        stdout,
        matches(
          RegExp(
            '.*Running v2 with local version 2.0.0 and global version 1.0.0.*',
          ),
        ),
      );
    });
  });

  group('run in consumer package', () {
    test('with same local and global version', () {
      final (:stdout, :stderr) = runExampleCli(
        workingDirectory: './fixture_packages/consumer_v1',
      );

      expect(
        stdout,
        matches(
          RegExp(
            '.*Running v1 with local version 1.0.0 and global version 1.0.0.*',
          ),
        ),
      );
    });

    test('with different local and global version', () {
      final (:stdout, :stderr) = runExampleCli(
        workingDirectory: './fixture_packages/consumer_v2',
      );

      expect(
        stdout,
        matches(
          RegExp(
            '.*Running v2 with local version 2.0.0 and global version 1.0.0.*',
          ),
        ),
      );
    });

    test('with different local and global version in sub directory', () {
      final dir = Directory('./fixture_packages/consumer_v2/sub')
        ..createSync(recursive: true);

      final (:stdout, :stderr) = runExampleCli(workingDirectory: dir.path);

      expect(
        stdout,
        matches(
          RegExp(
            '.*Running v2 with local version 2.0.0 and global version 1.0.0.*',
          ),
        ),
      );
    });

    test('with local launch config', () {
      final (:stdout, :stderr) = runExampleCli(
        workingDirectory: './fixture_packages/consumer_v1',
        arguments: ['--local-launch-config'],
        forcePubGet: true,
      );

      // Verify that `dart pub get` was run by checking the debug log.
      expect(stderr, contains('[cli_launcher] Dependencies are out of date. Running pub get.'));

      // Verify that `dart run` was run with `--enable-asserts`.
      expect(stdout, contains('Assertions are enabled.'));
    });

    test(
      'with equal pubspec timestamps does not run pub get',
      () {
        const workingDirectory = './fixture_packages/consumer_v1';
        final timestamp = DateTime.now();
        _setUpToDateTimestamps(workingDirectory, timestamp, timestamp);

        final (:stdout, :stderr) = runExampleCli(
          workingDirectory: workingDirectory,
        );

        expect(
          stderr,
          isNot(contains('[cli_launcher] Dependencies are out of date.')),
        );
      },
      // On Windows, `dart run` triggers auto-resolution for path dependencies
      // regardless of timestamps, making this test unreliable.
      skip: Platform.isWindows,
    );

    test('without pubspec.lock runs pub get', () {
      const workingDirectory = './fixture_packages/consumer_v1';
      final pubspecFile = File('$workingDirectory/pubspec.yaml');
      pubspecFile.setLastModifiedSync(DateTime.now());

      final (:stdout, :stderr) = runExampleCli(
        workingDirectory: workingDirectory,
        forcePubGet: true,
      );

      expect(
        stderr,
        contains('[cli_launcher] Dependencies are out of date. Running pub get.'),
      );
    });

    test('with older pubspec.lock runs pub get', () {
      const workingDirectory = './fixture_packages/consumer_v1';
      final pubspecFile = File('$workingDirectory/pubspec.yaml');
      final lockFile = File('$workingDirectory/pubspec.lock');
      final pubspecTimestamp = DateTime.now();
      final lockTimestamp = pubspecTimestamp.subtract(const Duration(hours: 1));
      pubspecFile.setLastModifiedSync(pubspecTimestamp);
      lockFile.setLastModifiedSync(lockTimestamp);

      final (:stdout, :stderr) = runExampleCli(
        workingDirectory: workingDirectory,
      );

      expect(
        stderr,
        contains('[cli_launcher] Dependencies are out of date. Running pub get.'),
      );
    });

    test(
      'with newer pubspec.lock does not run pub get',
      () {
        const workingDirectory = './fixture_packages/consumer_v1';
        final lockTimestamp = DateTime.now();
        final pubspecTimestamp = lockTimestamp.subtract(
          const Duration(hours: 1),
        );
        _setUpToDateTimestamps(
          workingDirectory,
          pubspecTimestamp,
          lockTimestamp,
        );

        final (:stdout, :stderr) = runExampleCli(
          workingDirectory: workingDirectory,
        );

        expect(
          stderr,
          isNot(contains('[cli_launcher] Dependencies are out of date.')),
        );
      },
      // On Windows, `dart run` triggers auto-resolution for path dependencies
      // regardless of timestamps, making this test unreliable.
      skip: Platform.isWindows,
    );
  });
}

/// Sets timestamps on all files that are checked to determine whether `pub get`
/// needs to be run.
///
/// This includes the pubspec files in the consumer package as well as the
/// `.dart_tool/package_config.json` and the path dependency's `pubspec.yaml`,
/// which are checked by `dart run`'s own auto-resolution.
void _setUpToDateTimestamps(
  String workingDirectory,
  DateTime pubspecTimestamp,
  DateTime lockTimestamp,
) {
  final packageConfigFile = File(
    '$workingDirectory/.dart_tool/package_config.json',
  );
  final pubspecFile = File('$workingDirectory/pubspec.yaml');
  final lockFile = File('$workingDirectory/pubspec.lock');
  // Path dependency of consumer_v1.
  final pathDepPubspecFile = File('./fixture_packages/example_v1/pubspec.yaml');

  // Set package_config.json to be the newest to prevent `dart run` from
  // triggering its own pub get.
  final newestTimestamp = lockTimestamp.isAfter(pubspecTimestamp)
      ? lockTimestamp
      : pubspecTimestamp;
  packageConfigFile.setLastModifiedSync(newestTimestamp);
  pathDepPubspecFile.setLastModifiedSync(pubspecTimestamp);
  pubspecFile.setLastModifiedSync(pubspecTimestamp);
  lockFile.setLastModifiedSync(lockTimestamp);
}

void _setFlutterWorkspaceUpToDateTimestamps(DateTime timestamp) {
  const workspaceRoot = './fixture_packages/flutter_workspace';
  const sourcePackage = '$workspaceRoot/packages/example_flutter_workspace';

  final workspacePubspecFile = File('$workspaceRoot/pubspec.yaml');
  final sourcePubspecFile = File('$sourcePackage/pubspec.yaml');
  final lockFile = File('$workspaceRoot/pubspec.lock');
  final flutterPubspecFile = File(
    '$workspaceRoot/packages/flutter_package/pubspec.yaml',
  );

  workspacePubspecFile.setLastModifiedSync(timestamp);
  sourcePubspecFile.setLastModifiedSync(timestamp);
  lockFile.setLastModifiedSync(timestamp);
  flutterPubspecFile.setLastModifiedSync(timestamp);

  // Set package_config.json to be the newest to prevent `dart run` from
  // triggering its own pub get via auto-resolution of path dependencies.
  final packageConfigFile = File(
    '$workspaceRoot/.dart_tool/package_config.json',
  );
  packageConfigFile.setLastModifiedSync(timestamp);
}

({String stdout, String stderr}) runExampleCli({
  List<String> arguments = const [],
  required String workingDirectory,
  bool forcePubGet = false,
  String executable = 'example',
}) {
  if (forcePubGet) {
    // Remove the pubspec.lock file to ensure a fresh run.
    final lockFile = File('$workingDirectory/pubspec.lock');
    if (lockFile.existsSync()) {
      lockFile.deleteSync();
    }
  }

  final result = Process.runSync(
    executable,
    arguments,
    runInShell: true,
    workingDirectory: workingDirectory,
    stderrEncoding: utf8,
    stdoutEncoding: utf8,
    environment: {...Platform.environment, 'CLI_LAUNCHER_VERBOSE': '1'},
  );

  if (result.exitCode != 0) {
    throw Exception(
      '$executable CLI failed with exit code ${result.exitCode}:'
      '\n${result.stdout}\n${result.stderr}',
    );
  }

  return (stdout: result.stdout as String, stderr: result.stderr as String);
}
