import 'dart:async';
import 'dart:io';

import 'package:cli_launcher/cli_launcher.dart';

class ExampleLauncher extends Launcher {
  ExampleLauncher()
      : super(PackageExecutable('cli_launcher_example', 'example'));

  @override
  FutureOr<void> run(List<String> arguments, InstallationLocation location) {
    print(
      'Running ${location.name} installation in ${Directory.current} with '
      '$arguments as arguments.',
    );
  }
}
