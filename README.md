# Pomodoro GUI

A Windows desktop Pomodoro timer with configurable work and break phases, sound alerts, and screen-lock actions. Keep working through repeating Additional Pomodoros, then start your break when you're ready.

Built with Flutter and the Rust [Locking Pomodoro Timer](https://github.com/davidzanger/Locking-Pomodoro-Timer). The timer is bundled with the app and runs in the same process.

## Install on Windows

1. Download `Pomodoro.zip` from the [latest release](https://github.com/davidzanger/pomodoro-gui/releases/latest).
2. Extract it to a writable folder. Keep the executable, DLLs, and `data` folder together.
3. Open `Pomodoro/pomodoro_gui.exe`.

The first Pomodoro starts automatically once the timer is ready. Turn off **Settings → Start timer when app opens** if you prefer to start manually. Settings from the former self-extracting package are not migrated automatically.

## Use the timer

The dashboard shows the current phase, remaining time, and cycle progress.

| Control | What it does |
| --- | --- |
| Play / pause | Start, pause, or resume the timer. |
| **Skip ahead one minute** | Shorten the current phase by one minute. |
| **Skip to next session** | Start the next phase immediately without running the current phase's end action. |
| **Settings** | Change durations, automatic starts, end actions, reminders, and appearance. |
| **View logs** | Open the in-app log history for troubleshooting. |

An **Additional Pomodoro** is a short work phase after a regular Pomodoro. With a positive duration, repetition and the **Take a break?** decision are enabled by default. Each naturally completed Additional Pomodoro runs its configured sound or screen lock and starts another. Repetitions do not count as new Pomodoros toward the next long break.

Choose **Keep working**, or dismiss the decision, to leave the timer running. Choose **Take a break** to start the due break immediately. You can disable repetition or the decision in Settings, or set the Additional Pomodoro duration to `0` to skip that phase.

### Settings and saved data

Settings save immediately. Durations apply to the next phase; end actions apply to upcoming completions.

- Configure Pomodoro, Additional Pomodoro, short-break, and long-break durations, plus the number of Pomodoros between long breaks.
- Choose automatic phase starts, built-in or custom sounds, screen-lock actions, and a repeating reminder while the next Pomodoro waits for manual start after a break.
- Choose a system, light, or dark theme. Each setting's info button explains its behavior and also supports hover.

Timer options are stored in `pomodoro_options.json` beside the executable. The theme and **Start timer when app opens** preference are stored separately through Flutter's `shared_preferences`.

The log viewer includes Flutter errors, timer commands and state changes, and errors reported by the Rust bridge. Internal Rust logs are not included.

## Run from source

### Prerequisites

- Windows with [Flutter's Windows desktop build tools](https://docs.flutter.dev/platform-integration/windows/setup), including Visual Studio's **Desktop development with C++** workload and a Windows SDK.
- Flutter with Native Assets support. The current [dependency lockfile](./pubspec.lock) requires Flutter **3.44.0 or newer** and Dart **3.12.0 or newer, below 4.0.0**. The broader Dart constraint in [pubspec.yaml](./pubspec.yaml) is `>=3.9.2 <4.0.0`.
- [Rust installed through rustup](https://rustup.rs/). The bridge pins Rust **1.93.1** in [rust/rust-toolchain.toml](./rust/rust-toolchain.toml).
- The Rust timer repository checked out beside this project, as required by [rust/Cargo.toml](./rust/Cargo.toml).

Clone both repositories into the same parent folder:

```powershell
git clone https://github.com/davidzanger/Locking-Pomodoro-Timer.git pomodoro
git clone https://github.com/davidzanger/pomodoro-gui.git
cd pomodoro-gui
```

Generate the remaining Windows runner files on a fresh clone, install dependencies, and launch the app:

```powershell
flutter create --platforms=windows --no-pub .
flutter pub get
flutter run -d windows
```

The build hook compiles the Rust library automatically. The app currently supports Windows only.

### Rust bridge development

Edit the bridge API in [rust/src/api/](./rust/src/api/). The underlying timer logic lives in the sibling `pomodoro` repository. [hook/build.dart](./hook/build.dart) builds the bridge as a Native Asset, and [windows/CMakeLists.txt](./windows/CMakeLists.txt) installs it beside the executable.

Bindings in [lib/src/rust/](./lib/src/rust/) are checked in. After changing the bridge API, regenerate them with the matching Flutter Rust Bridge code generator:

```powershell
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
flutter_rust_bridge_codegen generate
```

Code generation is configured in [flutter_rust_bridge.yaml](./flutter_rust_bridge.yaml). Flutter needs no separate Rust service executable or `POMODORO_RUST_EXECUTABLE` environment variable. The Rust timer's `--service` CLI remains available for compatibility and testing.

## Tests

Run these commands from this repository's root after completing source setup:

```powershell
flutter analyze
flutter test --coverage
.\tools\check-flutter-coverage.ps1
cargo test --manifest-path rust\Cargo.toml
cargo test --manifest-path ..\pomodoro\Cargo.toml
```

Flutter writes coverage to `coverage/lcov.info`. The [coverage check](./tools/check-flutter-coverage.ps1) requires line coverage **above 95%** for hand-written Dart under [lib/](./lib/), excluding generated bridge files. Use `flutter test` for a run without coverage. The Flutter suite includes an in-process bridge event-stream test; the Rust timer suite also checks the original service process protocol.

Run the desktop integration tests separately on Windows with build tools installed:

```powershell
flutter test integration_test\timer_flow_test.dart -d windows
flutter test integration_test\break_attention_test.dart -d windows
```

These tests exercise the real Rust timer through the desktop app.

## Build a Windows ZIP

After completing source setup, run:

```powershell
flutter build windows --release
```

The release build automatically creates `dist/Pomodoro.zip`, containing a `Pomodoro/` folder with the executable, DLLs, and assets. Extract and launch it as described in [Install on Windows](#install-on-windows).

The [packaging script](./tools/package-windows.ps1) also builds and packages the app:

```powershell
.\tools\package-windows.ps1
```

## Project information

See the [changelog](./CHANGELOG.md) for release notes and the [glossary](./GLOSSARY.md) for timer terminology. Report bugs and propose changes through [GitHub Issues](https://github.com/davidzanger/pomodoro-gui/issues); include reproduction steps and relevant entries from **View logs**.

## License

Pomodoro GUI is licensed under the [GNU General Public License v3.0](./LICENSE), the same license as the [Rust timer](https://github.com/davidzanger/Locking-Pomodoro-Timer). The license text is copied unchanged from the Rust project.
