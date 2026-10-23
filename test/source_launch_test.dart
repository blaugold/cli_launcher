@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

const _package = 'cli_launcher_source_test';
const _command = 'source_test';
final _launcherRoot = Directory.current.resolveSymbolicLinksSync();

enum _Source { hosted, path, git }

void main() {
  late _Fixture fixture;
  setUpAll(() async => fixture = await _Fixture.create());
  tearDownAll(() async => fixture.dispose());

  for (final source in _Source.values) {
    for (final workspace in [false, true]) {
      test('dart run ${source.name}, workspace: $workspace', () async {
        final consumer = await fixture.consumer(source, workspace: workspace);
        final result = await fixture.run([
          'run',
          '$_package:$_command',
          'argument with spaces',
        ], cwd: consumer);
        final data = _output(result);
        expect(data['version'], '1.0.0');
        expect(data['globalVersion'], '1.0.0');
        expect(data['localVersion'], '1.0.0');
        expect(data['globalFromPath'], source == _Source.path);
        expect(data['localFromPath'], source == _Source.path);
        expect(
          data['directory'],
          Directory(consumer).resolveSymbolicLinksSync(),
        );
        expect(data['args'], ['argument with spaces']);
        expect(
          result.stderr.toString().contains('Launching local installation via'),
          source == _Source.path,
        );

        // Mirrors Melos exec scripts: the running CLI starts another dart run
        // from a member/subdirectory, using the same workspace resolution.
        final nestedDir = p.join(consumer, 'nested');
        Directory(nestedDir).createSync();
        final nested = await fixture.run([
          'run',
          '$_package:$_command',
          '--nested',
        ], cwd: nestedDir);
        final nestedData = _output(nested);
        expect(nestedData['args'], ['nested argument']);
        expect(nestedData['version'], '1.0.0');
        expect(nestedData['globalFromPath'], source == _Source.path);
        expect(
          nestedData['directory'],
          Directory(nestedDir).resolveSymbolicLinksSync(),
        );
      });
    }

    test('global ${source.name} and forwarding to workspace', () async {
      await fixture.activate(source);
      try {
        final global = _output(await fixture.global(cwd: fixture.empty));
        expect(global['version'], '1.0.0');
        expect(global['globalVersion'], '1.0.0');
        expect(global['globalFromPath'], source == _Source.path);
        expect(global['localVersion'], isNull);

        final sameVersionConsumer = await fixture.consumer(
          source,
          workspace: true,
        );
        final sameVersionResult = await fixture.global(
          cwd: sameVersionConsumer,
        );
        expect(_output(sameVersionResult)['localVersion'], '1.0.0');
        expect(
          sameVersionResult.stderr.toString().contains(
            'Launching local installation via',
          ),
          source == _Source.path,
        );

        final consumer = await fixture.consumer(
          source,
          workspace: true,
          version: '2.0.0',
        );
        final result = await fixture.global(
          cwd: consumer,
          args: ['forwarded argument'],
        );
        final local = _output(result);
        expect(local['version'], '2.0.0');
        expect(local['globalVersion'], '1.0.0');
        expect(local['localVersion'], '2.0.0');
        expect(local['globalFromPath'], source == _Source.path);
        expect(local['localFromPath'], source == _Source.path);
        expect(
          local['directory'],
          Directory(consumer).resolveSymbolicLinksSync(),
        );
        expect(local['args'], ['forwarded argument']);
        expect(
          result.stderr,
          contains('Launching local installation via "dart run"'),
        );
      } finally {
        await fixture.run(['pub', 'global', 'deactivate', _package]);
      }
    });
  }

  test('source package entry point and dartdev snapshot', () async {
    final source = fixture.sources['1.0.0']!;
    await fixture.run(['pub', 'get'], cwd: source);
    final direct = _output(
      await fixture.run(['run', 'bin/$_command.dart'], cwd: source),
    );
    expect(direct['version'], '1.0.0');
    expect(direct['localVersion'], '1.0.0');

    final snapshot = p.join(
      source,
      '.dart_tool',
      'dartdev',
      'bin',
      _package,
      '$_command.dill',
    );
    Directory(p.dirname(snapshot)).createSync(recursive: true);
    await fixture.run([
      'compile',
      'kernel',
      'bin/$_command.dart',
      '-o',
      snapshot,
    ], cwd: source);
    final cached = _output(await fixture.run([snapshot], cwd: fixture.empty));
    expect(cached['globalVersion'], '1.0.0');
    expect(cached['globalFromPath'], isTrue);
    expect(cached['localVersion'], isNull);
  });
}

