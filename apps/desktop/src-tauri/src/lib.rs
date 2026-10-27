#[cfg(windows)]
use glideframe_recorder::platform;
#[cfg(windows)]
use glideframe_recorder::smoke;
use glideframe_recorder::{models, recorder};
mod commands;

use std::sync::{Arc, Mutex};

use commands::{
    cancel_conversion, conversion_status, convert_media, export_project, list_audio_devices,
    list_camera_devices, list_capture_sources, list_projects, open_project, open_recordings_folder,
    open_screen_recording_settings, pause_recording, recordings_folder,
    recover_interrupted_projects, request_screen_recording_permission, resume_recording,
    reveal_project, reveal_project_video, save_project_edits, screen_recording_permission_granted,
    start_recording, stop_recording,
};
use recorder::SessionManager;

pub struct AppState {
    pub(crate) sessions: Arc<Mutex<SessionManager>>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            sessions: Arc::new(Mutex::new(SessionManager::native())),
        }
    }
}

pub fn run() {
    #[cfg(windows)]
    if std::env::args().nth(1).as_deref() == Some("--smoke-recording") {
        match smoke::run() {
            Ok(()) => std::process::exit(0),
            Err(error) => {
                eprintln!("{error}");
                std::process::exit(1);
            }
        }
    }
    #[cfg(windows)]
    if std::env::args().nth(1).as_deref() == Some("--record-worker") {
        match platform::run_recording_worker() {
            Ok(()) => std::process::exit(0),
            Err(error) => {
                eprintln!("{error}");
                std::process::exit(1);
            }
        }
    }
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            list_capture_sources,
            list_audio_devices,
            list_camera_devices,
            list_projects,
            recover_interrupted_projects,
            start_recording,
            pause_recording,
            resume_recording,
            stop_recording,
            open_project,
            save_project_edits,
            conversion_status,
            convert_media,
            cancel_conversion,
            export_project,
            open_recordings_folder,
            recordings_folder,
            open_screen_recording_settings,
            screen_recording_permission_granted,
            request_screen_recording_permission,
            reveal_project,
            reveal_project_video
        ])
        .run(tauri::generate_context!())
        .expect("failed to run GlideFrame desktop app");
}
