import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// A function that is called to start the execution of an executable.
///
/// It is passed the arguments passed to the executable and a [LaunchContext]
/// that provides information about how the executable was launched.
typedef EntryPoint = FutureOr<void> Function(
  List<String> args,
  LaunchContext context,
);

/// A context that provides information about how an executable was launched.
///
/// It is provided to the [EntryPoint] function of an executable.
///
/// See also:
///
/// - [LaunchConfig.entrypoint] for defining the executable entry point.
class LaunchContext {
  /// Creates a new launch context.
  LaunchContext({
    required this.directory,
    this.globalInstallation,
    this.localInstallation,
  });

  /// The directory in which the user invoked the executable.
  final Directory directory;

  /// The global installation of the executable.
  ///
  /// This is `null` if the local installation is launched by running
  /// `dart run <package>:<executable>` from the package root where the
  /// executable is installed.
  final ExecutableInstallation? globalInstallation;

  /// The local installation of the executable.
  ///
  /// This is `null` if no local installation was found.
  final ExecutableInstallation? localInstallation;

  factory LaunchContext._fromJson(Map<String, Object?> json) {
    return LaunchContext(
      directory: Directory(json['d']! as String),
      globalInstallation: json['g'] == null
          ? null
          : ExecutableInstallation._fromJson((json['g'] as Map).cast()),
      localInstallation: json['l'] == null
          ? null
          : ExecutableInstallation._fromJson((json['l'] as Map).cast()),
    );
  }

  Map<String, Object?> _toJson() {
    return {
      'd': directory.path,
      'g': globalInstallation?._toJson(),
      'l': localInstallation?._toJson(),
    };
  }
}

/// The package qualified name of an executable.
class ExecutableName {
  /// Creates a new executable name.
  ExecutableName(
    this.executable, {
    String? package,
  }) : package = package ?? executable;

  /// The name of the package that contains the executable.
  final String package;

  /// The name of the executable.
  final String executable;

  @override
  String toString() => '$package:$executable';

  Map<String, Object?> _toJson() {
    return {
      'p': package,
      'e': executable,
    };
  }

  factory ExecutableName._fromJson(Map<String, Object?> json) {
    return ExecutableName(
      json['e']! as String,
      package: json['p']! as String,
    );
  }
}

/// Describes an installation of an executable.
class ExecutableInstallation {
  /// Creates a new executable installation.
  ExecutableInstallation({
    String? version,
    required this.name,
    required this.packageRoot,
  }) : _version = version;

  /// The name of the executable.
  final ExecutableName name;

  /// The version of the package which contains the executable.
  late final String version = _version ?? _loadVersion();

  /// The root directory of the package in which the executable is installed.
  final Directory packageRoot;

  /// The preloaded [version], if any.
  final String? _version;

  String _loadVersion() {
    final pubspecLockFile = File(path.join(packageRoot.path, 'pubspec.lock'));
    final pubspecLockString = pubspecLockFile.readAsStringSync();
    final pubspecLockYaml =
        loadYamlDocument(pubspecLockString, sourceUrl: pubspecLockFile.uri);
    final contents = pubspecLockYaml.contents as YamlMap;
    final packages = contents['packages']! as YamlMap;
    final package = packages[name.package] as YamlMap?;
    if (package != null) {
      return package['version']! as String;
    }

    // The package is not in the lock file, so the executable must have been
    // activated globally from path. In this case we can take the version from
    // the pubspec.

    final pubspecFile = File(path.join(packageRoot.path, 'pubspec.yaml'));
    final pubspecString = pubspecFile.readAsStringSync();
    final pubspecYaml =
        loadYamlDocument(pubspecString, sourceUrl: pubspecFile.uri);
    final pubspecContents = pubspecYaml.contents as YamlMap;
    return pubspecContents['version']! as String;
  }

  bool get _pubspecLockIsUpToDate {
    final pubspecFile = File(path.join(packageRoot.path, 'pubspec.yaml'));
    final pubspecLockFile = File(path.join(packageRoot.path, 'pubspec.lock'));
    if (!pubspecLockFile.existsSync()) {
      return false;
    }

    return pubspecLockFile
        .lastModifiedSync()
        .isAfter(pubspecFile.lastModifiedSync());
  }

  Future<bool> _updateDependencies() async {
    final result = await Process.start(
      'dart',
      [
        'pub',
        'get',
      ],
      mode: ProcessStartMode.inheritStdio,
      workingDirectory: packageRoot.path,
      // Necessary so that `dart.bat` wrapper can be found on Windows.
      runInShell: Platform.isWindows,
    );
    exitCode = await result.exitCode;
    return exitCode == 0;
  }

  factory ExecutableInstallation._fromJson(Map<String, Object?> json) {
    return ExecutableInstallation(
      version: json['v']! as String,
      name: ExecutableName._fromJson((json['e']! as Map).cast()),
      packageRoot: Directory(json['p']! as String),
    );
  }

  Map<String, Object?> _toJson() {
    return {
      'v': version,
      'e': name._toJson(),
      'p': packageRoot.path,
    };
  }
}

