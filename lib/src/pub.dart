import 'package:path/path.dart' as p;

import 'io.dart';

String pubspecPath(String packageRoot) => p.join(packageRoot, 'pubspec.yaml');

String pubspecOverridesPath(String packageRoot) =>
    p.join(packageRoot, 'pubspec_overrides.yaml');

String pubspecLockPath(String packageRoot) =>
    p.join(packageRoot, 'pubspec.lock');

bool pubDependenciesAreUpToDate(String packageRoot) {
  final pubspec = pubspecPath(packageRoot);
  final pubspecLock = pubspecLockPath(packageRoot);
  if (!fileExists(pubspecLock)) {
    return false;
  }

  if (fileIsNewerThanOtherFile(pubspec, pubspecLock)) {
    return false;
  }

  final pubspecOverrides = pubspecOverridesPath(packageRoot);
  if (fileExists(pubspecOverrides) &&
      fileIsNewerThanOtherFile(pubspecOverrides, pubspecLock)) {
    return false;
  }

  return true;
}
