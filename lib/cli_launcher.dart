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
    bool? requiresFlutter,
    required this.packageRoot,
    Directory? lockFileRoot,
  }) : _version = version,
       _isFromPath = isFromPath,
       _requiresFlutter = requiresFlutter,
       lockFileRoot = lockFileRoot ?? packageRoot;

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

  /// Whether the package or its workspace requires the Flutter SDK.
  bool get requiresFlutter => _requiresFlutter ??= _loadRequiresFlutter();

  /// The root directory of the package in which the executable is installed.
  final Directory packageRoot;

  /// The root directory containing the `pubspec.lock` file.
  ///
  /// For workspace member packages this is the workspace root, since
  /// `pubspec.lock` is only located there. For non-workspace packages this is
  /// the same as [packageRoot].
  final Directory lockFileRoot;

  /// The loaded [version] value, if any.
  String? _version;

  /// The loaded [isFromPath] value, if any.
  bool? _isFromPath;

  /// The loaded [requiresFlutter] value, if any.
  bool? _requiresFlutter;

  late final _pubspecLockEntry = _loadPubspecLockEntry();

  YamlMap? _loadPubspecLockEntry() {
    final pubspecLockFile = File(path.join(lockFileRoot.path, 'pubspec.lock'));
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

  bool _loadRequiresFlutter() {
    // Fast path: check package_config.json if it's up to date.
    final packageConfigFile = File(
      path.join(lockFileRoot.path, '.dart_tool', 'package_config.json'),
    );
    if (packageConfigFile.existsSync() &&
        !packageConfigFile.lastModifiedSync().isBefore(
          File(path.join(packageRoot.path, 'pubspec.yaml')).lastModifiedSync(),
        )) {
      final packageConfig =
          jsonDecode(packageConfigFile.readAsStringSync())
              as Map<String, Object?>;
      final packages = packageConfig['packages'] as List<Object?>?;
      if (packages != null) {
        return packages.any(
          (p) => (p as Map<String, Object?>)['name'] == 'flutter',
        );
      }
    }

    // Fallback: scan pubspec.yaml files.
    final rootPubspecFile = File(path.join(lockFileRoot.path, 'pubspec.yaml'));
    final rootPubspec = _parsePubspec(rootPubspecFile);
    final workspace = rootPubspec['workspace'] as YamlList?;

    if (workspace != null) {
      // Check all workspace members.
      for (final entry in workspace) {
        final memberPubspecFile = File(
          path.join(lockFileRoot.path, entry as String, 'pubspec.yaml'),
        );
        if (memberPubspecFile.existsSync()) {
          final memberPubspec = _parsePubspec(memberPubspecFile);
          if (_pubspecDependsOnFlutter(memberPubspec)) {
            return true;
          }
        }
      }
      return _pubspecDependsOnFlutter(rootPubspec);
    }

    final pubspec = lockFileRoot.path == packageRoot.path
        ? rootPubspec
        : _parsePubspec(File(path.join(packageRoot.path, 'pubspec.yaml')));
    return _pubspecDependsOnFlutter(pubspec);
  }

  bool get _pubspecLockIsUpToDate {
    final pubspecFile = File(path.join(packageRoot.path, 'pubspec.yaml'));
    final pubspecLockFile = File(path.join(lockFileRoot.path, 'pubspec.lock'));
    if (!pubspecLockFile.existsSync()) {
      _debug('${_relativePath(pubspecLockFile.path)} does not exist.');
      return false;
    }

    final pubspecModified = pubspecFile.lastModifiedSync();
    final lockModified = pubspecLockFile.lastModifiedSync();
    final upToDate = !lockModified.isBefore(pubspecModified);
    _debug(
      '${_relativePath(pubspecFile.path)} modified at ${pubspecModified.toIso8601String()}, '
      '${_relativePath(pubspecLockFile.path)} modified at ${lockModified.toIso8601String()}. '
      'Dependencies are ${upToDate ? 'up to date' : 'out of date'}.',
    );
    return upToDate;
  }

  Future<void> _updateDependencies([List<String>? pubGetArgs]) async {
    final command = requiresFlutter ? 'flutter' : 'dart';
    final result = await _runProcess(
      command,
      ['pub', 'get', if (pubGetArgs != null) ...pubGetArgs],
      // For workspace members, run from the workspace root so that path
      // dependencies are resolved consistently with the existing pubspec.lock.
      workingDirectory: lockFileRoot.path,
    );
    if (result.exitCode != 0) {
      throw _LaunchError(
        result.exitCode,
        'Failed to resolve dependencies for ${name.package}.\n'
        'Ran "$command pub get" in ${lockFileRoot.path}.\n'
        '${result.combined}',
      );
    }
  }

  factory ExecutableInstallation._fromJson(Map<String, Object?> json) {
    final packageRoot = Directory(json['p']! as String);
    return ExecutableInstallation(
      version: json['v'] as String?,
      name: ExecutableName._fromJson((json['e']! as Map).cast()),
      isSelf: json['s']! as bool,
      isFromPath: json['fp'] as bool?,
      requiresFlutter: json['f'] as bool?,
      packageRoot: packageRoot,
      lockFileRoot: json['lr'] != null
          ? Directory(json['lr']! as String)
          : null,
    );
  }

  Map<String, Object?> _toJson() {
    return {
      'v': _version,
      'e': name._toJson(),
      's': isSelf,
      'fp': _isFromPath,
      'f': _requiresFlutter,
      'p': packageRoot.path,
      if (lockFileRoot.path != packageRoot.path) 'lr': lockFileRoot.path,
    };
  }
}

