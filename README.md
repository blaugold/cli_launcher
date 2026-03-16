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
    B --> C{"Launch context<br/>in args?"}

    C -- "Yes (relaunched by global)" --> D["Restore original working<br/>directory, call entrypoint"]
    C -- "No (initial invocation)" --> E["Detect global installation<br/>from Platform.script"]

    E --> F["Search for local installation<br/>(walk up from cwd, check pubspec.yaml<br/>for dependency or dev_dependency)"]

    F -- "Found" --> G{"pubspec.lock<br/>up to date?"}
    F -- "Not found" --> GLOBAL

    G -- "Yes" --> I
    G -- "Missing or<br/>older than<br/>pubspec.yaml" --> H["Run pub get from<br/>lock file root"]

    H -- "OK" --> I{"Source package,<br/>path dep, or<br/>version mismatch?"}
    H -- "Failed" --> EXIT["Exit with error"]

    I -- "No" --> GLOBAL["Run entrypoint<br/>with global installation"]
    I -- "Yes" --> J["Launch local via<br/>dart run package:executable<br/>(inject launch context in args)"]

    J --> K["New process starts,<br/>calls launchExecutable(),<br/>finds launch context in args"]
    K --> D
```
