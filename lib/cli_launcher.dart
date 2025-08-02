import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// A function that is called to start the execution of an executable.
///
/// It is passed the arguments passed to the executable and a [LaunchContext]
/// that provides information about how the executable was launched.
typedef EntryPoint =
    FutureOr<void> Function(List<String> args, LaunchContext context);

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
  ExecutableName(this.executable, {String? package})
    : package = package ?? executable;

  /// The name of the package that contains the executable.
  final String package;

  /// The name of the executable.
  final String executable;

  @override
  String toString() => '$package:$executable';

  Map<String, Object?> _toJson() {
    return {'p': package, 'e': executable};
  }

  factory ExecutableName._fromJson(Map<String, Object?> json) {
    return ExecutableName(json['e']! as String, package: json['p']! as String);
  }
}

/// Describes an installation of an executable.
class ExecutableInstallation {
  /// Creates a new executable installation.
  ExecutableInstallation({
    String? version,
    required this.name,
    required this.isSelf,
    bool? isFromPath,
    required this.packageRoot,
  }) : _version = version,
       _isFromPath = isFromPath;

  /// The name of the executable.
  final ExecutableName name;

  /// The version of the package which contains the executable.
  String get version => _version ??= _loadVersion();

  /// Whether [packageRoot] is the root directory of the package that contains
  /// the executable.
  ///
  /// This is typically true when launching the executable during development
  /// from withing the package source directory.
  final bool isSelf;

  /// Whether the package containing the executable is dependent on through a
  /// path dependency, if known.
  bool get isFromPath => _isFromPath ??= _loadIsFromPath();

  /// The root directory of the package in which the executable is installed.
  final Directory packageRoot;

  /// The loaded [version] value, if any.
  String? _version;

  /// The loaded [isFromPath] value, if any.
  bool? _isFromPath;

  late final _pubspecLockEntry = _loadPubspecLockEntry();

  YamlMap? _loadPubspecLockEntry() {
    final pubspecLockFile = File(path.join(packageRoot.path, 'pubspec.lock'));
    final pubspecLockString = pubspecLockFile.readAsStringSync();
    final pubspecLockYaml = loadYamlDocument(
      pubspecLockString,
      sourceUrl: pubspecLockFile.uri,
    );
    final contents = pubspecLockYaml.contents as YamlMap;
    final packages = contents['packages']! as YamlMap;
    return packages[name.package] as YamlMap?;
  }

  String _loadVersion() {
    final entry = _pubspecLockEntry;
    if (entry != null) {
      return entry['version']! as String;
    }

    // The package is not in the lock file, so the executable must have been
    // activated globally from path. In this case we can take the version from
    // the pubspec.

    final pubspecFile = File(path.join(packageRoot.path, 'pubspec.yaml'));
    final pubspecString = pubspecFile.readAsStringSync();
    final pubspecYaml = loadYamlDocument(
      pubspecString,
      sourceUrl: pubspecFile.uri,
    );
    final pubspecContents = pubspecYaml.contents as YamlMap;
    return pubspecContents['version']! as String;
  }

  bool _loadIsFromPath() {
    final entry = _pubspecLockEntry;
    if (entry != null) {
      return entry['source'] == 'path';
    }

    // The package is not in the lock file, so the executable must have been
    // activated globally from path.
    return true;
  }

  bool get _pubspecLockIsUpToDate {
    final pubspecFile = File(path.join(packageRoot.path, 'pubspec.yaml'));
    final pubspecLockFile = File(path.join(packageRoot.path, 'pubspec.lock'));
    if (!pubspecLockFile.existsSync()) {
      return false;
    }

    return pubspecLockFile.lastModifiedSync().isAfter(
      pubspecFile.lastModifiedSync(),
    );
  }

  Future<bool> _updateDependencies([List<String>? pubGetArgs]) async {
    final result = await Process.start(
      'dart',
      ['pub', 'get', if (pubGetArgs != null) ...pubGetArgs],
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
      version: json['v'] as String?,
      name: ExecutableName._fromJson((json['e']! as Map).cast()),
      isSelf: json['s']! as bool,
      isFromPath: json['fp'] as bool?,
      packageRoot: Directory(json['p']! as String),
    );
  }

