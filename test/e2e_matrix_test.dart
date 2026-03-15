@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Root of the cli_launcher package (this package).
final _cliLauncherRoot = p.normalize(p.absolute(Directory.current.path));

enum InstallMethod { pathActivated, dartInstall }

enum PackageStructure { standalone, workspaceMember }

String _snakeCase(String camelCase) {
  return camelCase.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m[0]!.toLowerCase()}',
  );
}

void main() {
  for (final installMethod in InstallMethod.values) {
    for (final structure in PackageStructure.values) {
      final groupName = '${installMethod.name}, ${structure.name}';
      // Use unique names per group to avoid global activation conflicts.
      final packageName = 'cli_launcher_matrix_'
          '${_snakeCase(installMethod.name)}_${_snakeCase(structure.name)}';
      final executableName =
          'matrix_${_snakeCase(installMethod.name)}_${_snakeCase(structure.name)}';

      group(groupName, () {
        _Fixture? fixture;

        setUpAll(() async {
          fixture = await _Fixture.create(
            installMethod: installMethod,
            structure: structure,
            packageName: packageName,
            executableName: executableName,
          );
        });

        tearDownAll(() async {
          fixture?.dispose();
        });

        test('no local installation', () {
          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.emptyDir,
          );
          expect(stdout, contains('local=null'));
          expect(stdout, contains('global=1.0.0'));
          expect(stderr, contains('No local installation found'));
        });

        test('launches from self', () {
          _ensureUpToDateTimestamps(fixture!.cliPackageDir);
          if (fixture!.workspaceRootDir != null) {
            _ensureUpToDateTimestamps(fixture!.workspaceRootDir!);
          }

          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.cliPackageDir,
          );
          expect(stdout, contains('local=1.0.0'));
          expect(stdout, contains('global=1.0.0'));
          expect(stderr, contains('isSelf: true'));
          expect(stderr, contains('Launching local installation'));
          if (structure == PackageStructure.workspaceMember) {
            expect(stderr, contains('resolution: workspace'));
          }
        });

        test('launches from consumer', () {
          _ensureUpToDateTimestamps(fixture!.consumerDir);
          if (fixture!.workspaceRootDir != null) {
            _ensureUpToDateTimestamps(fixture!.workspaceRootDir!);
          }

          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.consumerDir,
          );
          expect(stdout, contains('local=1.0.0'));
          expect(stdout, contains('global=1.0.0'));
          expect(stderr, contains('isSelf: false'));
          expect(stderr, contains('Launching local installation'));
        });
      });
    }
  }
}

/// Ensures pubspec.lock and package_config.json are newer than pubspec.yaml
/// so that neither cli_launcher nor dart run triggers pub get.
void _ensureUpToDateTimestamps(String dir) {
  final now = DateTime.now();
  final pubspec = File(p.join(dir, 'pubspec.yaml'));
  final lock = File(p.join(dir, 'pubspec.lock'));
  final packageConfig = File(p.join(dir, '.dart_tool', 'package_config.json'));

  if (pubspec.existsSync()) {
    pubspec.setLastModifiedSync(now.subtract(const Duration(hours: 1)));
  }
  if (lock.existsSync()) {
    lock.setLastModifiedSync(now);
  }
  if (packageConfig.existsSync()) {
    packageConfig.setLastModifiedSync(now);
  }
}

class _Fixture {
  _Fixture._({
    required this.tempDir,
    required this.cliPackageDir,
    required this.consumerDir,
    required this.emptyDir,
    required this.executableName,
    required this.packageName,
    required this.installMethod,
    this.workspaceRootDir,
    this.installedBinDir,
  });

  final String tempDir;
  final String cliPackageDir;
  final String consumerDir;
  final String emptyDir;
  final String? workspaceRootDir;
  final String executableName;
  final String packageName;
  final InstallMethod installMethod;
  final String? installedBinDir;

