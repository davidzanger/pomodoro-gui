# Pomodoro GUI

Windows desktop app for the [Locking Pomodoro Timer](https://github.com/davidzanger/Locking-Pomodoro-Timer). The Rust timer is compiled as a native library and called in-process through [Flutter Rust Bridge](https://cjycode.com/flutter_rust_bridge/); the app no longer starts a separate Rust service executable.

## Development prerequisites

- Flutter with Windows desktop and Native Assets support (the checked setup uses Flutter 3.47 and Dart 3.13).
- Rust toolchain 1.93.1, installed automatically by the Rust toolchain file.
- Visual Studio C++ desktop tools and a Windows SDK.
- The Rust repository checked out at `..\..\pomodoro` relative to this repository.
- `flutter_rust_bridge_codegen` 2.13.0 for regenerating the bindings.

The generated Windows runner is intentionally not versioned. On a fresh clone, create it once with the Flutter SDK installed:

```powershell
flutter create --platforms=windows --no-pub .
```

From this repository root:

```powershell
flutter pub get
flutter_rust_bridge_codegen generate
flutter run -d windows
```

The generated FRB API is in `lib/src/rust/`; edit the bridge API in `rust/src/api/`. The Native Assets hook builds the Rust library during the Flutter Windows build. The Rust timer keeps its `pomodoro_options.json` beside the Flutter executable.

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
cargo test --manifest-path ..\..\pomodoro\Cargo.toml
```

The Flutter tests include an in-process FFI event-stream test. The Rust suite also tests the original `--service` process protocol to preserve CLI compatibility.

## Single-file Windows package

The regular Flutter release still consists of several runtime files, including `flutter_windows.dll`, the `data` directory, and the Rust native library. To create one file for distribution, run:

```powershell
.\tools\package-windows.ps1
```

If the generated `windows\` runner is missing, the script creates it before building. This builds the Windows release and produces `dist\Pomodoro.exe`. On first launch, that self-extracting executable places the complete app under `%LOCALAPPDATA%\PomodoroGui` and starts it from there. The extraction directory and Rust options file persist between launches. The package is one file to distribute, but it extracts multiple files to run.
