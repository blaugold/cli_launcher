import 'dart:async';
import 'dart:io';

import 'package:cli_launcher/cli_launcher.dart';

class ExampleLauncher extends CliLauncher {
  ExampleLauncher()
      : super(
          location: 'package:cli_launcher_example/src/launcher.dart',
          executableName: 'example',
        );

  @override
  FutureOr<void> run(List<String> args) {
    final location = isLocalInstallation ? 'local' : 'global';
    print(
      'Running $location installation in ${Directory.current} with $args as '
      'arguments.',
    );
  }
}
