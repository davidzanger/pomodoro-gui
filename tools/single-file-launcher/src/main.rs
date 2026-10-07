#![windows_subsystem = "windows"]

use std::env;
use std::error::Error;
use std::ffi::OsStr;
use std::fs::{self, File};
use std::io::{self, Cursor};
use std::os::windows::ffi::OsStrExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use zip::ZipArchive;

const PAYLOAD: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/pomodoro-payload.zip"));
const PAYLOAD_HASH: &str = env!("POMODORO_PAYLOAD_HASH");
const APPLICATION_NAME: &str = "pomodoro_gui.exe";
const APP_DIRECTORY_NAME: &str = "PomodoroGui";

fn main() {
    if let Err(error) = launch() {
        show_error(&format!("Could not start Pomodoro:\n\n{error:#}"));
    }
}

fn launch() -> Result<(), Box<dyn Error>> {
    let local_app_data =
        env::var_os("LOCALAPPDATA").ok_or("Windows did not provide the LOCALAPPDATA directory")?;
    let install_directory = PathBuf::from(local_app_data).join(APP_DIRECTORY_NAME);
    fs::create_dir_all(&install_directory)?;

    let application = install_directory.join(APPLICATION_NAME);
    if !is_payload_current(&install_directory, &application)? {
        extract_payload(&install_directory)?;
        fs::write(install_directory.join(".payload-sha256"), PAYLOAD_HASH)?;
    }

    Command::new(application)
        .current_dir(&install_directory)
        .spawn()?;
    Ok(())
}

fn is_payload_current(install_directory: &Path, application: &Path) -> io::Result<bool> {
    let marker = install_directory.join(".payload-sha256");
    let installed_hash = match fs::read_to_string(marker) {
        Ok(hash) => hash,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error),
    };
    Ok(installed_hash == PAYLOAD_HASH
        && application.is_file()
        && install_directory.join("flutter_windows.dll").is_file()
        && install_directory.join("pomodoro_gui_native.dll").is_file()
        && install_directory.join("data").is_dir())
}

fn extract_payload(install_directory: &Path) -> Result<(), Box<dyn Error>> {
    let mut archive = ZipArchive::new(Cursor::new(PAYLOAD))?;
    for index in 0..archive.len() {
        let mut entry = archive.by_index(index)?;
        let relative_path = entry
            .enclosed_name()
            .ok_or_else(|| format!("Invalid path in release archive: {}", entry.name()))?;
        let destination = install_directory.join(relative_path);

        if entry.is_dir() {
            fs::create_dir_all(destination)?;
            continue;
        }

        let parent = destination
            .parent()
            .ok_or_else(|| format!("Invalid destination path: {}", destination.display()))?;
        fs::create_dir_all(parent)?;
        io::copy(&mut entry, &mut File::create(destination)?)?;
    }
    Ok(())
}

fn show_error(message: &str) {
    let message: Vec<u16> = OsStr::new(message).encode_wide().chain(Some(0)).collect();
    let title: Vec<u16> = OsStr::new("Pomodoro")
        .encode_wide()
        .chain(Some(0))
        .collect();
    unsafe {
        windows_sys::Win32::UI::WindowsAndMessaging::MessageBoxW(
            std::ptr::null_mut(),
            message.as_ptr(),
            title.as_ptr(),
            windows_sys::Win32::UI::WindowsAndMessaging::MB_OK
                | windows_sys::Win32::UI::WindowsAndMessaging::MB_ICONERROR,
        );
    }
}
