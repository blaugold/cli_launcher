import 'dart:async';

import 'error.dart';
import 'logging.dart';

Future<void> cliLauncherShell(
  String name,
  List<String> arguments,
  FutureOr<void> Function() fn,
) async {
  initLogger(arguments);
  logger.trace('Starting $name.');
  try {
    await withErrorHandling(fn);
  } finally {
    logger.trace('Finished $name.');
  }
}
