import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_logging.dart';
import 'package:path/path.dart' as p;

void ensureDirectoryExists(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
}

bool fileExists(String path) => File(path).existsSync();

bool fileIsNewerThanOtherFile(String file, String other) {
  final fileStat = File(file).statSync();
  final otherStat = File(other).statSync();
  return fileStat.modified.isAfter(otherStat.modified);
}

String readFileAsString(String path) => File(path).readAsStringSync();

void writeFileAsString(String path, String contents) {
  ensureDirectoryExists(p.dirname(path));
  File(path).writeAsStringSync(contents);
}

void makeFileUnixExecutable(String path) {
  final result = Process.runSync('chmod', ['+x', path]);
  if (result.exitCode != 0) {
    throw Exception(
      'Failed to make file "$path" executable with exit code '
      '${result.exitCode}.',
    );
  }
}

void removeFile(String path) {
  if (fileExists(path)) {
    File(path).deleteSync();
  }
}

Iterable<String> walkUpwards(String path) sync* {
  var current = path;
  while (true) {
    yield current;
    final parent = Directory(current).parent;
    if (parent.path == current) {
      break;
    }
    current = parent.path;
  }
}

Future<void> runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  required Logger logger,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    // Needed to resolve .bat files on Windows.
    runInShell: Platform.isWindows,
  );

  final stdout = <String>[];
  final stderr = <String>[];

  process.stdout.transform(utf8.decoder).listen((event) {
    stdout.add(event);
    if (logger.isVerbose) {
      logger.stdout(event);
    }
  });
  process.stderr.transform(utf8.decoder).listen((event) {
    stderr.add(event);
    if (logger.isVerbose) {
      logger.stderr(event);
    }
  });

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      [
        'Process exited with non-zero exit code: $exitCode.',
        if (stdout.isNotEmpty) stdout.join(),
        if (stderr.isNotEmpty) stderr.join(),
      ].join('\n'),
      exitCode,
    );
  }
}

Future<bool> callProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  bool usePowerShell = false,
}) async {
  final process = await Process.start(
    usePowerShell ? 'powershell' : executable,
    usePowerShell ? [executable, ...arguments] : arguments,
    mode: ProcessStartMode.inheritStdio,
    workingDirectory: workingDirectory,
    // Needed to resolve .bat files on Windows.
    runInShell: usePowerShell ? false : Platform.isWindows,
  );

  return (exitCode = await process.exitCode) == 0;
}
