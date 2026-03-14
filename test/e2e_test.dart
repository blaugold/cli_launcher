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

/// Sets timestamps on all files that are checked to determine whether `pub get`
/// needs to be run.
///
/// This sets up timestamps so that:
/// 1. cli_launcher's `_pubspecLockIsUpToDate` considers the lock file up to date
///    (lock >= pubspec for the consumer package).
/// 2. `dart run`'s auto-resolution does not trigger. `dart run` checks
///    `package_config.json` against all pubspec/lock files, including those of
///    transitive path dependencies.
///
/// To avoid issues with future timestamps on Windows (which may not be
/// supported by all filesystem APIs), all pubspec/lock files are set to
/// timestamps in the past, and `package_config.json` files are set to the
/// current time.
void _setUpToDateTimestamps(
  String workingDirectory,
  DateTime pubspecTimestamp,
  DateTime lockTimestamp,
) {
  // Consumer package files.
  final packageConfigFile = File(
    '$workingDirectory/.dart_tool/package_config.json',
  );
  final pubspecFile = File('$workingDirectory/pubspec.yaml');
  final lockFile = File('$workingDirectory/pubspec.lock');

  // Path dependency: example_v1 (depended on by consumer_v1).
  final pathDepPubspecFile = File('./fixture_packages/example_v1/pubspec.yaml');
  final pathDepLockFile = File('./fixture_packages/example_v1/pubspec.lock');
  final pathDepPackageConfigFile = File(
    './fixture_packages/example_v1/.dart_tool/package_config.json',
  );

  // Transitive path dependency: root cli_launcher package (depended on by
  // example_v1 via `path: ../..`).
  final rootPubspecFile = File('./pubspec.yaml');

  // Use a base time 2 hours in the past. This ensures that even after adding
  // offsets for relative timestamp ordering, all pubspec/lock files remain
  // well before the current time.
  final baseTime = DateTime.now().subtract(const Duration(hours: 2));

  // Compute past timestamps that preserve the caller's intended relative
  // ordering between pubspec and lock files.
  final pastPubspec = baseTime;
  final DateTime pastLock;
  if (lockTimestamp.isAfter(pubspecTimestamp)) {
    pastLock = baseTime.add(lockTimestamp.difference(pubspecTimestamp));
  } else {
    pastLock = baseTime;
  }

  // Set all pubspec and lock files to past timestamps.
  pubspecFile.setLastModifiedSync(pastPubspec);
  lockFile.setLastModifiedSync(pastLock);
  pathDepPubspecFile.setLastModifiedSync(pastPubspec);
  if (pathDepLockFile.existsSync()) {
    pathDepLockFile.setLastModifiedSync(pastPubspec);
  }
  rootPubspecFile.setLastModifiedSync(pastPubspec);

  // Set package_config.json files to the current time, ensuring they are
  // newer than all pubspec/lock files.
  final now = DateTime.now();
  packageConfigFile.setLastModifiedSync(now);
  if (pathDepPackageConfigFile.existsSync()) {
    pathDepPackageConfigFile.setLastModifiedSync(now);
  }
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
