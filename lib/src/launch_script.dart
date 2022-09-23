import 'dart:io';

import 'error.dart';
import 'io.dart';
import 'launcher.dart';
import 'local_launch_context.dart';
import 'shell.dart';

Future<void> generateLaunchScript(List<String> arguments) => cliLauncherShell(
      'generate_launch_script',
      arguments,
      () => _generateLaunchScript(arguments),
    );

Future<void> _generateLaunchScript(List<String> arguments) async {
  if (arguments.isEmpty) {
    throw CliLauncherException(
      'Expected a package executable to generate the launch script for.',
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
    localLaunchContext.launchScriptPath,
    _buildLaunchScript(localLaunchContext),
  );
  if (!Platform.isWindows) {
    makeFileUnixExecutable(localLaunchContext.launchScriptPath);
  }
}

String _buildLaunchScript(LocalLaunchContext context) {
  if (Platform.isWindows) {
    return _buildPowerShellLaunchScript(context);
  }
  return _buildBashLaunchScript(context);
}

String _buildBashLaunchScript(LocalLaunchContext context) {
  // TODO: Hide output from "dart run cli_launcher:generate_snapshot".
  return '''
#!/usr/bin/env bash

if [ -f "${context.snapshotPath}" ]; then
  dart "${context.snapshotPath}" "\$@"
  exitCode="\$?"
  if [ "\$exitCode" -ne "253" ]; then
    exit "\$exitCode"
  fi
fi

pushd "${context.installationPackagePath}" > /dev/null
dart run cli_launcher:generate_snapshot ${context.executable}
exitCode="\$?"
if [ "\$exitCode" -ne "0" ]; then
  exit "\$exitCode"
fi
popd > /dev/null

dart "${context.snapshotPath}" "\$@"
''';
}

String _buildPowerShellLaunchScript(LocalLaunchContext context) {
  // TODO: Hide output from "dart run cli_launcher:generate_snapshot".
  return '''
if (Test-Path "${context.snapshotPath}") {
  dart "${context.snapshotPath}" \$args
  \$exitCode = \$LASTEXITCODE
  if (\$exitCode -ne 253) {
    exit \$exitCode
  }
}

Push-Location "${context.installationPackagePath}"
dart run cli_launcher:generate_snapshot ${context.executable}
\$exitCode = \$LASTEXITCODE
if (\$exitCode -ne 0) {
  exit \$exitCode
}
Pop-Location

dart "${context.snapshotPath}" \$args
''';
}