  static Future<_Fixture> create({
    required InstallMethod installMethod,
    required PackageStructure structure,
    required String packageName,
    required String executableName,
  }) async {
    final tempDir = Directory.systemTemp.createTempSync(
      'cli_launcher_matrix_',
    );

    try {
      switch (structure) {
        case PackageStructure.standalone:
          return await _createStandalone(
            tempDir: tempDir,
            installMethod: installMethod,
            packageName: packageName,
            executableName: executableName,
          );
        case PackageStructure.workspaceMember:
          return await _createWorkspace(
            tempDir: tempDir,
            installMethod: installMethod,
            packageName: packageName,
            executableName: executableName,
          );
      }
    } catch (e) {
      tempDir.deleteSync(recursive: true);
      rethrow;
    }
  }

  static Future<_Fixture> _createStandalone({
    required Directory tempDir,
    required InstallMethod installMethod,
    required String packageName,
    required String executableName,
  }) async {
    final cliDir = p.join(tempDir.path, 'cli_package');
    final consumerDir = p.join(tempDir.path, 'consumer');
    final emptyDir = p.join(tempDir.path, 'empty');

    _createCliPackage(
      dir: cliDir,
      packageName: packageName,
      executableName: executableName,
    );

    _createConsumerPackage(
      dir: consumerDir,
      cliPackageName: packageName,
      cliPackagePath: '../cli_package',
    );

    Directory(emptyDir).createSync();

    // Resolve dependencies.
    _runSync('dart', ['pub', 'get'], workingDirectory: cliDir);
    _runSync('dart', ['pub', 'get'], workingDirectory: consumerDir);

    // Install globally.
    final installedBinDir = _install(
      installMethod: installMethod,
      packageName: packageName,
      cliDir: cliDir,
    );

    return _Fixture._(
      tempDir: tempDir.path,
      cliPackageDir: cliDir,
      consumerDir: consumerDir,
      emptyDir: emptyDir,
      executableName: executableName,
      packageName: packageName,
      installMethod: installMethod,
      installedBinDir: installedBinDir,
    );
  }

  static Future<_Fixture> _createWorkspace({
    required Directory tempDir,
    required InstallMethod installMethod,
    required String packageName,
    required String executableName,
  }) async {
    final workspaceDir = tempDir.path;
    final cliDir = p.join(workspaceDir, 'packages', 'cli_package');
    final consumerDir = p.join(workspaceDir, 'packages', 'consumer');
    final emptyDir = p.join(workspaceDir, 'empty');

    // Create workspace root pubspec.
    File(p.join(workspaceDir, 'pubspec.yaml')).writeAsStringSync('''
name: matrix_workspace
environment:
  sdk: ^3.8.0
workspace:
  - packages/cli_package
  - packages/consumer
''');

    _createCliPackage(
      dir: cliDir,
      packageName: packageName,
      executableName: executableName,
      resolution: 'workspace',
    );

    _createConsumerPackage(
      dir: consumerDir,
      cliPackageName: packageName,
      cliPackagePath: '../cli_package',
      resolution: 'workspace',
    );

    Directory(emptyDir).createSync();

    // Resolve dependencies from workspace root.
    _runSync('dart', ['pub', 'get'], workingDirectory: workspaceDir);

    // Install globally.
    final installedBinDir = _install(
      installMethod: installMethod,
      packageName: packageName,
      cliDir: cliDir,
      workspaceDir: workspaceDir,
    );

    return _Fixture._(
      tempDir: tempDir.path,
      cliPackageDir: cliDir,
      consumerDir: consumerDir,
      emptyDir: emptyDir,
      workspaceRootDir: workspaceDir,
      executableName: executableName,
      packageName: packageName,
      installMethod: installMethod,
      installedBinDir: installedBinDir,
    );
  }

