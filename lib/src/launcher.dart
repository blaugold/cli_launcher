import 'dart:async';
import 'dart:io';

import 'package:cli_util/cli_logging.dart';

import 'error.dart';
import 'io.dart';
import 'local_launch_context.dart';
import 'logging.dart';

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
) async {
  final logger = createLogger(arguments);

  await withErrorHandling(
    logger,
    () => _runGlobalInstallation(logger, arguments, launcher),
  );
}

Future<void> _runGlobalInstallation(
  Logger logger,
  List<String> arguments,
  Launcher launcher,
) async {
  logger.trace('Launching ${launcher.executable} from global entrypoint.');

  final localLaunchContext = await resolveLocalLaunchContext(
    executable: launcher.executable,
    logger: logger,
  );

  if (localLaunchContext != null) {
    return await _launchLocalInstallation(
      logger,
      arguments,
      localLaunchContext,
    );
  } else {
    return await launcher.run(arguments, InstallationLocation.global);
  }
}

Future<void> _launchLocalInstallation(
  Logger logger,
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
      logger: logger,
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
  Future<void> Function() run,
) async {
  final logger = createLogger(arguments);

  await withErrorHandling(
    logger,
    () => _runLocalInstallation(logger, run),
  );
}

Future<void> _runLocalInstallation(
  Logger logger,
  Future<void> Function() run,
) async {
  // TODO: Check if the launch script and snapshot are up to date.

  await run();
}
