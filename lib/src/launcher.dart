import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';

import 'io.dart';
import 'pub.dart';

enum LaunchPhase {
  global,
  localLauncher,
  local,
}

const _bootstrapLocalLauncherArgument = '__BOOTSTRAP_LOCAL_LAUNCHER__';

abstract class CliLauncher {
  /// Constructor for subclasses.
  CliLauncher({required this.location, String? executableName}) {
    final locationUri = Uri.tryParse(location);
    if (locationUri == null) {
      throw ArgumentError.value(location, 'location', 'invalid URI');
    }

    if (locationUri.scheme != 'package') {
      throw ArgumentError.value(
        location,
        'location',
        'must be a package URI',
      );
    }

    if (!locationUri.path.endsWith('.dart')) {
      throw ArgumentError.value(
        location,
        'location',
        'must point to a Dart file',
      );
    }

    // Defaults to the name of the package that contains the launcher.
    this.executableName = executableName ?? locationUri.pathSegments.first;
  }

  /// The URI of the Dart file that contains this launcher.
  ///
  /// Must be a `package:` URI.
  final String location;

  /// The name of the package that contains this launcher.
  String get packageName => Uri.parse(location).pathSegments.first;

  /// The name of the executable that is launched.
  ///
  /// Defaults to the name of the [packageName].
  late final String executableName;

  /// The current phase of launching the CLI.
  LaunchPhase get launchPhase => _launchPhase;
  late LaunchPhase _launchPhase;

  /// Whether this instance is launching a local installation of the CLI or a
  /// global installation.
  bool get isLocalInstallation => launchPhase == LaunchPhase.local;

  /// That path to the package that has a local installation of the CLI.
  String? get localInstallationPath => _localInstallationPath;
  String? _localInstallationPath;

  String get _cliLauncherCachePath => p.join(
        _localInstallationPath!,
        '.dart_tool',
        '.cli_launcher',
        packageName,
        executableName,
      );

  String get _launcherPath => p.join(_cliLauncherCachePath, 'launcher.dart');
  String get _launcherSnapshotPath =>
      p.join(_cliLauncherCachePath, 'launcher.jit');

  String get _mainPath => p.join(_cliLauncherCachePath, 'main.dart');
  String get _mainSnapshotPath => p.join(_cliLauncherCachePath, 'main.jit');

  String _mainWorkingDirectory = Directory.current.path;

  /// Method that subclasses must implement to start running the CLI.
  FutureOr<void> run(List<String> arguments);

  /// Starts the process to [run] the CLI.
  Future<void> launch(
    List<String> arguments, {
    LaunchPhase phase = LaunchPhase.global,
    String? localInstallationPath,
  }) async {
    try {
      if (arguments.isNotEmpty &&
          arguments.first == _bootstrapLocalLauncherArgument) {
        return _bootstrapLocalLauncher(arguments);
      }

      _localInstallationPath ??= localInstallationPath;
      _launchPhase = phase;

      switch (_launchPhase) {
        case LaunchPhase.global:
          if (await _findLocalInstallation()) {
            await _runLauncher(arguments);
          } else {
            await run(arguments);
          }
          break;
        case LaunchPhase.localLauncher:
          if (!_launcherIsUpToDate()) {
            _deleteLauncher();
            await _runLauncher(arguments);
          } else {
            await _runMain(arguments);
          }
          break;
        case LaunchPhase.local:
          await run(arguments);
          break;
      }
    } on CliLauncherException catch (e) {
      stderr.writeln(e.message);
      exitCode = 1;
    }
  }

  Future<bool> _findLocalInstallation() async {
    for (final directory in walkUpwards(Directory.current.path)) {
      if (await _directoryContainsLocalInstallation(directory)) {
        _localInstallationPath = directory;
        return true;
      }
    }

    return false;
  }

  Future<bool> _directoryContainsLocalInstallation(String directory) async {
    final pubspecFile = pubspecPath(directory);
    if (!fileExists(pubspecFile)) {
      return false;
    }

    final Pubspec pubspec;
    try {
      pubspec = Pubspec.parse(
        readFileAsString(pubspecFile),
        sourceUrl: Uri.parse(pubspecFile),
      );
    } catch (e) {
      throw CliLauncherException(
        'Found invalid pubspec.yaml file while trying to find a local '
        'installation of "$executableName" at $pubspecFile:\n$e',
      );
    }

    if (pubspec.name != packageName &&
        !pubspec.dependencies.containsKey(packageName) &&
        !pubspec.devDependencies.containsKey(packageName)) {
      return false;
    }

    _localInstallationPath = directory;
    return true;
  }

  // === Local Launcher ========================================================

  Future<void> _runLauncher(List<String> arguments) async {
    if (fileExists(_launcherPath)) {
      await _runLauncherSnapshot(arguments);
    } else {
      await callProcess(
        'dart',
        [
          'run',
          '$packageName:$executableName',
          _bootstrapLocalLauncherArgument,
          _localInstallationPath!,
          Directory.current.path,
          ...arguments,
        ],
        // `dart run` has to be run in the directory of the package where the
        // CLI is installed.
        workingDirectory: _localInstallationPath,
      );
    }
  }

