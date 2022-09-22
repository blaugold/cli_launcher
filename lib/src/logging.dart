import 'package:cli_util/cli_logging.dart';

Logger createLogger(List<String> arguments) {
  return arguments.contains('--verbose') ? Logger.verbose() : Logger.standard();
}
