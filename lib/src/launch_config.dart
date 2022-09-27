import 'package:yaml/yaml.dart';

import 'error.dart';

/// The configuration for launching the executables of one package.
///
/// This information is stored under the `cli_launcher` field in the
/// `pubspec.yaml` file of the package.
class LaunchConfig {
  /// Create a new [LaunchConfig].
  LaunchConfig({required this.executables});

  /// Parses a [LaunchConfig] from the given YAML [node].
  ///
  /// [packageName] is the name of the package that this configuration is for.
  factory LaunchConfig.fromYaml({
    required String packageName,
    required YamlNode node,
  }) {
    if (node is! YamlMap) {
      node.error('Expected a map.');
    }

    final executables = <String, ExecutableConfig>{};
    for (final entry in node.nodes.entries) {
      final nameNode = entry.key as YamlNode;
      final name = nameNode.value;
      if (name is! String) {
        nameNode.error('Expected a string.');
      }

      executables[name] = ExecutableConfig.fromYaml(
        packageName: packageName,
        name: name,
        node: entry.value,
      );
    }

    return LaunchConfig(executables: executables);
  }

  /// Loads the launch configuration from the YAML [node] of a `pubspec.yaml`
  /// file, if the file contains launch configuration.
  static LaunchConfig? fromPubspecYaml({required YamlNode node}) {
    if (node is! YamlMap) return null;

    final name = node['name'];
    if (name is! String) {
      return null;
    }

    final cliLauncherNode = node.nodes['cli_launcher'];
    if (cliLauncherNode == null) return null;

    return LaunchConfig.fromYaml(packageName: name, node: cliLauncherNode);
  }

  /// [ExecutableConfig]s for executables in this package.
  final Map<String, ExecutableConfig> executables;
}

/// The configuration for launching a single executable.
class ExecutableConfig {
  /// Create a new [ExecutableConfig].
  ExecutableConfig({
    required this.name,
    required this.launcherFile,
    required this.launcherClass,
  });

  /// Parses a [ExecutableConfig] from the given YAML [node].
  ///
  /// [packageName] is the name of the package that contains the executable.
  ///
  /// [name] is the name of the executable.
  factory ExecutableConfig.fromYaml({
    required String packageName,
    required String name,
    required YamlNode node,
  }) {
    if (node is! YamlMap) {
      node.error('Expected a map.');
    }

    const expectedFields = ['launcherFile', 'launcherClass'];
    for (final field in node.keys) {
      if (!expectedFields.contains(field)) {
        node.error('Unexpected field "$field".');
      }
    }

    // Parse the launcherFile field.
    final launcherFileNode = node.nodes['launcherFile'];
    if (launcherFileNode == null) {
      node.error('Missing "launcherFile" field.');
    }
    final launcherFileVale = launcherFileNode.value;
    if (launcherFileVale is! String) {
      launcherFileNode.error('Expected a string.');
    }
    Uri launcherFile;
    try {
      launcherFile = Uri.parse(launcherFileVale);
    } catch (error) {
      launcherFileNode.error('Expected a valid URI: $error');
    }
    if (launcherFile.scheme != 'package') {
      launcherFileNode.error('Expected a package URI.');
    }
    if (!launcherFile.path.startsWith(packageName)) {
      launcherFileNode.error('Expected a URI for $packageName.');
    }

    // Parse the launcherClass field.
    final launcherClassNode = node.nodes['launcherClass'];
    if (launcherClassNode == null) {
      node.error('Missing "launcherClass" field.');
    }
    final launcherClass = launcherClassNode.value;
    if (launcherClass is! String) {
      launcherClassNode.error('Expected a string.');
    }

    return ExecutableConfig(
      name: name,
      launcherFile: launcherFile,
      launcherClass: launcherClass,
    );
  }

  /// The name of the executable.
  final String name;

  /// The path to the Dart file that contains the launcher class.
  final Uri launcherFile;

  /// The name of the launcher class.
  final String launcherClass;
}

class CliLauncherConfigException extends CliLauncherException {
  CliLauncherConfigException(this.node, String message) : super(message);

  final YamlNode node;

  @override
  String toString() =>
      '`cli_launcher` configuration error:\n${node.span.message(message)}';
}

extension on YamlNode {
  Never error(String message) =>
      throw CliLauncherConfigException(this, message);
}
