import 'dart:io';

import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:yaml/yaml.dart';

import 'error.dart';
import 'io.dart';
import 'launch_config.dart';
import 'launcher.dart';
import 'logging.dart';
import 'pub.dart';

class LocalLaunchContext {
  LocalLaunchContext({
    required this.installationPackagePath,
    required this.executable,
    required this.executableConfig,
  });

  final String installationPackagePath;
  final PackageExecutable executable;
  final ExecutableConfig executableConfig;

  late final pubspecLockPath = p.join(installationPackagePath, 'pubspec.lock');

  late final cacheDirectory = p.join(
    installationPackagePath,
    '.dart_tool',
    'cli_launcher',
    executable.package,
    executable.executable,
  );

  late final launchScriptPath =
      p.join(cacheDirectory, 'launch.${Platform.isWindows ? 'ps1' : 'sh'}');

  late final mainPath = p.join(cacheDirectory, 'main.dart');

  late final snapshotPath = p.join(cacheDirectory, 'main.snapshot');
}

Future<LocalLaunchContext?> resolveLocalLaunchContext({
  required PackageExecutable executable,
}) async {
  final currentDirectory = Directory.current.path;

  logger.trace(
    'Resolving local launch context starting at "$currentDirectory".',
  );

  for (final directory in walkUpwards(currentDirectory)) {
    final context = await resolveLocalLaunchContextForDirectory(
      directory: directory,
      executable: executable,
    );
    if (context != null) {
      logger.trace('Resolved local launch context for "$directory".');
      return context;
    }
  }

  logger.trace('Did not resolve a local launch context.');

  return null;
}

Future<LocalLaunchContext?> resolveLocalLaunchContextForDirectory({
  required String directory,
  required PackageExecutable executable,
}) async {
  final pubspecFile = pubspecPath(directory);
  if (!fileExists(pubspecFile)) {
    return null;
  }

  final pubspecString = readFileAsString(pubspecFile);
  final Pubspec pubspec;
  try {
    pubspec = Pubspec.parse(
      pubspecString,
      sourceUrl: Uri.parse(pubspecFile),
    );
  } catch (error) {
    logger.trace(
      'Found invalid pubspec.yaml file while trying to find a local '
      'installation of "$executable" at $pubspecFile:\n$error',
    );
    return null;
  }

  if (pubspec.name != executable.package &&
      !pubspec.dependencies.containsKey(executable.package) &&
      !pubspec.devDependencies.containsKey(executable.package)) {
    // No reference to the package in the pubspec.
    return null;
  }

  _checkPubDependenciesAreUpToDate(
    directory: directory,
    executable: executable,
  );

  final packageConfig =
      // We checked that pub dependencies are up-to-date, so we can assume
      // that a package_config.json file exists.
      (await findPackageConfig(Directory(directory), recurse: false))!;

  final cliPackageRoot = packageConfig.packages
      .firstWhere(
        (resolvedPackage) => resolvedPackage.name == executable.package,
      )
      .root;

  final cliPackagePubspecFile = pubspecPath(cliPackageRoot.toFilePath());
  final cliPackagePubspecString = readFileAsString(cliPackagePubspecFile);
  YamlNode cliPackagePubspecYaml;
  try {
    cliPackagePubspecYaml = loadYamlNode(
      cliPackagePubspecString,
      sourceUrl: Uri.parse(cliPackagePubspecFile),
    );
  } catch (error) {
    throw CliLauncherException(
      'Found invalid pubspec.yaml file while trying to find a local '
      'installation of "$executable" at $cliPackagePubspecFile:\n$error',
    );
  }

  final launchConfig = LaunchConfig.fromPubspecYaml(
    node: cliPackagePubspecYaml,
  );
  if (launchConfig == null) {
    return null;
  }

  final executableConfig = launchConfig.executables[executable.executable];
  if (executableConfig != null) {
    return LocalLaunchContext(
      installationPackagePath: directory,
      executable: executable,
      executableConfig: executableConfig,
    );
  }

  return null;
}

void _checkPubDependenciesAreUpToDate({
  required String directory,
  required PackageExecutable executable,
}) {
  if (!pubDependenciesAreUpToDate(directory)) {
    throw CliLauncherException(
      'Cannot launch local installation of "$executable" '
      'because the pub dependencies are out of date.\nRun "dart pub get" in '
      '$directory to bring them up to date.',
    );
  }
}
