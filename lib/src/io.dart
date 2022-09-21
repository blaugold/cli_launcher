import 'dart:io';

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

Future<bool> callProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
    workingDirectory: workingDirectory,
  );

  return (exitCode = await process.exitCode) == 0;
}
