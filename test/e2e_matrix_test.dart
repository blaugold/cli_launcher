@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Root of the cli_launcher package (this package).
final _cliLauncherRoot = p.normalize(p.absolute(Directory.current.path));

enum InstallMethod { pathActivated, dartInstall }

enum PackageStructure { standalone, workspaceMember, flutterWorkspaceMember }

String _snakeCase(String camelCase) {
  return camelCase.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m[0]!.toLowerCase()}',
  );
}

// Note: The following scenarios cannot easily be tested in e2e:
//
// - `dart pub global activate` from pub cache (requires publishing to pub.dev)
// - Hosted dependency (non-path) in consumer (requires publishing to pub.dev)
// - "Same version → launch global" for consumers (path deps always have
//   isFromPath=true, so local is always launched regardless of version)

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

        // --- No local installation ---

        test('no local installation', () {
          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.emptyDir,
          );
          expect(stdout, contains('local=null'));
          expect(stdout, contains('global=1.0.0'));
          expect(stderr, contains('No local installation found'));
        });

        // --- isSelf: running from the source package ---

        test('launches from self (isSelf)', () {
          fixture!.ensureUpToDateTimestamps();

          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.cliPackageDir,
          );
          expect(stdout, contains('local=1.0.0'));
          expect(stdout, contains('global=1.0.0'));
          expect(stderr, contains('isSelf: true'));
          expect(stderr, contains('Launching local installation'));
          if (structure == PackageStructure.workspaceMember ||
              structure == PackageStructure.flutterWorkspaceMember) {
            expect(stderr, contains('resolution: workspace'));
          }
        });

        // --- Consumer with dependency ---

        test('launches from consumer (dependency)', () {
          fixture!.ensureUpToDateTimestamps();

          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.consumerDir,
          );
          expect(stdout, contains('local=1.0.0'));
          expect(stdout, contains('global=1.0.0'));
          expect(stderr, contains('isSelf: false'));
          expect(stderr, contains('Launching local installation'));
        });

        // --- Consumer with dev_dependency ---

        test('launches from dev_dependency consumer', () {
          fixture!.ensureUpToDateTimestamps();

          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.devDepConsumerDir,
          );
          expect(stdout, contains('local=1.0.0'));
          expect(stdout, contains('global=1.0.0'));
          expect(stderr, contains('isSelf: false'));
          expect(stderr, contains('Launching local installation'));
        });

        // --- Consumer from sub-directory ---

        test('launches from sub-directory of consumer', () {
          fixture!.ensureUpToDateTimestamps();

          final subDir = p.join(fixture!.consumerDir, 'sub');
          Directory(subDir).createSync(recursive: true);

          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: subDir,
          );
          expect(stdout, contains('local=1.0.0'));
          expect(stdout, contains('global=1.0.0'));
          expect(stderr, contains('isSelf: false'));
          expect(stderr, contains('Launching local installation'));
        });

        // --- Dependency freshness: pubspec.lock missing ---
        //
        // For path-activated workspace packages, the workspace lock file is
        // shared between the global and local installations. Deleting it
        // breaks the global CLI itself.

        test(
          'pubspec.lock missing triggers pub get',
          () {
            final lockFileDir =
                fixture!.workspaceRootDir ?? fixture!.consumerDir;
            final lockFile = File(p.join(lockFileDir, 'pubspec.lock'));

            final hadLock = lockFile.existsSync();
            String? lockContents;
            if (hadLock) {
              lockContents = lockFile.readAsStringSync();
              lockFile.deleteSync();
            }

            try {
              final (:stdout, :stderr) = fixture!.runCli(
                workingDirectory: fixture!.consumerDir,
              );
              expect(stdout, contains('local=1.0.0'));
              expect(stdout, contains('global=1.0.0'));
              expect(stderr, contains('does not exist'));
              expect(
                stderr,
                contains('Dependencies are out of date. Running pub get.'),
              );
            } finally {
              if (hadLock) {
                lockFile.writeAsStringSync(lockContents!);
              }
            }
          },
          skip: installMethod == InstallMethod.pathActivated &&
                  structure != PackageStructure.standalone
              ? 'path-activated workspace shares lock file with global CLI'
              : null,
        );

        // --- Dependency freshness: pubspec.lock older than pubspec.yaml ---

        test(
          'pubspec.lock older than pubspec.yaml triggers pub get',
          () {
            final lockFileDir =
                fixture!.workspaceRootDir ?? fixture!.consumerDir;
            final pubspecFile =
                File(p.join(fixture!.consumerDir, 'pubspec.yaml'));
            final lockFile = File(p.join(lockFileDir, 'pubspec.lock'));

            final now = DateTime.now();
            pubspecFile.setLastModifiedSync(now);
            lockFile
                .setLastModifiedSync(now.subtract(const Duration(hours: 1)));

            final (:stdout, :stderr) = fixture!.runCli(
              workingDirectory: fixture!.consumerDir,
            );
            expect(stdout, contains('local=1.0.0'));
            expect(stdout, contains('global=1.0.0'));
            expect(stderr, contains('Dependencies are out of date'));
            expect(
              stderr,
              contains('Dependencies are out of date. Running pub get.'),
            );
          },
          skip: installMethod == InstallMethod.pathActivated &&
                  structure != PackageStructure.standalone
              ? 'path-activated workspace shares lock file with global CLI'
              : null,
        );

        // --- Dependency freshness: up to date ---

        test(
          'up to date pubspec.lock does not trigger pub get',
          () {
            fixture!.ensureUpToDateTimestamps();

            final (:stdout, :stderr) = fixture!.runCli(
              workingDirectory: fixture!.consumerDir,
            );
            expect(stdout, contains('local=1.0.0'));
            expect(
              stderr,
              isNot(contains('Dependencies are out of date. Running pub get.')),
            );
          },
          // On Windows, `dart run` triggers auto-resolution for path
          // dependencies regardless of timestamps.
          skip: Platform.isWindows,
        );

        // --- Different version: v2 consumer depends on v2 CLI ---

        test('different version consumer launches local', () {
          fixture!.ensureUpToDateTimestamps();

          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.v2ConsumerDir,
          );
          // The v2 consumer depends on the v2 CLI package.
          expect(stdout, contains('local=2.0.0'));
          expect(stdout, contains('global=1.0.0'));
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
    required this.devDepConsumerDir,
    required this.v2CliPackageDir,
    required this.v2ConsumerDir,
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
  final String devDepConsumerDir;
  final String v2CliPackageDir;
  final String v2ConsumerDir;
  final String emptyDir;
  final String? workspaceRootDir;
  final String executableName;
  final String packageName;
  final InstallMethod installMethod;
  final String? installedBinDir;

  /// Ensures timestamps are up to date for all relevant directories.
  void ensureUpToDateTimestamps() {
    _ensureUpToDateTimestamps(cliPackageDir);
    _ensureUpToDateTimestamps(consumerDir);
    _ensureUpToDateTimestamps(devDepConsumerDir);
    _ensureUpToDateTimestamps(v2CliPackageDir);
    _ensureUpToDateTimestamps(v2ConsumerDir);
    if (workspaceRootDir != null) {
      _ensureUpToDateTimestamps(workspaceRootDir!);
    }
  }

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
            flutter: false,
          );
        case PackageStructure.flutterWorkspaceMember:
          return await _createWorkspace(
            tempDir: tempDir,
            installMethod: installMethod,
            packageName: packageName,
            executableName: executableName,
            flutter: true,
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
    final devDepConsumerDir = p.join(tempDir.path, 'dev_dep_consumer');
    final v2CliDir = p.join(tempDir.path, 'cli_package_v2');
    final v2ConsumerDir = p.join(tempDir.path, 'consumer_v2');
    final emptyDir = p.join(tempDir.path, 'empty');

    _createCliPackage(
      dir: cliDir,
      packageName: packageName,
      executableName: executableName,
    );

    _createCliPackage(
      dir: v2CliDir,
      packageName: packageName,
      executableName: executableName,
      version: '2.0.0',
    );

    _createConsumerPackage(
      dir: consumerDir,
      cliPackageName: packageName,
      cliPackagePath: '../cli_package',
      devDependency: false,
    );

    _createConsumerPackage(
      dir: devDepConsumerDir,
      cliPackageName: packageName,
      cliPackagePath: '../cli_package',
      devDependency: true,
      consumerName: 'matrix_test_dev_dep_consumer',
    );

    _createConsumerPackage(
      dir: v2ConsumerDir,
      cliPackageName: packageName,
      cliPackagePath: '../cli_package_v2',
      devDependency: false,
      consumerName: 'matrix_test_v2_consumer',
    );

    Directory(emptyDir).createSync();

    // Resolve dependencies.
    _runSync('dart', ['pub', 'get'], workingDirectory: cliDir);
    _runSync('dart', ['pub', 'get'], workingDirectory: v2CliDir);
    _runSync('dart', ['pub', 'get'], workingDirectory: consumerDir);
    _runSync('dart', ['pub', 'get'], workingDirectory: devDepConsumerDir);
    _runSync('dart', ['pub', 'get'], workingDirectory: v2ConsumerDir);

    // Install globally (v1).
    final installedBinDir = _install(
      installMethod: installMethod,
      packageName: packageName,
      cliDir: cliDir,
    );

    return _Fixture._(
      tempDir: tempDir.path,
      cliPackageDir: cliDir,
      consumerDir: consumerDir,
      devDepConsumerDir: devDepConsumerDir,
      v2CliPackageDir: v2CliDir,
      v2ConsumerDir: v2ConsumerDir,
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
    required bool flutter,
  }) async {
    final workspaceDir = p.join(tempDir.path, 'workspace');
    Directory(workspaceDir).createSync();
    final cliDir = p.join(workspaceDir, 'packages', 'cli_package');
    final consumerDir = p.join(workspaceDir, 'packages', 'consumer');
    final devDepConsumerDir =
        p.join(workspaceDir, 'packages', 'dev_dep_consumer');
    final emptyDir = p.join(workspaceDir, 'empty');

    // v2 packages live outside the workspace to avoid name conflicts.
    final v2CliDir = p.join(tempDir.path, 'cli_package_v2');
    final v2ConsumerDir = p.join(tempDir.path, 'consumer_v2');

    // Create workspace root pubspec.
    final workspaceMembers = [
      'packages/cli_package',
      'packages/consumer',
      'packages/dev_dep_consumer',
      if (flutter) 'packages/flutter_package',
    ];

    File(p.join(workspaceDir, 'pubspec.yaml')).writeAsStringSync('''
name: matrix_workspace
environment:
  sdk: ^3.8.0
workspace:
${workspaceMembers.map((m) => '  - $m').join('\n')}
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
      devDependency: false,
    );

    _createConsumerPackage(
      dir: devDepConsumerDir,
      cliPackageName: packageName,
      cliPackagePath: '../cli_package',
      resolution: 'workspace',
      devDependency: true,
      consumerName: 'matrix_test_dev_dep_consumer',
    );

    if (flutter) {
      _createFlutterPackage(
        dir: p.join(workspaceDir, 'packages', 'flutter_package'),
      );
    }

    Directory(emptyDir).createSync();

    // Resolve workspace dependencies.
    final pubCommand = flutter ? 'flutter' : 'dart';
    _runSync(pubCommand, ['pub', 'get'], workingDirectory: workspaceDir);

    // Create v2 packages outside the workspace (standalone).
    _createCliPackage(
      dir: v2CliDir,
      packageName: packageName,
      executableName: executableName,
      version: '2.0.0',
    );

    _createConsumerPackage(
      dir: v2ConsumerDir,
      cliPackageName: packageName,
      cliPackagePath: '../cli_package_v2',
      devDependency: false,
      consumerName: 'matrix_test_v2_consumer',
    );

    _runSync('dart', ['pub', 'get'], workingDirectory: v2CliDir);
    _runSync('dart', ['pub', 'get'], workingDirectory: v2ConsumerDir);

    // Install globally (v1).
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
      devDepConsumerDir: devDepConsumerDir,
      v2CliPackageDir: v2CliDir,
      v2ConsumerDir: v2ConsumerDir,
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
    String version = '1.0.0',
    String? resolution,
  }) {
    Directory(p.join(dir, 'bin')).createSync(recursive: true);
    Directory(p.join(dir, 'lib')).createSync(recursive: true);

    final resolutionLine =
        resolution != null ? 'resolution: $resolution\n' : '';

    File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('''
name: $packageName
version: $version
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
    required bool devDependency,
    String? resolution,
    String consumerName = 'matrix_test_consumer',
  }) {
    Directory(dir).createSync(recursive: true);

    final resolutionLine =
        resolution != null ? 'resolution: $resolution\n' : '';

    final depsSection = devDependency
        ? '''
dev_dependencies:
  $cliPackageName:
    path: $cliPackagePath'''
        : '''
dependencies:
  $cliPackageName:
    path: $cliPackagePath''';

    File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('''
name: $consumerName
version: 1.0.0
${resolutionLine}environment:
  sdk: ^3.8.0
$depsSection
''');
  }

  static void _createFlutterPackage({required String dir}) {
    Directory(p.join(dir, 'lib')).createSync(recursive: true);

    File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('''
name: matrix_flutter_package
version: 1.0.0
resolution: workspace
environment:
  sdk: ^3.8.0
dependencies:
  flutter:
    sdk: flutter
''');

    File(p.join(dir, 'lib', 'main.dart')).writeAsStringSync('''
void main() {}
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
