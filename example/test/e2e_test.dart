import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('run global version', () {
    final output = runExampleCli(
      // Run outside of the example package directory so that the global
      // version is used.
      workingDirectory: '..',
    );

    expect(
      output,
      matches(
        RegExp(
          ".*Running global installation in Directory: '.*cli_launcher'.*",
        ),
      ),
    );
  });

  test('run local version within package containing executable', () {
    final output = runExampleCli(
      workingDirectory: '.',
    );

    expect(
      output,
      matches(
        RegExp(
          ".*Running local installation in Directory: '.*example'.*",
        ),
      ),
    );
  });

  test('run local version within consuming package', () {
    final output = runExampleCli(workingDirectory: './consumer');

    expect(
      output,
      matches(
        RegExp(
          ".*Running local installation in Directory: '.*consumer'.*",
        ),
      ),
    );
  });

  test('run local version within sub directory of consuming package', () {
    final dir = Directory('consumer/sub')..createSync(recursive: true);

    final output = runExampleCli(workingDirectory: dir.path);

    expect(
      output,
      matches(
        RegExp(
          ".*Running local installation in Directory: '.*sub'.*",
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