YamlMap _parsePubspec(File file) {
  final yaml = loadYamlDocument(file.readAsStringSync(), sourceUrl: file.uri);
  return yaml.contents as YamlMap;
}

bool _pubspecDependsOnFlutter(YamlMap pubspec) {
  final deps = pubspec['dependencies'] as YamlMap?;
  return deps != null && deps.containsKey('flutter');
}

ExecutableInstallation _findGlobalInstallation(ExecutableName executable) {
  _debug('Finding global installation of $executable.');
  _debug('Platform.script: ${Platform.script}');
  _debug('Platform.resolvedExecutable: ${Platform.resolvedExecutable}');

  final Directory packageRoot;
  Directory? lockFileRootOverride;

  final scriptPath = Platform.script.toFilePath();
  if (scriptPath.contains(path.join('global_packages', executable.package))) {
    // The snapshot of an executable that is globally installed in the pub cache
    // is located in the `bin` directory in a generated package.
    // This package is located in `<pub-cache>/global_packages/<package>`.
    packageRoot = File(scriptPath).parent.parent;
    _debug(
      'Detected pub cache global installation at ${_relativePath(packageRoot.path)}.',
    );
  } else if (scriptPath.contains(
    path.join('.dart_tool', 'pub', 'bin', executable.package),
  )) {
    final (:root, :lockFileRoot) = _findPathActivatedPackageRoot(
      scriptPath,
      executable,
    );
    packageRoot = root;
    lockFileRootOverride = lockFileRoot;
    _debug(
      'Detected path-activated installation at ${_relativePath(packageRoot.path)}.',
    );
    if (lockFileRootOverride != null) {
      _debug('Lock file root: ${_relativePath(lockFileRootOverride.path)}');
    }
  } else if (Platform.resolvedExecutable.contains(
    path.join('app-bundles', executable.package),
  )) {
    // The binary of an executable installed via `dart install` is located
    // in the `bundle/bin` directory within the package's app bundle.
    // Structure: <install-dir>/app-bundles/<package>/<source>/bundle/bin/<executable>
    // Platform.resolvedExecutable is used instead of Platform.script because
    // for AOT-compiled binaries, Platform.script may not contain the actual
    // binary path (e.g. when invoked via a shell).
    packageRoot = File(Platform.resolvedExecutable).parent.parent.parent;
    _debug(
      'Detected dart install installation at ${_relativePath(packageRoot.path)}.',
    );
  } else {
    throw StateError(
      'Could not find global installation of $executable.\n'
      'Platform.script: ${Platform.script}\n'
      'Platform.resolvedExecutable: ${Platform.resolvedExecutable}\n'
      'This is likely a bug in `package:cli_launcher`.',
    );
  }

  return ExecutableInstallation(
    name: executable,
    isSelf: false,
    packageRoot: packageRoot,
    lockFileRoot: lockFileRootOverride,
  );
}

