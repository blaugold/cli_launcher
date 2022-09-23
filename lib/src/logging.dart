import 'dart:io';
import 'dart:io' as io;

import 'package:cli_util/cli_logging.dart';

const _indentationForDescendants = '  ';
const _verboseLoggingEnvVar = 'DART_CLI_LAUNCHER_VERBOSE_LOGGING';

String? get _verboseLoggingEnvBarValue =>
    Platform.environment[_verboseLoggingEnvVar];

final _childIndentation =
    '${_verboseLoggingEnvBarValue ?? ''}$_indentationForDescendants';

Logger get logger => _logger;
late Logger _logger;

void initLogger(List<String> arguments) {
  final indentation = _verboseLoggingEnvBarValue ??
      (arguments.contains('--verbose') ? '' : null);
  if (indentation != null) {
    _logger = _VerboseLogger(indentation: indentation);
  } else {
    _logger = Logger.standard();
  }
}

Map<String, String>? updateEnvironmentToPropagateLogging([
  Map<String, String>? environment,
]) {
  if (logger.isVerbose) {
    environment ??= Map.of(Platform.environment);
    environment[_verboseLoggingEnvVar] = _childIndentation;
  }
  return environment;
}

class _VerboseLogger implements Logger {
  @override
  Ansi ansi = Ansi(Ansi.terminalSupportsAnsi);
  bool logTime = true;
  final _timer = Stopwatch()..start();
  final String indentation;

  _VerboseLogger({required this.indentation});

  @override
  bool get isVerbose => true;

  @override
  void stdout(String message) {
    io.stdout.writeln('$indentation${_createPrefix()}$message');
  }

  @override
  void stderr(String message) {
    io.stderr.writeln(
      '$indentation${_createPrefix()}${ansi.red}$message${ansi.none}',
    );
  }

  @override
  void trace(String message) {
    io.stdout.writeln(
      '$indentation${_createPrefix()}${ansi.gray}$message${ansi.none}',
    );
  }

  @override
  void write(String message) {
    io.stdout.write(message);
  }

  @override
  void writeCharCode(int charCode) {
    io.stdout.writeCharCode(charCode);
  }

  @override
  Progress progress(String message) => SimpleProgress(this, message);

  @override
  @Deprecated('This method will be removed in the future')
  void flush() {}

  String _createPrefix() {
    if (!logTime) {
      return '';
    }

    var seconds = _timer.elapsedMilliseconds / 1000.0;
    final minutes = seconds ~/ 60;
    seconds -= minutes * 60.0;

    final buf = StringBuffer();
    if (minutes > 0) {
      buf.write((minutes % 60));
      buf.write('m ');
    }

    buf.write(seconds.toStringAsFixed(3).padLeft(minutes > 0 ? 6 : 1, '0'));
    buf.write('s');

    return '[${buf.toString().padLeft(11)}] ';
  }
}
