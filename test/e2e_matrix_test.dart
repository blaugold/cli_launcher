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
      final packageName =
          'cli_launcher_matrix_'
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

        // --- Relaunch uses the Flutter tool for Flutter workspaces ---
        //
        // Regression test: launching a local installation implicitly resolves
        // dependencies (`dart run` runs an implicit `dart pub get`). In a
        // Flutter workspace a plain `dart pub get` fails with "requires the
        // Flutter SDK", so the relaunch must go through the Flutter tool
        // instead. This broke consumers such as supabase-flutter whose
        // Dart-only CI activated a newer global melos than the workspace
        // pinned, triggering a relaunch of the pinned version.
        test('relaunch uses the correct SDK tool', () {
          fixture!.ensureUpToDateTimestamps();

          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.consumerDir,
          );
          expect(stderr, contains('Launching local installation'));
          if (structure == PackageStructure.flutterWorkspaceMember) {
            expect(
              stderr,
              contains('Launching local installation via "flutter pub run"'),
            );
          } else {
            expect(
              stderr,
              contains('Launching local installation via "dart run"'),
            );
          }
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

        // --- Running from workspace root ---

        test(
          'launches from workspace root with cli as dev_dependency',
          () {
            if (fixture!.workspaceRootDir == null) {
              return;
            }
            fixture!.ensureUpToDateTimestamps();

            final (:stdout, :stderr) = fixture!.runCli(
              workingDirectory: fixture!.workspaceRootDir!,
            );
            expect(stdout, contains('local=1.0.0'));
            expect(stdout, contains('global=1.0.0'));
            expect(stderr, contains('Resolved workspace member'));
            expect(stderr, contains('Launching local installation'));
          },
          skip: structure == PackageStructure.standalone
              ? 'standalone has no workspace root'
              : null,
        );

        // --- Consumer from sub-directory ---

        test('launches from sub-directory of consumer', () {
          fixture!.ensureUpToDateTimestamps();

          final subDir = p.join(fixture!.consumerDir, 'sub');
          Directory(subDir).createSync(recursive: true);

          final (:stdout, :stderr) = fixture!.runCli(workingDirectory: subDir);
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
          skip:
              installMethod == InstallMethod.pathActivated &&
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
            final pubspecFile = File(
              p.join(fixture!.consumerDir, 'pubspec.yaml'),
            );
            final lockFile = File(p.join(lockFileDir, 'pubspec.lock'));

            final now = DateTime.now();
            pubspecFile.setLastModifiedSync(now);
            lockFile.setLastModifiedSync(
              now.subtract(const Duration(hours: 1)),
            );

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
          skip:
              installMethod == InstallMethod.pathActivated &&
                  structure != PackageStructure.standalone
              ? 'path-activated workspace shares lock file with global CLI'
              : null,
        );

        // --- Dependency freshness: up to date ---

        test('up to date pubspec.lock does not trigger pub get', () {
          fixture!.ensureUpToDateTimestamps();

          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.consumerDir,
          );
          expect(stdout, contains('local=1.0.0'));
          expect(
            stderr,
            isNot(contains('Dependencies are out of date. Running pub get.')),
          );
        });

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

        // --- resolveLocalLaunchConfig ---

        test('resolveLocalLaunchConfig passes dartRunArgs', () {
          fixture!.ensureUpToDateTimestamps();

          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.consumerDir,
            arguments: ['--local-launch-config'],
          );
          expect(stdout, contains('local=1.0.0'));
          // --enable-asserts is passed via dartRunArgs by resolveLocalLaunchConfig.
          expect(stdout, contains('Assertions are enabled.'));
        });

        // --- resolveLocalLaunchConfig: sdkPath ---
        //
        // The SDK path is used for the tools that resolve dependencies and
        // relaunch the local installation, instead of `dart`/`flutter` from
        // the PATH. An SDK path that does not exist proves that the tools are
        // taken from it, since the launch then fails with the tool path.

        final sdkTool = structure == PackageStructure.flutterWorkspaceMember
            ? 'flutter'
            : 'dart';

        test('resolveLocalLaunchConfig uses sdkPath to launch', () {
          fixture!.ensureUpToDateTimestamps();

          final sdkPath = _findSdkRoot(
            flutter: structure == PackageStructure.flutterWorkspaceMember,
          );
          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.consumerDir,
            arguments: ['--sdk-path=$sdkPath'],
          );
          expect(stdout, contains('local=1.0.0'));
          expect(stderr, contains('Launching local installation'));
          expect(stderr, contains('Using SDK at $sdkPath.'));
        });

        test('resolveLocalLaunchConfig resolves a relative sdkPath', () {
          fixture!.ensureUpToDateTimestamps();

          final sdkPath = _findSdkRoot(
            flutter: structure == PackageStructure.flutterWorkspaceMember,
          );
          final relativeSdkPath = p.relative(
            sdkPath,
            from: Directory(fixture!.consumerDir).resolveSymbolicLinksSync(),
          );
          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.consumerDir,
            arguments: ['--sdk-path=$relativeSdkPath', '--print-path'],
          );
          expect(stdout, contains('local=1.0.0'));
          expect(stdout, contains('PATH=${p.join(sdkPath, 'bin')}'));
          expect(stderr, contains('Using SDK at $sdkPath.'));
        });

        test(
          'resolveLocalLaunchConfig uses a relative sdkPath for pub get',
          () {
            final lockFileDir =
                fixture!.workspaceRootDir ?? fixture!.consumerDir;
            final pubspecFile = File(
              p.join(fixture!.consumerDir, 'pubspec.yaml'),
            );
            final lockFile = File(p.join(lockFileDir, 'pubspec.lock'));

            final now = DateTime.now();
            pubspecFile.setLastModifiedSync(now);
            lockFile.setLastModifiedSync(
              now.subtract(const Duration(hours: 1)),
            );

            final sdkPath = _findSdkRoot(
              flutter: structure == PackageStructure.flutterWorkspaceMember,
            );
            final relativeSdkPath = p.relative(
              sdkPath,
              from: Directory(fixture!.consumerDir).resolveSymbolicLinksSync(),
            );
            final (:stdout, :stderr) = fixture!.runCli(
              workingDirectory: fixture!.consumerDir,
              arguments: ['--sdk-path=$relativeSdkPath', '--print-path'],
            );
            expect(stdout, contains('local=1.0.0'));
            expect(stdout, contains('PATH=${p.join(sdkPath, 'bin')}'));
            expect(
              stderr,
              contains('Dependencies are out of date. Running pub get.'),
            );
            expect(stderr, contains('Using SDK at $sdkPath.'));
          },
          skip:
              installMethod == InstallMethod.pathActivated &&
                  structure != PackageStructure.standalone
              ? 'path-activated workspace shares lock file with global CLI'
              : null,
        );

        test('resolveLocalLaunchConfig launches with tools from sdkPath', () {
          fixture!.ensureUpToDateTimestamps();

          final sdkPath = p.join(fixture!.tempDir, 'missing_sdk');
          expect(
            () => fixture!.runCli(
              workingDirectory: fixture!.consumerDir,
              arguments: ['--sdk-path=$sdkPath'],
            ),
            throwsA(
              isA<Exception>().having(
                (e) => e.toString(),
                'message',
                allOf(
                  contains('Launching local installation'),
                  contains(
                    'Could not find the $sdkTool tool at '
                    '${p.join(sdkPath, 'bin', sdkTool)}.',
                  ),
                ),
              ),
            ),
          );
        });

        test(
          'resolveLocalLaunchConfig runs pub get with tools from sdkPath',
          () {
            final lockFileDir =
                fixture!.workspaceRootDir ?? fixture!.consumerDir;
            final pubspecFile = File(
              p.join(fixture!.consumerDir, 'pubspec.yaml'),
            );
            final lockFile = File(p.join(lockFileDir, 'pubspec.lock'));

            final now = DateTime.now();
            pubspecFile.setLastModifiedSync(now);
            lockFile.setLastModifiedSync(
              now.subtract(const Duration(hours: 1)),
            );

            final sdkPath = p.join(fixture!.tempDir, 'missing_sdk');
            expect(
              () => fixture!.runCli(
                workingDirectory: fixture!.consumerDir,
                arguments: ['--sdk-path=$sdkPath'],
              ),
              throwsA(
                isA<Exception>().having(
                  (e) => e.toString(),
                  'message',
                  allOf(
                    contains('Dependencies are out of date. Running pub get.'),
                    contains(
                      'Could not find the $sdkTool tool at '
                      '${p.join(sdkPath, 'bin', sdkTool)}.',
                    ),
                  ),
                ),
              ),
            );
          },
          skip:
              installMethod == InstallMethod.pathActivated &&
                  structure != PackageStructure.standalone
              ? 'path-activated workspace shares lock file with global CLI'
              : null,
        );

        // --- runPubGet: false ---

        test(
          'out of date dependencies do not trigger pub get',
          () {
            final lockFileDir =
                fixture!.workspaceRootDir ?? fixture!.consumerDir;
            final pubspecFile = File(
              p.join(fixture!.consumerDir, 'pubspec.yaml'),
            );
            final lockFile = File(p.join(lockFileDir, 'pubspec.lock'));

            final now = DateTime.now();
            pubspecFile.setLastModifiedSync(now);
            lockFile.setLastModifiedSync(
              now.subtract(const Duration(hours: 1)),
            );

            final (:stdout, :stderr) = fixture!.runCli(
              workingDirectory: fixture!.consumerDir,
              arguments: ['--no-pub'],
            );
            expect(stdout, contains('local=1.0.0'));
            expect(
              stderr,
              contains('Dependencies are out of date, but pub get is disabled'),
            );
            expect(stderr, isNot(contains('Running pub get')));
          },
          skip:
              installMethod == InstallMethod.pathActivated &&
                  structure != PackageStructure.standalone
              ? 'path-activated workspace shares lock file with global CLI'
              : null,
        );

        // The local installation is launched without `dart run`, which would
        // resolve dependencies implicitly, leaving the lock file untouched
        // even though the pubspec asks for a dependency that is not in it.
        test(
          'launching does not resolve dependencies implicitly',
          () {
            final lockFileDir =
                fixture!.workspaceRootDir ?? fixture!.consumerDir;
            final pubspecFile = File(
              p.join(fixture!.consumerDir, 'pubspec.yaml'),
            );
            final lockFile = File(p.join(lockFileDir, 'pubspec.lock'));

            final pubspecContents = pubspecFile.readAsStringSync();
            final lockContents = lockFile.readAsStringSync();

            try {
              pubspecFile.writeAsStringSync(
                pubspecContents.replaceFirst(
                  RegExp('^dependencies:', multiLine: true),
                  'dependencies:\n  collection: ^1.19.0',
                ),
              );

              final (:stdout, :stderr) = fixture!.runCli(
                workingDirectory: fixture!.consumerDir,
                arguments: ['--no-pub'],
              );
              expect(stdout, contains('local=1.0.0'));
              expect(
                stderr,
                contains('Launching local installation via "dart"'),
              );
              expect(lockFile.readAsStringSync(), lockContents);
            } finally {
              pubspecFile.writeAsStringSync(pubspecContents);
              lockFile.writeAsStringSync(lockContents);
            }
          },
          skip:
              installMethod == InstallMethod.pathActivated &&
                  structure != PackageStructure.standalone
              ? 'path-activated workspace shares lock file with global CLI'
              : null,
        );

        test('relative sdkPath is used when pub get is disabled', () {
          fixture!.ensureUpToDateTimestamps();

          final sdkPath = _findSdkRoot(flutter: false);
          final relativeSdkPath = p.relative(
            sdkPath,
            from: Directory(fixture!.consumerDir).resolveSymbolicLinksSync(),
          );
          final (:stdout, :stderr) = fixture!.runCli(
            workingDirectory: fixture!.consumerDir,
            arguments: [
              '--sdk-path=$relativeSdkPath',
              '--no-pub',
              '--print-path',
            ],
          );

          expect(stdout, contains('local=1.0.0'));
          expect(stdout, contains('PATH=${p.join(sdkPath, 'bin')}'));
          expect(stderr, contains('Launching local installation via "dart"'));
          expect(stderr, contains('Using SDK at $sdkPath.'));
        });
      });
    }
  }

  // Tests activating a workspace member CLI package directly from the
  // workspace root, where the workspace root has the CLI as a dev_dependency.
  group('workspace member activated from workspace root', () {
    _WorkspaceRootActivationFixture? fixture;

    setUpAll(() async {
      fixture = await _WorkspaceRootActivationFixture.create();
    });

    tearDownAll(() {
      fixture?.dispose();
    });

    test('launches correctly from empty directory', () {
      final (:stdout, :stderr) = fixture!.runCli(
        workingDirectory: fixture!.emptyDir,
      );
      expect(stdout, contains('local=null'));
      expect(stdout, contains('global=1.0.0'));
      expect(stderr, contains('No local installation found'));
    });

    test('launches correctly from workspace root', () {
      fixture!.ensureUpToDateTimestamps();

      final (:stdout, :stderr) = fixture!.runCli(
        workingDirectory: fixture!.workspaceRootDir,
      );
      expect(stdout, contains('local=1.0.0'));
      expect(stdout, contains('global=1.0.0'));
      expect(stderr, contains('Resolved workspace member'));
      expect(stderr, contains('Launching local installation'));
    });
  });
}

