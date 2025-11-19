import 'package:cli_launcher/cli_launcher.dart';

void main(List<String> args) {
  launchExecutable(
    args,
    LaunchConfig(
      name: ExecutableName('example', package: 'cli_launcher_example'),
      entrypoint: (args, context) {
        print(
          'Running v1 with '
          'local version ${context.localInstallation?.version} and '
          'global version ${context.globalInstallation?.version}.',
        );

        assert(() {
          print('Assertions are enabled.');
          return true;
        }());
      },
      resolveLocalLaunchConfig:
          args.contains('--local-launch-config') ||
              args.contains('--skip-pub-get')
          ? (context) async {
              return LocalLaunchConfig(
                pubGetArgs: args.contains('--local-launch-config')
                    ? ['--verbose']
                    : null,
                dartRunArgs: args.contains('--local-launch-config')
                    ? ['--enable-asserts']
                    : null,
                skipPubGet: args.contains('--skip-pub-get'),
              );
            }
          : null,
    ),
  );
}
