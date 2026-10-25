# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-10-25

### Added

- Initial Windows desktop release of Pomodoro GUI, with the Rust timer bundled in the app. Download `Pomodoro.zip`, extract it to a writable folder, and launch `Pomodoro/pomodoro_gui.exe`. Keep the executable, DLLs, and `data` folder together; no separate Rust service executable or environment variable is required.
- A timer dashboard showing the current Pomodoro, Additional Pomodoro, or break, remaining time, and cycle progress. Use the main control to start, pause, or resume, **Skip ahead one minute** to shorten the current phase, and **Skip to next session** to advance immediately without running that phase's end action.
- Repeating Additional Pomodoros and a **Take a break?** decision. With a positive Additional Pomodoro duration, repetition and the decision are enabled by default. Each naturally completed Additional Pomodoro runs its configured sound or screen lock and starts another; repetitions do not count as new Pomodoros. Choose **Keep working**, or dismiss the decision, to leave the timer running. Choose **Take a break** to start the due break immediately. Disable repetition or the decision in **Settings**, or set the Additional Pomodoro duration to 0 to disable that phase.
- Immediate settings updates from the top-bar **Settings** button, with explanations available through each info button. Configure Pomodoro and break durations, the long-break interval, automatic phase starts, sound paths, screen-lock actions, and reminders while a Pomodoro awaits manual start after a break. Durations apply to the next phase; end actions apply to upcoming completions. Timer options are saved in `pomodoro_options.json` beside the executable.
- A separate **Start timer when app opens** preference in **Settings**, enabled by default, that starts the first Pomodoro when the Rust timer is ready. Turn it off to start manually. This preference and the system, light, or dark appearance choice are stored separately from the Rust timer options.
- An in-app log viewer accessible through **View logs** in the top bar. Inspect Flutter errors, timer commands and state changes, and bridge-reported errors when troubleshooting; internal Rust logs are not included.

[1.0.0]: https://github.com/davidzanger/pomodoro-gui/releases/tag/v1.0.0
