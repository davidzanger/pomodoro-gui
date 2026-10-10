use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::Mutex;
use std::thread;

use crate::frb_generated::StreamSink;
use flutter_rust_bridge::frb;

/// A live connection to the in-process Rust timer.
pub struct TimerService {
    commands: Sender<String>,
    events: Mutex<Option<Receiver<String>>>,
}

/// A supported timer operation.
pub enum TimerCommand {
    Start,
    Pause,
    Resume,
    Skip,
    Cancel,
    Quit,
}

/// Loads the Rust timer options used by the settings screen.
pub fn load_timer_settings() -> Result<String, String> {
    locking_pomodoro_timer::read_timer_settings_json()
}

/// Persists validated timer options through the Rust configuration owner.
pub fn save_timer_settings(settings_json: String) -> Result<(), String> {
    locking_pomodoro_timer::save_timer_settings_json(&settings_json)
}

/// Creates a timer service and starts its Rust worker thread.
pub fn create_timer_service() -> Result<TimerService, String> {
    let (command_sender, command_receiver) = mpsc::channel();
    let (event_sender, event_receiver) = mpsc::channel();
    let failure_sender = event_sender.clone();

    thread::Builder::new()
        .name("pomodoro-timer".to_owned())
        .spawn(move || {
            if let Err(error) =
                locking_pomodoro_timer::run_embedded_service(command_receiver, event_sender)
            {
                let event = serde_json::json!({
                    "protocolVersion": 1,
                    "event": {
                        "type": "error",
                        "message": format!("Rust timer failed: {error}"),
                    },
                });
                if let Err(send_error) = failure_sender.send(event.to_string()) {
                    eprintln!("Could not report Rust timer failure: {send_error}");
                }
            }
        })
        .map_err(|error| format!("Could not start Rust timer worker: {error}"))?;

    Ok(TimerService {
        commands: command_sender,
        events: Mutex::new(Some(event_receiver)),
    })
}

impl TimerService {
    /// Forwards Rust service events to Dart as a stream.
    pub fn events(&self, sink: StreamSink<String>) -> Result<(), String> {
        let receiver = self
            .events
            .lock()
            .map_err(|error| format!("Timer event stream lock is poisoned: {error}"))?
            .take()
            .ok_or_else(|| "Timer event stream is already open.".to_owned())?;

        thread::Builder::new()
            .name("pomodoro-events".to_owned())
            .spawn(move || {
                while let Ok(event) = receiver.recv() {
                    if sink.add(event).is_err() {
                        break;
                    }
                }
            })
            .map_err(|error| format!("Could not start Rust event forwarding thread: {error}"))?;
        Ok(())
    }

    /// Sends a timer command to the Rust worker.
    pub fn send_command(&self, command: TimerCommand, seconds: Option<i64>) -> Result<(), String> {
        let command_json = match command {
            TimerCommand::Start => r#"{"type":"start"}"#.to_owned(),
            TimerCommand::Pause => r#"{"type":"pause"}"#.to_owned(),
            TimerCommand::Resume => r#"{"type":"resume"}"#.to_owned(),
            TimerCommand::Skip => {
                let seconds = seconds.ok_or_else(|| "Skip requires seconds.".to_owned())?;
                if seconds < 0 {
                    return Err("Skip seconds must not be negative.".to_owned());
                }
                format!(r#"{{"type":"skip","seconds":{seconds}}}"#)
            }
            TimerCommand::Cancel => r#"{"type":"cancel"}"#.to_owned(),
            TimerCommand::Quit => r#"{"type":"quit"}"#.to_owned(),
        };
        let request = format!(r#"{{"protocolVersion":1,"command":{command_json}}}"#);
        self.commands
            .send(request)
            .map_err(|error| format!("Could not send command to Rust timer: {error}"))
    }

    /// Updates timer settings for phases that have not started yet.
    pub fn update_settings(
        &self,
        duration_pomodoro: i32,
        additional_duration: i32,
        duration_short_break: i32,
        duration_long_break: i32,
        interval_long_break: i32,
        auto_start_break: bool,
        auto_start_pomodoro: bool,
    ) -> Result<(), String> {
        let command = serde_json::json!({
            "type": "updateSettings",
            "settings": {
                "durationPomodoro": duration_pomodoro,
                "additionalDuration": additional_duration,
                "durationShortBreak": duration_short_break,
                "durationLongBreak": duration_long_break,
                "intervalLongBreak": interval_long_break,
                "autoStartBreak": auto_start_break,
                "autoStartPomodoro": auto_start_pomodoro,
            },
        });
        self.commands
            .send(
                serde_json::json!({
                    "protocolVersion": 1,
                    "command": command,
                })
                .to_string(),
            )
            .map_err(|error| format!("Could not update Rust timer settings: {error}"))
    }
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
