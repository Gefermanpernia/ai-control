# AI Control

AI Control is a deterministic, mock-only macOS menu-bar app for switching
between simulated Claude and Codex CLI accounts.

## Run tests

Use the repository test script with the active Apple developer toolchain:

```sh
./scripts/test
```

SwiftPM arguments can be passed through for focused runs:

```sh
./scripts/test --filter ControlStoreTests
```

With a full Xcode installation, the script runs the standard `swift test`
command. With Command Line Tools only, it supplies the framework and runtime
paths required by Swift Testing. Installing Xcode and selecting its developer
directory remains the standard long-term setup.