Map<String, Object?> _output(ProcessResult result) {
  final line = const LineSplitter()
      .convert(result.stdout as String)
      .lastWhere(
        (line) => line.startsWith('RESULT:'),
        orElse: () =>
            throw StateError('No result: ${result.stdout}\n${result.stderr}'),
      );
  return (jsonDecode(line.substring('RESULT:'.length)) as Map).cast();
}

/// A real pub server and local Git repositories let us test source semantics
/// without publishing fixture packages or relying on a particular public CLI.
class _Fixture {
  _Fixture(this.root, this.server);

  final Directory root;
  final HttpServer server;
  final sources = <String, String>{};
  final archives = <String, File>{};
  final pubspecs = <String, Map<String, Object?>>{};
  int _consumerId = 0;

  String get url => 'http://127.0.0.1:${server.port}';
  String get empty => p.join(root.path, 'empty');
  String get cache =>
      Platform.environment['PUB_CACHE'] ?? p.join(root.path, 'cache');
  Map<String, String> get environment => {
    'PUB_CACHE': cache,
    'CLI_LAUNCHER_VERBOSE': '1',
    // Permit the fixture server when tests run behind a proxy.
    'NO_PROXY': 'localhost,127.0.0.1',
    'no_proxy': 'localhost,127.0.0.1',
  };

