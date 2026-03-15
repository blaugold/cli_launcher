[![CI](https://github.com/blaugold/cli_launcher/actions/workflows/ci.yaml/badge.svg)](https://github.com/blaugold/cli_launcher/actions/workflows/ci.yaml)
[![Pub Version](https://img.shields.io/pub/v/cli_launcher)](https://pub.dev/packages/cli_launcher)

CLI development utility to support launching locally installed versions.

When the globally installed version of a CLI is launched and it finds a locally
installed version of itself that is a different version, it will launch the
locally installed version.

Otherwise, the globally installed version will continue to run.

Installing means adding the package that contains the CLI executable to a
pubspec.yaml file.

To find the locally installed version, the globally installed version will
search for a pubspec.yaml file in the current directory or any parent directory.
If it finds one, it will look for a dependency on the package that contains the
CLI executable.

In addition, if the CLI is executed in the package that contains the CLI
executable, the current version in that package will be launched. This is useful
for development.

## Launch flow

```mermaid
flowchart TD
    A["User invokes CLI"] --> B["launchExecutable()"]
    B --> C{"Launch context\nin args?"}

    C -- "Yes (relaunched by global)" --> D["Restore original working\ndirectory, call entrypoint"]
    C -- "No (initial invocation)" --> E["Detect global installation\nfrom Platform.script"]

    E --> F["Search for local installation\n(walk up from cwd, check pubspec.yaml\nfor dependency or dev_dependency)"]

    F -- "Not found" --> GLOBAL["Run entrypoint\nwith global installation"]
    F -- "Found" --> G{"pubspec.lock\nup to date?"}

    G -- "Missing or\nolder than\npubspec.yaml" --> H["Run pub get from\nlock file root"]
    G -- "Yes" --> I

    H -- "Failed" --> EXIT["Exit with error"]
    H -- "OK" --> I{"Source package,\npath dep, or\nversion mismatch?"}

    I -- "Yes" --> J["Launch local via\ndart run package:executable\n(inject launch context in args)"]
    I -- "No" --> GLOBAL

    J --> K["New process starts,\ncalls launchExecutable(),\nfinds launch context in args"]
    K --> D
```