  Map<String, Object?> _toJson() {
    return {
      'v': _version,
      'e': name._toJson(),
      's': isSelf,
      'fp': _isFromPath,
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
  } else if (scriptPath.contains(
    path.join('.dart_tool', 'pub', 'bin', executable.package),
  )) {
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
    isSelf: false,
    packageRoot: packageRoot,
  );
}

ExecutableInstallation? _findLocalInstallation(
  ExecutableName executable,
  bool findSelf,
  Directory start,
) {
  if (path.equals(start.path, start.parent.path)) {
    return null;
  }

  final pubspecFile = File(path.join(start.path, 'pubspec.yaml'));
  if (pubspecFile.existsSync()) {
    final pubspecString = pubspecFile.readAsStringSync();
    String? name;
    YamlMap? dependencies;
    YamlMap? devDependencies;

    try {
      final pubspecYaml = loadYamlDocument(
        pubspecString,
        sourceUrl: pubspecFile.uri,
      );
      final pubspec = pubspecYaml.contents as YamlMap;
      name = pubspec['name'] as String?;
      dependencies = pubspec['dependencies'] as YamlMap?;
      devDependencies = pubspec['dev_dependencies'] as YamlMap?;
    } catch (error, stackTrace) {
      throw StateError(
        'Could not parse pubspec.yaml at ${start.path}.\n$error\n$stackTrace',
      );
    }

    final isSelf = name == executable.package;

    if ((findSelf && isSelf) ||
        (dependencies != null &&
            dependencies.containsKey(executable.package)) ||
        (devDependencies != null &&
            devDependencies.containsKey(executable.package))) {
      return ExecutableInstallation(
        name: executable,
        isSelf: isSelf,
        packageRoot: start,
      );
    }
  }

  return _findLocalInstallation(executable, findSelf, start.parent);
}

/// The configuration for launching an executable.
class LaunchConfig {
  /// Creates a new launch configuration.
  LaunchConfig({
    required this.name,
    required this.entrypoint,
    this.launchFromSelf = true,
    this.resolveLocalLaunchConfig,
  });

  /// The name of the executable to launch.
  final ExecutableName name;

  /// The entry point to start running the logic of the executable.
  final EntryPoint entrypoint;

  /// When launching from within the source package, whether to launch the
  /// executable from the source package.
  final bool launchFromSelf;

  /// Resolver that is called to resolve a [LocalLaunchConfig] in case a local
  /// installation of the executable launched.
  final ResolveLocalLaunchConfig? resolveLocalLaunchConfig;
}

/// A function that resolves a [LocalLaunchConfig] for launching a local
/// installation of an executable.
///
/// It is called with the [LaunchContext] in which the local installation will
/// be launched.
typedef ResolveLocalLaunchConfig =
    Future<LocalLaunchConfig> Function(LaunchContext context);

/// Configuration options for launching a local installation of an executable.
class LocalLaunchConfig {
  /// Creates a new local launch configuration.
  LocalLaunchConfig({this.pubGetArgs, this.dartRunArgs});

  /// Additional arguments to pass to `dart pub get` when dependencies are out
  /// of date.
  final List<String>? pubGetArgs;

  /// Additional arguments to pass to `dart run` when launching the executable.
  final List<String>? dartRunArgs;
}

const _launchContextMarker = 'CLI_LAUNCHER_LAUNCH_CONTEXT';

LaunchContext? _extractLaunchContext(List<String> args) {
  if (args.length < 2 || args.first != _launchContextMarker) {
    return null;
  }

  args.removeAt(0); // Remove the marker.
  final launchContextString = args.removeAt(0); // Remove the launch context.

  return LaunchContext._fromJson(
    (jsonDecode(launchContextString) as Map).cast(),
  );
}

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
  args = args.toList(); // Make a mutable copy of the arguments.
  var launchContext = _extractLaunchContext(args);
  if (launchContext != null) {
    // We are running a local installation that was launched by global
    // installation. The global installation will have set the environment
    // variable for the _environmentLaunchContext.

    // We restore the working directory from which the global installation was
    // launched before launching the local installation.
    Directory.current = launchContext.directory;

    return config.entrypoint(args, launchContext);
  }

  // We are running a global installation.
  final globalInstallation = _findGlobalInstallation(config.name);

  // Try to find a local installation.
  final localInstallation = _findLocalInstallation(
    config.name,
    config.launchFromSelf,
    Directory.current,
  );

  launchContext = LaunchContext(
    directory: Directory.current,
    globalInstallation: globalInstallation,
    localInstallation: localInstallation,
  );

  // Resolve local launch configuration if provided.
  LocalLaunchConfig? localConfig;
  if (config.resolveLocalLaunchConfig != null) {
    localConfig = await config.resolveLocalLaunchConfig!(launchContext);
  }

  if (localInstallation != null && !localInstallation._pubspecLockIsUpToDate) {
    // Ensure that dependencies are up to date so that we can resolve the
    // version of the local installation.
    if (!await localInstallation._updateDependencies(localConfig?.pubGetArgs)) {
      // Failed to update dependencies so we abort.
      return;
    }
  }

  if (localInstallation != null &&
      (localInstallation.isSelf ||
          localInstallation.isFromPath ||
          localInstallation.version != globalInstallation.version)) {
    // We found a local installation which is different from the global
    // installation so we launch the local installation.
    final process = await Process.start(
      'dart',
      [
        'run',
        ...?localConfig?.dartRunArgs,
        config.name.toString(),
        _launchContextMarker,
        jsonEncode(launchContext._toJson()),
        ...args,
      ],
      mode: ProcessStartMode.inheritStdio,
      workingDirectory: localInstallation.packageRoot.path,
      // Necessary so that `dart.bat` wrapper can be found on Windows.
      runInShell: Platform.isWindows,
    );
    exitCode = await process.exitCode;
    return;
  }

  // We did not find a local installation or global and local installations have
  // the same version so we launch the global installation.
  return config.entrypoint(args, launchContext);
}
