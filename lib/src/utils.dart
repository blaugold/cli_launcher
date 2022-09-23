import 'dart:convert';

extension StringUtilsExtension on String {
  String get withoutTrailingNewLine {
    if (isEmpty) return this;
    if (endsWith('\r\n')) return substring(0, length - 2);
    if (endsWith('\n')) return substring(0, length - 1);
    return this;
  }

  List<String> get lines => LineSplitter().convert(this);
}
