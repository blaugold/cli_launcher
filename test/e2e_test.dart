import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('run global version', () {
    final output = runExampleCli(workingDirectory: '.');

    expect(
      output,
      matches(
        RegExp(
          '.*Running v1 with local version null and global version 1.0.0.*',
        ),
      ),
    );
  });

  test('run global workspace version', () {
    final output = runExampleCli(
      workingDirectory: '.',
      executable: 'example_workspace',
    );

    expect(
      output,
      matches(
        RegExp(
          '.*Running workspace example with local version null and global version 1.0.0.*',
        ),
      ),
    );
  });

  test('run from Flutter workspace member', () {
    final output = runExampleCli(
      workingDirectory:
          './fixture_packages/flutter_workspace/packages/flutter_package',
      executable: 'example_flutter_workspace',
    );

    expect(
      output,
      matches(
        RegExp(
          '.*Running flutter workspace example with local version null and global version 1.0.0.*',
        ),
      ),
    );
  });

  group('run in source package', () {
    test('with same local and global version', () {
      final output = runExampleCli(
        workingDirectory: 'fixture_packages/example_v1',
      );

      expect(
        output,
        matches(
          RegExp(
            '.*Running v1 with local version 1.0.0 and global version 1.0.0.*',
          ),
        ),
      );
    });

    test('with different local and global version', () {
      final output = runExampleCli(
        workingDirectory: 'fixture_packages/example_v2',
      );

      expect(
        output,
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
      final output = runExampleCli(
        workingDirectory: './fixture_packages/consumer_v1',
      );

      expect(
        output,
        matches(
          RegExp(
            '.*Running v1 with local version 1.0.0 and global version 1.0.0.*',
          ),
        ),
      );
    });

    test('with different local and global version', () {
      final output = runExampleCli(
        workingDirectory: './fixture_packages/consumer_v2',
      );

      expect(
        output,
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

      final output = runExampleCli(workingDirectory: dir.path);

      expect(
        output,
        matches(
          RegExp(
            '.*Running v2 with local version 2.0.0 and global version 1.0.0.*',
          ),
        ),
      );
    });

    test('with local launch config', () {
      final output = runExampleCli(
        workingDirectory: './fixture_packages/consumer_v1',
        arguments: ['--local-launch-config'],
        forcePubGet: true,
      );

      // Verify that `dart pub get` was run with `--verbose`.
      expect(output, matches('MSG : Resolving dependencies...'));

      // Verify that `dart run` was run with `--enable-asserts`.
      expect(output, matches('Assertions are enabled.'));
    });

    test(
      'with equal pubspec timestamps does not run pub get',
      () {
        const workingDirectory = './fixture_packages/consumer_v1';
        final timestamp = DateTime.now();
        _setUpToDateTimestamps(workingDirectory, timestamp, timestamp);

        final output = runExampleCli(workingDirectory: workingDirectory);

        expect(output, isNot(contains('Resolving dependencies...')));
      },
      // On Windows, `dart run` triggers auto-resolution for path dependencies
      // regardless of timestamps, making this test unreliable.
      skip: Platform.isWindows,
    );

    test('without pubspec.lock runs pub get', () {
      const workingDirectory = './fixture_packages/consumer_v1';
      final pubspecFile = File('$workingDirectory/pubspec.yaml');
      pubspecFile.setLastModifiedSync(DateTime.now());

      final output = runExampleCli(
        workingDirectory: workingDirectory,
        forcePubGet: true,
      );

      expect(output, contains('Resolving dependencies...'));
    });

    test('with older pubspec.lock runs pub get', () {
      const workingDirectory = './fixture_packages/consumer_v1';
      final pubspecFile = File('$workingDirectory/pubspec.yaml');
      final lockFile = File('$workingDirectory/pubspec.lock');
      final pubspecTimestamp = DateTime.now();
      final lockTimestamp = pubspecTimestamp.subtract(const Duration(hours: 1));
      pubspecFile.setLastModifiedSync(pubspecTimestamp);
      lockFile.setLastModifiedSync(lockTimestamp);

      final output = runExampleCli(workingDirectory: workingDirectory);

      expect(output, contains('Resolving dependencies...'));
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

        final output = runExampleCli(workingDirectory: workingDirectory);

        expect(output, isNot(contains('Resolving dependencies...')));
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

String runExampleCli({
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
  );

  if (result.exitCode != 0) {
    throw Exception(
      '$executable CLI failed with exit code ${result.exitCode}:'
      '\n${result.stdout}\n${result.stderr}',
    );
  }

  return result.stdout as String;
}
