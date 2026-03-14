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

    test('with equal pubspec timestamps does not run pub get', () {
      const workingDirectory = './fixture_packages/consumer_v1';
      final timestamp = DateTime.now();
      _setUpToDateTimestamps(workingDirectory, timestamp, timestamp);

      final output = runExampleCli(workingDirectory: workingDirectory);

      expect(output, isNot(contains('Resolving dependencies...')));
    });

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

    test('with newer pubspec.lock does not run pub get', () {
      const workingDirectory = './fixture_packages/consumer_v1';
      final lockTimestamp = DateTime.now();
      final pubspecTimestamp = lockTimestamp.subtract(const Duration(hours: 1));
      _setUpToDateTimestamps(workingDirectory, pubspecTimestamp, lockTimestamp);

      final output = runExampleCli(workingDirectory: workingDirectory);

      expect(output, isNot(contains('Resolving dependencies...')));
    });
  });
}

/// Ensures all package resolutions are up to date so that neither
/// cli_launcher's `_pubspecLockIsUpToDate` check nor `dart run`'s
/// auto-resolution will trigger `pub get`.
///
/// This runs `dart pub get` in all relevant directories to guarantee fresh
/// `package_config.json` files, then sets the consumer's pubspec/lock
/// timestamps to preserve the caller's intended relative ordering.
void _setUpToDateTimestamps(
  String workingDirectory,
  DateTime pubspecTimestamp,
  DateTime lockTimestamp,
) {
  final pubspecFile = File('$workingDirectory/pubspec.yaml');
  final lockFile = File('$workingDirectory/pubspec.lock');

  // Run `dart pub get` in all relevant directories to ensure
  // `package_config.json` files are fresh and consistent with the current SDK.
  // This is the most reliable way to prevent `dart run`'s auto-resolution,
  // especially on Windows where timestamp manipulation via
  // `setLastModifiedSync` may not reliably prevent auto-resolution.
  Process.runSync(
    'dart',
    ['pub', 'get'],
    workingDirectory: './fixture_packages/example_v1',
    runInShell: Platform.isWindows,
  );
  Process.runSync(
    'dart',
    ['pub', 'get'],
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );

  // Set the consumer's pubspec/lock timestamps to preserve the caller's
  // intended relative ordering. Both must be before `package_config.json`
  // (which was just created by `dart pub get`).
  final packageConfigTime = File(
    '$workingDirectory/.dart_tool/package_config.json',
  ).lastModifiedSync();
  final basePubspec = packageConfigTime.subtract(const Duration(hours: 2));
  final DateTime baseLock;
  if (lockTimestamp.isAfter(pubspecTimestamp)) {
    baseLock = basePubspec.add(lockTimestamp.difference(pubspecTimestamp));
  } else {
    baseLock = basePubspec;
  }

  pubspecFile.setLastModifiedSync(basePubspec);
  lockFile.setLastModifiedSync(baseLock);
}

String runExampleCli({
  List<String> arguments = const [],
  required String workingDirectory,
  bool forcePubGet = false,
}) {
  if (forcePubGet) {
    // Remove the pubspec.lock file to ensure a fresh run.
    final lockFile = File('$workingDirectory/pubspec.lock');
    if (lockFile.existsSync()) {
      lockFile.deleteSync();
    }
  }

  final result = Process.runSync(
    'example',
    arguments,
    runInShell: true,
    workingDirectory: workingDirectory,
    stderrEncoding: utf8,
    stdoutEncoding: utf8,
  );

  if (result.exitCode != 0) {
    throw Exception(
      'example CLI failed with exit code ${result.exitCode}:'
      '\n${result.stdout}\n${result.stderr}',
    );
  }

  return result.stdout as String;
}