  static void _createCliPackage({
    required String dir,
    required String packageName,
    required String executableName,
    String? resolution,
  }) {
    Directory(p.join(dir, 'bin')).createSync(recursive: true);
    Directory(p.join(dir, 'lib')).createSync(recursive: true);

    final resolutionLine = resolution != null ? 'resolution: $resolution\n' : '';

    File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('''
name: $packageName
version: 1.0.0
${resolutionLine}environment:
  sdk: ^3.8.0
dependencies:
  cli_launcher:
    path: $_cliLauncherRoot
executables:
  $executableName:
''');

    File(p.join(dir, 'bin', '$executableName.dart')).writeAsStringSync('''
import 'package:cli_launcher/cli_launcher.dart';

void main(List<String> args) {
  launchExecutable(
    args,
    LaunchConfig(
      name: ExecutableName('$executableName', package: '$packageName'),
      entrypoint: (args, context) {
        print(
          'local=\${context.localInstallation?.version} '
          'global=\${context.globalInstallation?.version}',
        );
      },
    ),
  );
}
''');
  }

  static void _createConsumerPackage({
    required String dir,
    required String cliPackageName,
    required String cliPackagePath,
    String? resolution,
  }) {
    Directory(dir).createSync(recursive: true);

    final resolutionLine = resolution != null ? 'resolution: $resolution\n' : '';

    File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('''
name: matrix_test_consumer
version: 1.0.0
${resolutionLine}environment:
  sdk: ^3.8.0
dependencies:
  $cliPackageName:
    path: $cliPackagePath
''');
  }

  /// Installs the CLI globally and returns the bin directory for dart install,
  /// or null for path-activated.
  static String? _install({
    required InstallMethod installMethod,
    required String packageName,
    required String cliDir,
    String? workspaceDir,
  }) {
    switch (installMethod) {
      case InstallMethod.pathActivated:
        if (workspaceDir != null) {
          _runSync(
            'dart',
            [
              'pub',
              'global',
              'activate',
              '--source',
              'path',
              p.relative(cliDir, from: workspaceDir),
            ],
            workingDirectory: workspaceDir,
          );
        } else {
          _runSync(
            'dart',
            ['pub', 'global', 'activate', '--source', 'path', '.'],
            workingDirectory: cliDir,
          );
        }
        return null;

      case InstallMethod.dartInstall:
        final result = Process.runSync(
          'dart',
          ['install', cliDir],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
        );
        if (result.exitCode != 0) {
          throw Exception(
            'dart install failed with exit code ${result.exitCode}:\n'
            '${result.stdout}\n${result.stderr}',
          );
        }
        final stdout = result.stdout as String;
        final installedLine = stdout
            .split('\n')
            .where((line) => line.startsWith('Installed:'))
            .firstOrNull;
        if (installedLine == null) {
          throw Exception(
            'Could not find "Installed:" line in dart install output:\n'
            '$stdout',
          );
        }
        final installedPath =
            installedLine.replaceFirst('Installed: ', '').trim();
        return File(installedPath).parent.path;
    }
  }

  ({String stdout, String stderr}) runCli({
    required String workingDirectory,
  }) {
    final env = {...Platform.environment, 'CLI_LAUNCHER_VERBOSE': '1'};
    if (installedBinDir != null) {
      env['PATH'] = '$installedBinDir:${env['PATH']}';
    }

    final result = Process.runSync(
      executableName,
      [],
      runInShell: true,
      workingDirectory: workingDirectory,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
      environment: env,
    );

    if (result.exitCode != 0) {
      throw Exception(
        '$executableName failed with exit code ${result.exitCode}:\n'
        'stdout: ${result.stdout}\nstderr: ${result.stderr}',
      );
    }

    return (stdout: result.stdout as String, stderr: result.stderr as String);
  }

  void dispose() {
    switch (installMethod) {
      case InstallMethod.pathActivated:
        Process.runSync(
          'dart',
          ['pub', 'global', 'deactivate', packageName],
        );
      case InstallMethod.dartInstall:
        Process.runSync('dart', ['uninstall', packageName]);
    }
    Directory(tempDir).deleteSync(recursive: true);
  }

  static void _runSync(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) {
    final result = Process.runSync(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw Exception(
        '$executable ${arguments.join(' ')} failed with exit code '
        '${result.exitCode}:\n${result.stdout}\n${result.stderr}',
      );
    }
  }
}
