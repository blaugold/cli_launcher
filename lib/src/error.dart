import 'dart:async';
import 'dart:io';

import 'package:cli_util/cli_logging.dart';

class CliLauncherException implements Exception {
  CliLauncherException(this.message, {this.exitCode = 1});

  final String message;

  final int exitCode;

  @override
  String toString() => message;
}

Future<void> withErrorHandling(
  Logger logger,
  FutureOr<void> Function() fn,
) async {
  try {
    await fn();
  } on CliLauncherException catch (error) {
    logger.stderr(error.toString());
    exitCode = error.exitCode;
  }
}
