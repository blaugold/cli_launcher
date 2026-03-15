import 'package:cli_launcher/cli_launcher.dart';

void main(List<String> args) {
  launchExecutable(
    args,
    LaunchConfig(
      name: ExecutableName(
        'example_flutter_workspace',
        package: 'cli_launcher_example_flutter_workspace',
      ),
      entrypoint: (args, context) {
        print(
          'Running flutter workspace example with '
          'local version ${context.localInstallation?.version} and '
          'global version ${context.globalInstallation?.version}.',
        );
      },
    ),
  );
}
