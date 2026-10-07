# Windows Rust integration

The Flutter Windows app loads the sibling Rust project as a native library through the generated Flutter Rust Bridge bindings. `flutter_rust_bridge.yaml` points code generation at `rust/src/api/`, and `hook/build.dart` builds that Rust crate as a Windows Native Asset. The Rust timer logic remains in the sibling `pomodoro` repository, which is a path dependency of the bridge crate.

No `POMODORO_RUST_EXECUTABLE` environment variable or separate `locking-pomodoro-timer.exe` is needed by the Flutter app. Rust's existing `--service` CLI entry point remains available for compatibility and testing.

For a single file to distribute, use [`tools/package-windows.ps1`](./tools/package-windows.ps1). It embeds the normal Flutter release bundle in a self-extracting executable. The package extracts to `%LOCALAPPDATA%\PomodoroGui` and runs the Flutter app from that directory; it does not merge the Flutter runtime into one native PE executable.