({Directory root, Directory? lockFileRoot}) _findPathActivatedPackageRoot(
  String scriptPath,
  ExecutableName executable,
) {
  // The snapshot of an executable that is globally installed from path
  // is located in the `.dart_tool/pub/bin/<package>` directory in
  // the specified package.
  final packageRoot = File(scriptPath).parent.parent.parent.parent.parent;

  final pubspecFile = File(path.join(packageRoot.path, 'pubspec.yaml'));
  final pubspecString = pubspecFile.readAsStringSync();
  final pubspecYaml = loadYamlDocument(
    pubspecString,
    sourceUrl: pubspecFile.uri,
  );
  final pubspec = pubspecYaml.contents as YamlMap;

  final workspace = pubspec['workspace'] as YamlList?;
  if (workspace == null) {
    return (root: packageRoot, lockFileRoot: null);
  }

  for (final entry in workspace) {
    final packagePath = path.join(packageRoot.path, entry as String);
    final subPubspecFile = File(path.join(packagePath, 'pubspec.yaml'));
    if (subPubspecFile.existsSync()) {
      final subPubspecString = subPubspecFile.readAsStringSync();
      final subPubspecYaml = loadYamlDocument(
        subPubspecString,
        sourceUrl: subPubspecFile.uri,
      );
      final subPubspec = subPubspecYaml.contents as YamlMap;
      if (subPubspec['name'] == executable.package) {
        return (root: Directory(packagePath), lockFileRoot: packageRoot);
      }
    }
  }

  return (root: packageRoot, lockFileRoot: null);
}

ExecutableInstallation? _findLocalInstallation(
  ExecutableName executable,
  bool findSelf,
  Directory start,
) {
  if (path.equals(start.path, start.parent.path)) {
    _debug('Reached filesystem root without finding local installation.');
    return null;
  }

  final pubspecFile = File(path.join(start.path, 'pubspec.yaml'));
  if (pubspecFile.existsSync()) {
    _debug(
      'Checking ${_relativePath(pubspecFile.path)} for local installation.',
    );
    final pubspecString = pubspecFile.readAsStringSync();
    String? name;
    String? resolution;
    YamlMap? dependencies;
    YamlMap? devDependencies;
    YamlList? workspace;

    try {
      final pubspecYaml = loadYamlDocument(
        pubspecString,
        sourceUrl: pubspecFile.uri,
      );
      final pubspec = pubspecYaml.contents as YamlMap;
      name = pubspec['name'] as String?;
      resolution = pubspec['resolution'] as String?;
      dependencies = pubspec['dependencies'] as YamlMap?;
      devDependencies = pubspec['dev_dependencies'] as YamlMap?;
      workspace = pubspec['workspace'] as YamlList?;
    } catch (error) {
      throw StateError('Could not parse ${pubspecFile.path}: $error');
    }

    final isSelf = name == executable.package;

    if ((findSelf && isSelf) ||
        (dependencies != null &&
            dependencies.containsKey(executable.package)) ||
        (devDependencies != null &&
            devDependencies.containsKey(executable.package))) {
      // If this is a workspace root and the executable package is a workspace
      // member, resolve the actual package directory instead of using the
      // workspace root as the package root.
      var packageRoot = start;
      Directory? lockFileRoot;
      if (workspace != null && !isSelf) {
        for (final entry in workspace) {
          final memberPath = path.join(start.path, entry as String);
          final memberPubspecFile = File(
            path.join(memberPath, 'pubspec.yaml'),
          );
          if (memberPubspecFile.existsSync()) {
            final memberPubspecString = memberPubspecFile.readAsStringSync();
            final memberPubspecYaml = loadYamlDocument(
              memberPubspecString,
              sourceUrl: memberPubspecFile.uri,
            );
            final memberPubspec = memberPubspecYaml.contents as YamlMap;
            if (memberPubspec['name'] == executable.package) {
              packageRoot = Directory(memberPath);
              lockFileRoot = start;
              _debug(
                'Resolved workspace member at '
                '${_relativePath(memberPath)}.',
              );
              break;
            }
          }
        }
      } else if (resolution == 'workspace') {
        lockFileRoot = _findWorkspaceRoot(start) ??
            (throw StateError(
              'Could not find workspace root for package at '
              '${start.path}. The pubspec.yaml has '
              '"resolution: workspace" but no parent directory '
              'contains a pubspec.yaml with a "workspace" field.',
            ));
      }

      _debug(
        'Found local installation at ${_relativePath(packageRoot.path)} '
        '(isSelf: $isSelf, resolution: $resolution).',
      );
      return ExecutableInstallation(
        name: executable,
        isSelf: isSelf,
        packageRoot: packageRoot,
        lockFileRoot: lockFileRoot,
      );
    }
  }

  return _findLocalInstallation(executable, findSelf, start.parent);
}