/// Fixture that activates a workspace member CLI package directly from the
/// workspace root, where the root has the CLI as a dev_dependency.
///
/// This reproduces the pattern used in the melos repo:
///
/// - Workspace root: `melos_workspace` with `melos` as dev_dependency
/// - CLI member: `melos` at `packages/melos`
/// - Activated via `dart pub global activate --source=path packages/melos`
class _WorkspaceRootActivationFixture {
  _WorkspaceRootActivationFixture._({
    required this.tempDir,
    required this.workspaceRootDir,
    required this.cliPackageDir,
    required this.emptyDir,
    required this.executableName,
    required this.packageName,
  });

  final String tempDir;
  final String workspaceRootDir;
  final String cliPackageDir;
  final String emptyDir;
  final String executableName;
  final String packageName;

  void ensureUpToDateTimestamps() {
    _ensureUpToDateTimestamps(workspaceRootDir);
    _ensureUpToDateTimestamps(cliPackageDir);
  }

  static Future<_WorkspaceRootActivationFixture> create() async {
    const packageName = 'ws_member_cli';
    const executableName = 'ws_member_cli_exec';

    final tempDir = Directory.systemTemp.createTempSync(
      'cli_launcher_ws_member_',
    );

    try {
      final workspaceDir = p.join(tempDir.path, 'workspace');
      final cliDir = p.join(workspaceDir, 'packages', 'cli_package');
      final emptyDir = p.join(tempDir.path, 'empty');

      // Create workspace root with the CLI package as a dev_dependency.
      Directory(workspaceDir).createSync(recursive: true);
      File(p.join(workspaceDir, 'pubspec.yaml')).writeAsStringSync('''
name: ws_member_workspace
environment:
  sdk: ^3.8.0
workspace:
  - packages/cli_package
dev_dependencies:
  $packageName:
    path: packages/cli_package
''');

      // Create the CLI member package.
      Directory(p.join(cliDir, 'bin')).createSync(recursive: true);
      Directory(p.join(cliDir, 'lib')).createSync(recursive: true);

      File(p.join(cliDir, 'pubspec.yaml')).writeAsStringSync('''
name: $packageName
version: 1.0.0
resolution: workspace
environment:
  sdk: ^3.8.0
dependencies:
  cli_launcher:
    path: $_cliLauncherRoot
executables:
  $executableName:
''');

      // Create the CLI entrypoint in the member package.
      File(p.join(cliDir, 'bin', '$executableName.dart')).writeAsStringSync('''
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

      Directory(emptyDir).createSync();

      // Resolve workspace dependencies.
      _Fixture._runSync('dart', ['pub', 'get'], workingDirectory: workspaceDir);

      // Activate the CLI member package directly from the workspace root.
      // This mirrors how melos does:
      //   dart pub global activate --source="path" packages/melos --executable="melos"
      _Fixture._runSync('dart', [
        'pub',
        'global',
        'activate',
        '--source',
        'path',
        'packages/cli_package',
        '--executable=$executableName',
      ], workingDirectory: workspaceDir);

      return _WorkspaceRootActivationFixture._(
        tempDir: tempDir.path,
        workspaceRootDir: workspaceDir,
        cliPackageDir: cliDir,
        emptyDir: emptyDir,
        executableName: executableName,
        packageName: packageName,
      );
    } catch (e) {
      tempDir.deleteSync(recursive: true);
      rethrow;
    }
  }

  ({String stdout, String stderr}) runCli({required String workingDirectory}) {
    final env = {...Platform.environment, 'CLI_LAUNCHER_VERBOSE': '1'};

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
    Process.runSync('dart', [
      'pub',
      'global',
      'deactivate',
      packageName,
    ], runInShell: Platform.isWindows);
    Directory(tempDir).deleteSync(recursive: true);
  }
}

/// Finds the root directory of the SDK that provides the `dart` tool used to
/// run the tests, or the `flutter` tool on the PATH when [flutter] is true.
String _findSdkRoot({required bool flutter}) {
  if (!flutter) {
    return p.dirname(p.dirname(Platform.resolvedExecutable));
  }
  final result = Process.runSync(
    Platform.isWindows ? 'where' : 'which',
    ['flutter'],
    runInShell: Platform.isWindows,
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw Exception('Could not find the flutter tool on the PATH.');
  }
  final flutterTool = const LineSplitter()
      .convert(result.stdout as String)
      .first
      .trim();
  return p.dirname(p.dirname(File(flutterTool).resolveSymbolicLinksSync()));
}

/// Ensures pubspec.lock and package_config.json are newer than pubspec.yaml so
/// that neither cli_launcher nor dart run triggers pub get.
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
    final tempDir = Directory.systemTemp.createTempSync('cli_launcher_matrix_');

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
    final devDepConsumerDir = p.join(
      workspaceDir,
      'packages',
      'dev_dep_consumer',
    );
    // Empty dir must be outside the workspace so that the "no local
    // installation" test doesn't find the workspace root's dev_dependency.
    final emptyDir = p.join(tempDir.path, 'empty');

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

    // The workspace root lists the CLI package as a dev_dependency (like the
    // melos repo does for itself) to test that running from the workspace root
    // correctly resolves the workspace member as the package root.
    File(p.join(workspaceDir, 'pubspec.yaml')).writeAsStringSync('''
name: matrix_workspace
environment:
  sdk: ^3.8.0
workspace:
${workspaceMembers.map((m) => '  - $m').join('\n')}
dev_dependencies:
  $packageName:
    path: packages/cli_package
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

    final resolutionLine = resolution != null
        ? 'resolution: $resolution\n'
        : '';

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
import 'dart:io';

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

        if (args.contains('--print-path')) {
          final pathKey = Platform.environment.keys.firstWhere(
            (key) => key.toUpperCase() == 'PATH',
            orElse: () => 'PATH',
          );
          print('PATH=\${Platform.environment[pathKey]}');
        }

        assert(() {
          print('Assertions are enabled.');
          return true;
        }());
      },
      resolveLocalLaunchConfig:
          args.contains('--local-launch-config') ||
              args.contains('--no-pub') ||
              args.any((arg) => arg.startsWith('--sdk-path='))
          ? (context) async {
              final sdkPathArg = args
                  .where((arg) => arg.startsWith('--sdk-path='))
                  .firstOrNull;
              return LocalLaunchConfig(
                dartRunArgs: args.contains('--local-launch-config')
                    ? ['--enable-asserts']
                    : null,
                sdkPath: sdkPathArg?.substring('--sdk-path='.length),
                runPubGet: !args.contains('--no-pub'),
              );
            }
          : null,
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

    final resolutionLine = resolution != null
        ? 'resolution: $resolution\n'
        : '';

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
          _runSync('dart', [
            'pub',
            'global',
            'activate',
            '--source',
            'path',
            p.relative(cliDir, from: workspaceDir),
          ], workingDirectory: workspaceDir);
        } else {
          _runSync('dart', [
            'pub',
            'global',
            'activate',
            '--source',
            'path',
            '.',
          ], workingDirectory: cliDir);
        }
        return null;

      case InstallMethod.dartInstall:
        final result = Process.runSync(
          'dart',
          ['install', cliDir],
          stdoutEncoding: utf8,
          stderrEncoding: utf8,
          runInShell: Platform.isWindows,
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
        final installedPath = installedLine
            .replaceFirst('Installed: ', '')
            .trim();
        return File(installedPath).parent.path;
    }
  }

  ({String stdout, String stderr}) runCli({
    required String workingDirectory,
    List<String> arguments = const [],
  }) {
    final env = {...Platform.environment, 'CLI_LAUNCHER_VERBOSE': '1'};
    if (installedBinDir != null) {
      final pathSeparator = Platform.isWindows ? ';' : ':';
      env['PATH'] = '$installedBinDir$pathSeparator${env['PATH']}';
    }

    final result = Process.runSync(
      executableName,
      arguments,
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
        Process.runSync('dart', [
          'pub',
          'global',
          'deactivate',
          packageName,
        ], runInShell: Platform.isWindows);
      case InstallMethod.dartInstall:
        Process.runSync('dart', [
          'uninstall',
          packageName,
        ], runInShell: Platform.isWindows);
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
      // Necessary so that `dart.bat`/`flutter.bat` wrappers can be found on
      // Windows.
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      throw Exception(
        '$executable ${arguments.join(' ')} failed with exit code '
        '${result.exitCode}:\n${result.stdout}\n${result.stderr}',
      );
    }
  }
}