  static Future<_Fixture> create() async {
    final root = Directory.systemTemp.createTempSync('cli_launcher_sources_');
    final fixture = _Fixture(
      root,
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture.server.listen(fixture._serve);
    try {
      Directory(fixture.empty).createSync();
      final launcherVersion =
          (loadYaml(
                    File(
                      p.join(_launcherRoot, 'pubspec.yaml'),
                    ).readAsStringSync(),
                  )
                  as YamlMap)['version']!
              as String;
      await fixture._archive('cli_launcher', launcherVersion, _launcherRoot, [
        'pubspec.yaml',
        'lib',
      ]);
      for (final version in ['1.0.0', '2.0.0']) {
        final dir = p.join(root.path, 'source-$version');
        fixture.sources[version] = dir;
        Directory(p.join(dir, 'bin')).createSync(recursive: true);
        File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('''
name: $_package
version: $version
environment:
  sdk: ^3.8.0
dependencies:
  cli_launcher:
    hosted: ${fixture.url}
    version: $launcherVersion
executables:
  $_command:
''');
        File(p.join(dir, 'bin', '$_command.dart')).writeAsStringSync('''
import 'dart:convert';
import 'dart:io';
import 'package:cli_launcher/cli_launcher.dart';

Future<void> main(List<String> args) async {
  await launchExecutable(args, LaunchConfig(
    name: ExecutableName('$_command', package: '$_package'),
    entrypoint: (args, context) async {
      if (args.contains('--nested')) {
        final child = await Process.run(Platform.resolvedExecutable,
          ['run', '$_package:$_command', 'nested argument']);
        stdout.write(child.stdout);
        stderr.write(child.stderr);
        exitCode = child.exitCode;
        return;
      }
      print('RESULT:\${jsonEncode({
        'version': '$version',
        'globalVersion': context.globalInstallation?.version,
        'localVersion': context.localInstallation?.version,
        'globalFromPath': context.globalInstallation?.isFromPath,
        'localFromPath': context.localInstallation?.isFromPath,
        'directory': Directory.current.resolveSymbolicLinksSync(),
        'args': args,
      })}');
    },
  ));
}
''');
        await fixture._archive(_package, version, dir, ['pubspec.yaml', 'bin']);
        await fixture.command('git', ['init', '--quiet'], cwd: dir);
        await fixture.command('git', ['add', 'pubspec.yaml', 'bin'], cwd: dir);
        await fixture.command('git', [
          '-c',
          'user.name=Test',
          '-c',
          'user.email=test@example.invalid',
          '-c',
          'commit.gpgsign=false',
          'commit',
          '--quiet',
          '-m',
          'fixture',
        ], cwd: dir);
      }
      return fixture;
    } catch (_) {
      await fixture.dispose();
      rethrow;
    }
  }

  Future<void> _archive(
    String name,
    String version,
    String source,
    List<String> files,
  ) async {
    final key = '$name-$version';
    final archive = File(p.join(root.path, '$key.tar.gz'));
    await command('tar', ['-czf', archive.path, '-C', source, ...files]);
    archives[key] = archive;
    pubspecs[key] =
        (loadYaml(File(p.join(source, 'pubspec.yaml')).readAsStringSync())
                as YamlMap)
            .cast();
  }

  Future<void> _serve(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    if (segments.length == 3 &&
        segments[0] == 'api' &&
        segments[1] == 'packages') {
      final versions = pubspecs.entries
          .where((entry) => entry.value['name'] == segments[2])
          .map(
            (entry) => {
              'version': entry.value['version'],
              'pubspec': entry.value,
              'archive_url': '$url/archives/${entry.key}.tar.gz',
            },
          )
          .toList();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'name': segments[2],
          'latest': versions.last,
          'versions': versions,
        }),
      );
    } else if (segments.length == 2 && segments[0] == 'archives') {
      final archive = archives[segments[1].replaceFirst('.tar.gz', '')];
      if (archive == null) {
        request.response.statusCode = 404;
      } else {
        await request.response.addStream(archive.openRead());
      }
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  }

  Future<String> consumer(
    _Source source, {
    required bool workspace,
    String version = '1.0.0',
  }) async {
    final dir = p.join(root.path, 'consumer-${_consumerId++}');
    Directory(dir).createSync();
    final dependency = switch (source) {
      _Source.hosted => 'hosted: $url\n    version: $version',
      _Source.path => 'path: ${sources[version]}',
      _Source.git => 'git: ${Directory(sources[version]!).uri}',
    };
    File(p.join(dir, 'pubspec.yaml')).writeAsStringSync('''
name: source_test_consumer
environment:
  sdk: ^3.8.0
${workspace ? 'workspace:\n  - member\n' : ''}dev_dependencies:
  $_package:
    $dependency
''');
    if (workspace) {
      Directory(p.join(dir, 'member')).createSync();
      File(p.join(dir, 'member', 'pubspec.yaml')).writeAsStringSync('''
name: source_test_member
resolution: workspace
environment:
  sdk: ^3.8.0
''');
    }
    await run(['pub', 'get'], cwd: dir);
    return workspace ? p.join(dir, 'member') : dir;
  }

  Future<void> activate(_Source source) => run([
    'pub',
    'global',
    'activate',
    ...switch (source) {
      _Source.hosted => ['--hosted-url', url, _package, '1.0.0'],
      _Source.path => ['--source', 'path', sources['1.0.0']!],
      _Source.git => [
        '--source',
        'git',
        Directory(sources['1.0.0']!).uri.toString(),
      ],
    },
  ]).then((_) {});

  Future<ProcessResult> global({
    required String cwd,
    List<String> args = const [],
  }) => command(
    p.join(cache, 'bin', '$_command${Platform.isWindows ? '.bat' : ''}'),
    args,
    cwd: cwd,
  );

  Future<ProcessResult> run(List<String> args, {String? cwd}) =>
      command(Platform.resolvedExecutable, args, cwd: cwd);

  Future<ProcessResult> command(
    String executable,
    List<String> args, {
    String? cwd,
  }) async {
    final result = await Process.run(
      executable,
      args,
      workingDirectory: cwd ?? root.path,
      environment: environment,
      runInShell: Platform.isWindows,
    );
    if (result.exitCode != 0) {
      throw StateError(
        '$executable ${args.join(' ')} (${result.exitCode})\n${result.stdout}\n${result.stderr}',
      );
    }
    return result;
  }

  Future<void> dispose() async {
    await server.close(force: true);
    root.deleteSync(recursive: true);
  }
}
