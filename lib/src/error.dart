import 'dart:async';
import 'dart:io';

import 'logging.dart';

class CliLauncherException implements Exception {
  CliLauncherException(this.message, {this.exitCode = 1});

  final String message;

  final int exitCode;

  @override
  String toString() => message;
}

Future<void> withErrorHandling(FutureOr<void> Function() fn) async {
  try {
    await fn();
  } on CliLauncherException catch (error) {
    logger.stderr(error.toString());
    exitCode = error.exitCode;
  }
}
