import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late String exampleBinDir;

  setUpAll(() {
    final result = Process.runSync(
      'dart',
      ['install', 'fixture_packages/example_v1'],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw Exception(
        'dart install failed with exit code ${result.exitCode}:\n'
        '${result.stdout}\n${result.stderr}',
      );
    }

    // Parse the install bin directory from the output.
    // Output contains a line like: "Installed: /path/to/bin/example"
    final stdout = result.stdout as String;
    final installedLine = stdout
        .split('\n')
        .where((line) => line.startsWith('Installed:'))
        .firstOrNull;
    if (installedLine == null) {
      throw Exception(
        'Could not find "Installed:" line in dart install output:\n$stdout',
      );
    }
    final installedPath = installedLine.replaceFirst('Installed: ', '').trim();
    exampleBinDir = File(installedPath).parent.path;
  });

  tearDownAll(() {
    Process.runSync('dart', ['uninstall', 'cli_launcher_example']);
  });

  test('run global version', () {
    final output = runExampleCli(
      exampleBinDir: exampleBinDir,
      workingDirectory: '.',
    );

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
        exampleBinDir: exampleBinDir,
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
        exampleBinDir: exampleBinDir,
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
        exampleBinDir: exampleBinDir,
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
        exampleBinDir: exampleBinDir,
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

      final output = runExampleCli(
        exampleBinDir: exampleBinDir,
        workingDirectory: dir.path,
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
}

String runExampleCli({
  required String exampleBinDir,
  List<String> arguments = const [],
  required String workingDirectory,
}) {
  // Prepend the dart install bin directory to PATH so the installed binary
  // is found first.
  final env = Map<String, String>.from(Platform.environment);
  env['PATH'] = '$exampleBinDir:${env['PATH']}';

  final result = Process.runSync(
    'example',
    arguments,
    runInShell: true,
    workingDirectory: workingDirectory,
    stderrEncoding: utf8,
    stdoutEncoding: utf8,
    environment: env,
  );

  if (result.exitCode != 0) {
    throw Exception(
      'example CLI failed with exit code ${result.exitCode}:'
      '\n${result.stdout}\n${result.stderr}',
    );
  }

  return result.stdout as String;
}