ExecutableInstallation _findGlobalInstallation(ExecutableName executable) {
  final Directory packageRoot;

  final scriptPath = Platform.script.toFilePath();
  if (scriptPath.contains(path.join('global_packages', executable.package))) {
    // The snapshot of an executable that is globally installed in the pub cache
    // is located in the `bin` directory in a generated package.
    // This package is located in `<pub-cache>/global_packages/<package>`.
    packageRoot = File(scriptPath).parent.parent;
  } else if (scriptPath
      .contains(path.join('.dart_tool', 'pub', 'bin', executable.package))) {
    // The snapshot of an executable that is globally installed from path
    // is located in the `.dart_tool/pub/bin/<package>` directory in
    // the specified package.
    packageRoot = File(scriptPath).parent.parent.parent.parent.parent;
  } else {
    throw StateError(
      'Could not find global installation of $executable. '
      'This is likely a bug in `package:cli_launcher`.',
    );
  }

  return ExecutableInstallation(
    name: executable,
    packageRoot: packageRoot,
  );
}

ExecutableInstallation? _findLocalInstallation(
  ExecutableName executable,
  Directory start,
) {
  if (path.equals(start.path, start.parent.path)) {
    return null;
  }

  final pubspecFile = File(path.join(start.path, 'pubspec.yaml'));
  if (pubspecFile.existsSync()) {
    final pubspecString = pubspecFile.readAsStringSync();
    YamlMap? dependencies;
    YamlMap? devDependencies;

    try {
      final pubspecYaml =
          loadYamlDocument(pubspecString, sourceUrl: pubspecFile.uri);
      final pubspec = pubspecYaml.contents as YamlMap;
      dependencies = pubspec['dependencies'] as YamlMap?;
      devDependencies = pubspec['dev_dependencies'] as YamlMap?;
    } catch (error, stackTrace) {
      throw StateError(
        'Could not parse pubspec.yaml at ${start.path}.\n$error\n$stackTrace',
      );
    }

    if ((dependencies != null &&
            dependencies.containsKey(executable.package)) ||
        (devDependencies != null &&
            devDependencies.containsKey(executable.package))) {
      return ExecutableInstallation(
        name: executable,
        packageRoot: start,
      );
    }
  }

  return _findLocalInstallation(executable, start.parent);
}

/// The configuration for launching an executable.
class LaunchConfig {
  /// Creates a new launch configuration.
  LaunchConfig({
    required this.name,
    required this.entrypoint,
  });

  /// The name of the executable to launch.
  final ExecutableName name;

  /// The entry point to start running the logic of the executable.
  final EntryPoint entrypoint;
}

const _launchContextEnvVar = 'CLI_LAUNCHER_LAUNCH_CONTEXT';

LaunchContext? get _environmentLaunchContext {
  final launchContextString = Platform.environment[_launchContextEnvVar];
  if (launchContextString == null) return null;
  return LaunchContext._fromJson(
    (jsonDecode(launchContextString) as Map).cast(),
  );
}

bool get _isRunningLocalInstallation =>
    // The snapshot generate by pub for a locally installed executable lives
    // somewhere within the `.dart_tool/pub` directory in the package.
    // This heuristic detects an executable launched through
    // `dart run <package>:<executable` as a local installation, as well as an
    // executable that was globally installed from path, when executed within
    // its source package.
    path.isWithin(
      path.join(Directory.current.path, '.dart_tool', 'pub'),
      Platform.script.toFilePath(),
    );

/// Launches an executable with the given [args] and [config].
///
/// ```dart
/// void main(List<String> args) {
///   launchExecutable(
///     args,
///     LaunchConfig(
///       name: ExecutableName('foo'),
///       entrypoint: (args, launchContext) {
///         print('Hello world!');
///       },
///     ),
///   );
/// }
/// ```
FutureOr<void> launchExecutable(List<String> args, LaunchConfig config) async {
  var launchContext = _environmentLaunchContext;
  if (launchContext != null) {
    // We are running a local installation that was launched by global
    // installation. The global installation will have set the environment
    // variable for the _environmentLaunchContext.

    // We restore the working directory from which the global installation was
    // launched before launching the local installation.
    Directory.current = launchContext.directory;

    return config.entrypoint(args, launchContext);
  }

  if (_isRunningLocalInstallation) {
    // We are running a local installation that was launched directly. We know
    // that it was not launched by the global installation because the global
    // installation would have provided the launch context through the
    // environment.

    launchContext = LaunchContext(
      directory: Directory.current,
      localInstallation: ExecutableInstallation(
        name: config.name,
        packageRoot: Directory.current,
      ),
    );

    return config.entrypoint(args, launchContext);
  }

  // We are running a global installation.
  final globalInstallation = _findGlobalInstallation(config.name);

  // Try to find a local installation.
  final localInstallation = _findLocalInstallation(
    config.name,
    Directory.current,
  );

  launchContext = LaunchContext(
    directory: Directory.current,
    globalInstallation: globalInstallation,
    localInstallation: localInstallation,
  );

  if (localInstallation != null && !localInstallation._pubspecLockIsUpToDate) {
    // Ensure that dependencies are up to date so that we can resolve the
    // version of the local installation.
    if (!await localInstallation._updateDependencies()) {
      // Failed to update dependencies so we abort.
      return;
    }
  }

  if (localInstallation != null &&
      localInstallation.version != globalInstallation.version) {
    // We found a local installation which has a different version than the
    // global install so we launch the local installation.
    final process = await Process.start(
      'dart',
      ['run', config.name.toString(), ...args],
      mode: ProcessStartMode.inheritStdio,
      workingDirectory: localInstallation.packageRoot.path,
      // Necessary so that `dart.bat` wrapper can be found on Windows.
      runInShell: Platform.isWindows,
      environment: {
        ...Platform.environment,
        _launchContextEnvVar: jsonEncode(launchContext._toJson()),
      },
    );
    exitCode = await process.exitCode;
    return;
  }

  // We did not find a local installation or global and local installations have
  // the same version so we launch the global installation.
  return config.entrypoint(args, launchContext);
}
