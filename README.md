# Pomodoro GUI

Windows desktop app for the [Locking Pomodoro Timer](https://github.com/davidzanger/Locking-Pomodoro-Timer). The Rust timer is compiled as a native library and called in-process through [Flutter Rust Bridge](https://cjycode.com/flutter_rust_bridge/); the app no longer starts a separate Rust service executable.

## Development prerequisites

- Flutter with Windows desktop and Native Assets support (the checked setup uses Flutter 3.47 and Dart 3.13).
- Rust toolchain 1.93.1, installed automatically by the Rust toolchain file.
- Visual Studio C++ desktop tools and a Windows SDK.
- The Rust repository checked out at `..\pomodoro` relative to this repository.
- `flutter_rust_bridge_codegen` 2.13.0 for regenerating the bindings.

Most generated Windows runner files are intentionally not versioned. The project-level `windows/CMakeLists.txt` is versioned because it installs the Rust Native Asset beside the executable. On a fresh clone, create the remaining runner files once with the Flutter SDK installed:

```powershell
flutter create --platforms=windows --no-pub .
```

From this repository root:

```powershell
flutter pub get
flutter_rust_bridge_codegen generate
flutter run -d windows
```

## Windows Rust integration

The generated FRB API is in `lib/src/rust/`; edit the bridge API in `rust/src/api/`. `flutter_rust_bridge.yaml` points code generation at that API, and `hook/build.dart` builds the bridge crate as a Windows Native Asset during the Flutter build. The timer logic remains in the sibling `pomodoro` repository, which is a path dependency of the bridge crate. The Rust timer keeps its `pomodoro_options.json` beside the Flutter executable.

The Flutter app needs neither a `POMODORO_RUST_EXECUTABLE` environment variable nor a separate `locking-pomodoro-timer.exe`. Rust's existing `--service` CLI entry point remains available for compatibility and testing.

The top-bar **Settings** button opens every timer option in `pomodoro_options.json`: durations, break cycles, Additional Pomodoro repetition and break decisions, automatic starts, end actions, sound paths, and break reminders. Each control has an info button that also shows its explanation on hover. Changes save immediately; durations take effect on the next phase and actions on upcoming phase completions. Repetition and the break decision are enabled by default when the Additional Pomodoro duration is positive. After each naturally completed Additional Pomodoro, the selected sound or screen lock runs, then the next Additional Pomodoro starts automatically. The break decision can stay open while further Additional Pomodoros run. **Keep working** or dismissing the decision leaves the current timer running; **Take a break** and **Skip to next session** start the due break immediately without running the current phase's end action. A reminder repeats while the next Pomodoro is waiting for manual start. The app theme is stored separately by Flutter using `shared_preferences` and is never written to the Rust options file.

## In-app logs

The top-bar **View logs** button opens Talker's in-app log history. The app uses
[`talker_flutter`](https://pub.dev/packages/talker_flutter) because it provides
both the logger and a ready-made Flutter log screen; the separate
[`logger`](https://pub.dev/packages/logger) package is a lightweight console
logger without that built-in viewer. The history includes Flutter framework
and uncaught async errors, Flutter-side timer commands and state changes, and
errors reported by the Rust bridge. Internal Rust logs are not forwarded to
the Flutter process.

## Tests

```powershell
flutter analyze
flutter test
flutter test --coverage
.\tools\check-flutter-coverage.ps1
cargo test --manifest-path rust\Cargo.toml
cargo test --manifest-path ..\..\pomodoro\Cargo.toml
flutter test integration_test\timer_flow_test.dart -d windows
```

Flutter's built-in coverage option writes `coverage/lcov.info`. The coverage
check reports line coverage for hand-written Dart under `lib/`, excluding the
generated Rust bridge files in `lib/src/rust/`, and fails unless coverage is
above 95%. The Flutter tests include an in-process FFI event-stream test. The
Rust suite also tests the original `--service` process protocol to preserve CLI
compatibility. The Windows integration test drives the desktop controls through
the real Rust timer; run it separately on a Windows desktop with build tools.

## Single-file Windows package

The regular Flutter release still consists of several runtime files, including `flutter_windows.dll`, the `data` directory, and the Rust native library. To create one file for distribution, run [`tools/package-windows.ps1`](./tools/package-windows.ps1):

```powershell
.\tools\package-windows.ps1
```

If the generated `windows\` runner is missing, the script creates it before building. This builds the Windows release and produces `dist\Pomodoro.exe`. On first launch, that self-extracting executable places the complete app under `%LOCALAPPDATA%\PomodoroGui` and starts it from there. The extraction directory and Rust options file persist between launches. The package is one file to distribute, but it extracts multiple files to run; it does not merge the Flutter runtime into one native PE executable.
