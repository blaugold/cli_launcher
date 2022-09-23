import 'dart:async';
import 'dart:io';

import 'io.dart';
import 'local_launch_context.dart';
import 'logging.dart';
import 'shell.dart';

/// The installation location of a package executable.
enum InstallationLocation {
  /// The executable is installed globally in the pub cache.
  global,

  /// The executable is installed locally in a root package that depends on the
  /// package containing the executable.
  local,
}

/// Identifies an [executable] that is provided through a [package].
class PackageExecutable {
  /// Creates a new [PackageExecutable].
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

  /// The name of the package that provides the executable.
  final String package;

  /// The name of the executable.
  final String executable;

  @override
  String toString() => '$package:$executable';
}

/// Interface for launching an [executable] through `cli_launcher`.
///
/// Packages that want to launch an [executable] through `cli_launcher` have to
/// define a class that **extends** (not implements) this class for each of
/// their executables.
///
/// ```
/// // lib/src/launcher.dart
///
/// class FooLauncher extends Launcher {
///   FooLauncher() : super(PackageExecutable('foo_pkg', 'foo'));
///
///   @override
///   void run(List<String> arguments, InstallationLocation location) {
///     print('Running ${location} "foo" with arguments: $arguments');
///   }
/// }
/// ```
///
/// This class must be declared in the package's `pubspec.yaml` file:
///
/// ```yaml
/// #...
///
/// executables:
///   foo:
///
/// cli_launcher:
///   foo:
///     launcherFile: package:foo_pkg/src/launcher.dart
///     launcherClass: FooLauncher
/// ```
///
/// The global version of an executable has to be launched in the Dart script of
/// the executable in `bin`:
///
/// ```dart no_analyze
/// // bin/foo.dart
///
/// import 'package:cli_launcher/cli_launcher.dart';
///
/// import '../lib/src/launcher.dart';
///
/// Future<void> main(List<String> arguments) =>
///     runGlobalInstallation(arguments, FooLauncher());
/// ```
abstract class Launcher {
  /// Constructor for subclasses.
  Launcher(this.executable);

  /// Identifier for the executable that is launched by this [Launcher].
  final PackageExecutable executable;

  /// Starts running the code of the executable.
  ///
  /// The [arguments] are the arguments that were passed to the executable.
  ///
  /// The [location] indicates where the executable is installed.
  FutureOr<void> run(List<String> arguments, InstallationLocation location);
}

/// Launches the global installation of an executable.
///
/// The [arguments] are the arguments that were passed to the Dart program.
///
/// The [launcher] is the [Launcher] that is used to run the executable.
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
