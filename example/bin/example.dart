import 'package:cli_launcher/cli_launcher.dart';

import '../lib/src/launcher.dart';

void main(List<String> arguments) =>
    runGlobalInstallation(arguments, ExampleLauncher());