  Future<void> _bootstrapLocalLauncher(List<String> arguments) async {
    arguments = arguments.toList();
    // Removes _localLauncherArgument.
    arguments.removeAt(0);
    // Take the local installation path.
    _localInstallationPath = arguments.removeAt(0);
    // Take the working directory for main.
    _mainWorkingDirectory = arguments.removeAt(0);
    _launchPhase = LaunchPhase.localLauncher;

    _checkPubDependenciesAreUpToDate();

    writeFileAsString(_launcherPath, _buildLauncherSource());
    await _runLauncherSnapshot(
      arguments,
      // This is the first time that the local launcher is run, which always
      // is done through `dart run`, which has to be run in the directory of
      // the package where the CLI is installed. But we want to run the
      // final executable in the original working directory where the user
      // ran the command.
      workingDirectory: _mainWorkingDirectory,
    );
  }

  bool _launcherIsUpToDate() {
    if (!fileExists(_launcherPath)) {
      // No snapshot, so it's not up-to-date.
      return false;
    }

    if (fileIsNewerThanOtherFile(
      pubspecLockPath(_localInstallationPath!),
      _launcherPath,
    )) {
      // The dependencies that were used to generate the snapshot might have
      // changed.
      return false;
    }

    return true;
  }

  void _deleteLauncher() {
    removeFile(_launcherPath);
    removeFile(_launcherSnapshotPath);
  }

  String _buildLauncherSource() {
    return '''
// DO NOT EDIT. This file is generated.
// ignore_for_file: implementation_imports
import 'package:cli_launcher/cli_launcher.dart';
import '$location' as _launcher;

void main(List<String> arguments) {
  final launcher = _launcher.$runtimeType();
  launcher.launch(
    arguments,
    phase: LaunchPhase.localLauncher,
    localInstallationPath: r'$_localInstallationPath',
  );
}
''';
  }

  Future<void> _runLauncherSnapshot(
    List<String> arguments, {
    String? workingDirectory,
  }) {
    return _runWithSnapshot(
      _launcherPath,
      arguments,
      snapshotPath: _launcherSnapshotPath,
      workingDirectory: workingDirectory,
    );
  }

  // === Local main ============================================================

  Future<void> _runMain(List<String> arguments) async {
    await _ensureMainIsUpToDate();
    return _runMainSnapshot(arguments);
  }

  Future<void> _ensureMainIsUpToDate() async {
    if (_mainIsUpToDate()) {
      return;
    }

    _deleteMain();
    writeFileAsString(_mainPath, _buildMainSource());
  }

  bool _mainIsUpToDate() {
    if (!fileExists(_mainPath)) {
      // No snapshot, so it's not up-to-date.
      return false;
    }

    if (fileIsNewerThanOtherFile(
      pubspecLockPath(_localInstallationPath!),
      _mainPath,
    )) {
      // The dependencies that were used to generate the snapshot might have
      // changed.
      return false;
    }

    // TODO: The contents of a relevant path dependency have changed.

    return true;
  }

  void _deleteMain() {
    removeFile(_mainPath);
    removeFile(_mainSnapshotPath);
  }

  String _buildMainSource() {
    return '''
// DO NOT EDIT. This file is generated.
// ignore_for_file: implementation_imports
import 'package:cli_launcher/cli_launcher.dart';
import '$location' as _launcher;

void main(List<String> arguments) {
  final launcher = _launcher.$runtimeType();
  launcher.launch(
    arguments,
    phase: LaunchPhase.local,
    localInstallationPath: r'$_localInstallationPath',
  );
}
''';
  }

  Future<void> _runMainSnapshot(List<String> arguments) {
    return _runWithSnapshot(
      _mainPath,
      arguments,
      snapshotPath: _mainSnapshotPath,
    );
  }

  // === Misc ==================================================================

  Future<void> _runWithSnapshot(
    String mainPath,
    List<String> arguments, {
    required String snapshotPath,
    String? workingDirectory,
  }) {
    if (fileExists(snapshotPath)) {
      return callProcess(
        'dart',
        [snapshotPath, ...arguments],
        workingDirectory: workingDirectory,
      );
    } else {
      return callProcess(
        'dart',
        [
          'compile',
          'jit-snapshot',
          '--verbosity',
          'warning',
          mainPath,
          ...arguments
        ],
        workingDirectory: workingDirectory,
      );
    }
  }

  void _checkPubDependenciesAreUpToDate() {
    if (!pubDependenciesAreUpToDate(_localInstallationPath!)) {
      throw CliLauncherException(
        'Cannot launch local installation of "$executableName" because the pub '
        'dependencies are out of date.\nRun "dart pub get" in '
        '$_localInstallationPath to bring them up to date.',
      );
    }
  }
}

class CliLauncherException implements Exception {
  CliLauncherException(this.message, {this.exitCode = 1});

  final String message;

  final int exitCode;

  @override
  String toString() => message;
}