Directory? _findWorkspaceRoot(Directory memberDir) {
  var current = memberDir.parent;
  while (!path.equals(current.path, current.parent.path)) {
    final pubspecFile = File(path.join(current.path, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      final pubspecString = pubspecFile.readAsStringSync();
      final pubspecYaml = loadYamlDocument(
        pubspecString,
        sourceUrl: pubspecFile.uri,
      );
      final pubspec = pubspecYaml.contents as YamlMap;
      if (pubspec['workspace'] != null) {
        return current;
      }
    }
    current = current.parent;
  }
  return null;
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

/// An error that indicates the launch process failed with a specific exit code.
class _LaunchError {
  _LaunchError(this.exitCode, this.message);

  final int exitCode;
  final String message;
}

/// The result of running a process with captured output.
class _ProcessOutput {
  _ProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  /// Returns the combined stdout and stderr output, with non-empty sections
  /// separated by a newline.
  String get combined {
    final parts = <String>[
      if (stdout.isNotEmpty) stdout,
      if (stderr.isNotEmpty) stderr,
    ];
    return parts.join('\n');
  }
}

/// Runs a process and captures its stdout and stderr output.
Future<_ProcessOutput> _runProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    // Necessary so that `dart.bat`/`flutter.bat` wrapper can be found on
    // Windows.
    runInShell: Platform.isWindows,
  );
  final results = await (
    process.stdout.transform(utf8.decoder).join(),
    process.stderr.transform(utf8.decoder).join(),
    process.exitCode,
  ).wait;
  return _ProcessOutput(
    stdout: results.$1,
    stderr: results.$2,
    exitCode: results.$3,
  );
}

final _verbose = Platform.environment['CLI_LAUNCHER_VERBOSE'] == '1';

void _debug(String message) {
  if (_verbose) {
    stderr.writeln('[cli_launcher] $message');
  }
}

/// Returns [filePath] relative to the current working directory, or the
/// absolute path if it is not under the current working directory.
String _relativePath(String filePath) {
  final relative = path.relative(filePath);
  // If the relative path starts with too many `..` segments, the absolute
  // path is more readable.
  if (relative.startsWith('..${path.separator}..${path.separator}..')) {
    return filePath;
  }
  return relative;
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
  _debug('Working directory: ${Directory.current.path}');
  args = args.toList(); // Make a mutable copy of the arguments.
  final launchContext = _extractLaunchContext(args);
  if (launchContext != null) {
    // We are running a local installation that was launched by the global
    // installation.
    _debug('Detected relaunch from global installation.');

    // We restore the working directory from which the global installation was
    // launched before launching the local installation.
    Directory.current = launchContext.directory;
    _debug('Restored working directory to ${launchContext.directory.path}.');

    return config.entrypoint(args, launchContext);
  }

  try {
    await _launchFromGlobalInstallation(args, config);
  } on _LaunchError catch (error) {
    exitCode = error.exitCode;
    stderr.writeln(error.message);
  }
}

Future<void> _launchFromGlobalInstallation(
  List<String> args,
  LaunchConfig config,
) async {
  final globalInstallation = _findGlobalInstallation(config.name);

  // Try to find a local installation.
  final localInstallation = _findLocalInstallation(
    config.name,
    config.launchFromSelf,
    Directory.current,
  );

  final launchContext = LaunchContext(
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
    _debug('Dependencies are out of date. Running pub get.');
    await localInstallation._updateDependencies(localConfig?.pubGetArgs);
  }

  if (localInstallation != null &&
      (localInstallation.isSelf ||
          localInstallation.isFromPath ||
          localInstallation.version != globalInstallation.version)) {
    _debug(
      'Launching local installation '
      '(isSelf: ${localInstallation.isSelf}, '
      'isFromPath: ${localInstallation.isFromPath}, '
      'local version: ${localInstallation.version}, '
      'global version: ${globalInstallation.version}).',
    );
    // We found a local installation which is different from the global
    // installation so we launch the local installation, passing through
    // stdio and exit code directly.
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
  if (localInstallation == null) {
    _debug('No local installation found. Launching global installation.');
  } else {
    _debug(
      'Local and global versions match '
      '(${globalInstallation.version}). Launching global installation.',
    );
  }
  return config.entrypoint(args, launchContext);
}
