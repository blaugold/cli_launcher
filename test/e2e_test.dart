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

  test('run in package containing executable', () {
    final output =
        runExampleCli(workingDirectory: 'fixture_packages/example_v1');

    expect(
      output,
      matches(
        RegExp(
          '.*Running v1 with local version 1.0.0 and global version null.*',
        ),
      ),
    );
  });

  test('local and global version are the same', () {
    final output =
        runExampleCli(workingDirectory: './fixture_packages/consumer_v1');

    expect(
      output,
      matches(
        RegExp(
          '.*Running v1 with local version 1.0.0 and global version 1.0.0.*',
        ),
      ),
    );
  });

  test('local and global version are not same', () {
    final output =
        runExampleCli(workingDirectory: './fixture_packages/consumer_v2');

    expect(
      output,
      matches(
        RegExp(
          '.*Running v2 with local version 2.0.0 and global version 1.0.0.*',
        ),
      ),
    );
  });

  test('run local version within sub directory of consuming package', () {
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
}

String runExampleCli({
  List<String> arguments = const [],
  required String workingDirectory,
}) {
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