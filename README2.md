# Pomodoro GUI

Flutter desktop companion for the Rust Pomodoro timer. This repository is independent of the Rust repository in the sibling `pomodoro/` folder.

The Flutter package is in `pomodoro_gui/`. On Windows, start the Rust repository's service-mode executable from this folder:

```powershell
cd pomodoro_gui
flutter pub get
flutter run -d windows
```

The app looks for `../../pomodoro/target/debug/locking-pomodoro-timer.exe` relative to the Flutter project directory. Override the executable path when needed:

```powershell
$env:POMODORO_RUST_EXECUTABLE = "C:\path\to\locking-pomodoro-timer.exe"
flutter run -d windows
```

The Rust process uses its `pomodoro_options.json` file beside the executable. The versioned JSON Lines contract is documented in the Rust repository's README.