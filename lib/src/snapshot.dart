import 'dart:io';

import 'error.dart';
import 'io.dart';
import 'launcher.dart';
import 'local_launch_context.dart';
import 'shell.dart';

Future<void> generateSnapshot(List<String> arguments) => cliLauncherShell(
      'generate_snapshot',
      arguments,
      () => _generateSnapshot(arguments),
    );

Future<void> _generateSnapshot(List<String> arguments) async {
  if (arguments.isEmpty) {
    throw CliLauncherException(
      'Expected a package executable to generate snapshot for.',
    );
  }

  PackageExecutable executable;
  try {
    executable = PackageExecutable.parse(arguments.last);
  } on ArgumentError catch (error) {
    throw CliLauncherException(
      'Invalid package executable: $error',
    );
  }

  final currentDirectory = Directory.current.path;
  final localLaunchContext = await resolveLocalLaunchContextForDirectory(
    directory: currentDirectory,
    executable: executable,
  );

  if (localLaunchContext == null) {
    throw CliLauncherException(
      'Could not resolve a local launch context for "$executable" in '
      '"$currentDirectory".',
    );
  }

  writeFileAsString(
    localLaunchContext.mainPath,
    await _buildMainDartFile(localLaunchContext),
  );

  await runProcess(
    'dart',
    [
      'compile',
      'kernel',
      localLaunchContext.mainPath,
      '-o',
      localLaunchContext.snapshotPath
    ],
  );
}

Future<String> _buildMainDartFile(LocalLaunchContext context) async {
  return '''
// DO NOT EDIT. This file is generated.
// ignore_for_file: implementation_imports
import 'package:cli_launcher/cli_launcher.dart' as _cli_launcher;
import 'package:cli_launcher/src/launcher.dart' as _cli_launcher_impl;
import '${context.executableConfig.launcherFile}' as _launcher_file;

Future<void> main(List<String> arguments) async {
  await _cli_launcher_impl.runLocalInstallation(arguments, () async {
    final launcher = _launcher_file.${context.executableConfig.launcherClass}();
    await launcher.run(arguments, _cli_launcher.InstallationLocation.local);
  });
}
''';
}
