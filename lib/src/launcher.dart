import 'dart:async';
import 'dart:io';

import 'io.dart';
import 'local_launch_context.dart';
import 'logging.dart';
import 'shell.dart';

enum InstallationLocation {
  global,
  local,
}

class PackageExecutable {
  PackageExecutable(this.package, this.executable);

  factory PackageExecutable.parse(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      throw ArgumentError.value(
        value,
        'value',
        'Expected a value in the form "package:executable".',
      );
    }
    return PackageExecutable(parts[0], parts[1]);
  }

  final String package;
  final String executable;

  @override
  String toString() => '$package:$executable';
}

abstract class Launcher {
  Launcher(this.executable);

  final PackageExecutable executable;

  FutureOr<void> run(List<String> arguments, InstallationLocation location);
}

Future<void> runGlobalInstallation(
  List<String> arguments,
  Launcher launcher,
) =>
    cliLauncherShell(
      'global_installation',
      arguments,
      () => _runGlobalInstallation(arguments, launcher),
    );

Future<void> _runGlobalInstallation(
  List<String> arguments,
  Launcher launcher,
) async {
  logger.trace('Launching ${launcher.executable}.');

  final localLaunchContext =
      await resolveLocalLaunchContext(executable: launcher.executable);

  if (localLaunchContext != null) {
    return await _launchLocalInstallation(
      arguments,
      localLaunchContext,
    );
  } else {
    return await launcher.run(arguments, InstallationLocation.global);
  }
}

Future<void> _launchLocalInstallation(
  List<String> arguments,
  LocalLaunchContext context,
) async {
  logger.trace('Launching ${context.executable} through launch script.');

  if (!fileExists(context.launchScriptPath)) {
    logger.trace('Generating launch script at "${context.launchScriptPath}".');
    await runProcess(
      'dart',
      [
        'run',
        'cli_launcher:generate_launch_script',
        if (logger.isVerbose) '--verbose',
        context.executable.toString(),
      ],
      workingDirectory: context.installationPackagePath,
    );
  }

  logger.trace('Running launch script at "${context.launchScriptPath}".');
  await callProcess(
    context.launchScriptPath,
    arguments,
    // On Windows the launch script is a PowerShell script.
    usePowerShell: Platform.isWindows,
  );
}

Future<void> runLocalInstallation(
  List<String> arguments,
  LocalLaunchContext context,
  Future<void> Function() run,
) =>
    cliLauncherShell(
      'local_installation',
      arguments,
      () => _runLocalInstallation(arguments, context, run),
    );

Future<void> _runLocalInstallation(
  List<String> arguments,
  LocalLaunchContext context,
  Future<void> Function() run,
) async {
  if (_localInstallationIsUpToDate(context)) {
    await run();
  } else {
    logger
        .stdout('Local installation of ${context.executable} is out of date.');
    removeDirectory(context.cacheDirectory);
    logger.trace('Removed cache directory at "${context.cacheDirectory}".');
    await callProcess(context.executable.executable, arguments);
  }
}

bool _localInstallationIsUpToDate(LocalLaunchContext context) {
  if (!fileExists(context.launchScriptPath)) {
    return false;
  }

  if (fileIsNewerThanOtherFile(
    context.pubspecLockPath,
    context.launchScriptPath,
  )) {
    return false;
  }

  if (!fileExists(context.snapshotPath)) {
    return false;
  }

  if (fileIsNewerThanOtherFile(
    context.pubspecLockPath,
    context.snapshotPath,
  )) {
    return false;
  }

  // TODO: For local plugins, check if the plugin has been updated.

  return true;
}
