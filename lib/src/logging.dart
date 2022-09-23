import 'dart:io';

import 'package:cli_util/cli_logging.dart';

const verboseLoggingEnvVar = 'DART_CLI_LAUNCHER_VERBOSE_LOGGING';

bool get verboseLoggingEnVarIsSet =>
    Platform.environment.containsKey(verboseLoggingEnvVar);

Logger get logger => _logger;
late Logger _logger;

void initLogger(List<String> arguments) {
  _logger = arguments.contains('--verbose') || verboseLoggingEnVarIsSet
      ? Logger.verbose()
      : Logger.standard();
}

Map<String, String>? updateEnvironmentToPropagateLogging([
  Map<String, String>? environment,
]) {
  if (logger.isVerbose && !verboseLoggingEnVarIsSet) {
    environment ??= Map.of(Platform.environment);
    environment[verboseLoggingEnvVar] = 'true';
  }
  return environment;
}
