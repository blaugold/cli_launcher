import 'package:cli_launcher/cli_launcher.dart';

void main(List<String> args) {
  launchExecutable(
    args,
    LaunchConfig(
      name: ExecutableName('example', package: 'cli_launcher_example'),
      entrypoint: (args, context) {
        print(
          'Running v2 with '
          'local version ${context.localInstallation?.version} and '
          'global version ${context.globalInstallation?.version}.',
        );
      },
    ),
  );
}
