use std::path::PathBuf;

use tauri::State;
use uuid::Uuid;

use crate::{
    models::{
        AudioDevice, CameraDevice, CaptureSource, ProjectManifest, ProjectSummary,
        RecordingOptions, RecordingSession,
    },
    recorder::{self, RecorderError},
    AppState,
};

type CommandResult<T> = Result<T, String>;

#[tauri::command]
pub async fn conversion_status() -> CommandResult<String> {
    blocking(glideframe_recorder::conversion::status).await
}
#[tauri::command]
pub async fn cancel_conversion() -> CommandResult<()> {
    blocking(glideframe_recorder::conversion::cancel).await
}
#[tauri::command]
pub async fn convert_media(
    input: String,
    output_directory: String,
    settings: glideframe_recorder::conversion::ConversionSettings,
) -> CommandResult<String> {
    blocking(move || {
        glideframe_recorder::conversion::convert(
            &PathBuf::from(input),
            &PathBuf::from(output_directory),
            settings,
        )
        .map(|path| path.display().to_string())
    })
    .await
}

#[tauri::command]
pub async fn save_project_edits(
    path: String,
    edits: glideframe_recorder::models::ProjectEdits,
) -> CommandResult<ProjectManifest> {
    blocking(move || {
        Ok(
            glideframe_recorder::project::ProjectStore::for_root(PathBuf::from("."))
                .save_edits(&PathBuf::from(path), edits)?,
        )
    })
    .await
}

#[tauri::command]
pub async fn list_capture_sources() -> CommandResult<Vec<CaptureSource>> {
    blocking(recorder::list_capture_sources).await
}

#[tauri::command]
pub async fn list_audio_devices() -> CommandResult<Vec<AudioDevice>> {
    blocking(recorder::list_audio_devices).await
}

#[tauri::command]
pub async fn list_camera_devices() -> CommandResult<Vec<CameraDevice>> {
    blocking(recorder::list_camera_devices).await
}

#[tauri::command]
pub async fn list_projects() -> CommandResult<Vec<ProjectSummary>> {
    blocking(recorder::list_projects).await
}

#[tauri::command]
pub async fn recover_interrupted_projects() -> CommandResult<Vec<ProjectSummary>> {
    blocking(recorder::recover_interrupted_projects).await
}

#[tauri::command]
pub async fn start_recording(
    options: RecordingOptions,
    state: State<'_, AppState>,
) -> CommandResult<RecordingSession> {
    let sessions = state.sessions.clone();
    blocking(move || {
        sessions
            .lock()
            .map_err(|_| RecorderError::InvalidState)?
            .start(options)
    })
    .await
}

#[tauri::command]
pub async fn pause_recording(
    session_id: String,
    state: State<'_, AppState>,
) -> CommandResult<RecordingSession> {
    let id =
        Uuid::parse_str(&session_id).map_err(|_| "Invalid recording session id.".to_string())?;
    let sessions = state.sessions.clone();
    blocking(move || {
        sessions
            .lock()
            .map_err(|_| RecorderError::InvalidState)?
            .pause(id)
    })
    .await
}

#[tauri::command]
pub async fn resume_recording(
    session_id: String,
    state: State<'_, AppState>,
) -> CommandResult<RecordingSession> {
    let id =
        Uuid::parse_str(&session_id).map_err(|_| "Invalid recording session id.".to_string())?;
    let sessions = state.sessions.clone();
    blocking(move || {
        sessions
            .lock()
            .map_err(|_| RecorderError::InvalidState)?
            .resume(id)
    })
    .await
}

#[tauri::command]
pub async fn stop_recording(
    session_id: String,
    state: State<'_, AppState>,
) -> CommandResult<ProjectManifest> {
    let id =
        Uuid::parse_str(&session_id).map_err(|_| "Invalid recording session id.".to_string())?;
    let sessions = state.sessions.clone();
    blocking(move || {
        sessions
            .lock()
            .map_err(|_| RecorderError::InvalidState)?
            .stop(id)
    })
    .await
}

#[tauri::command]
pub async fn open_project(path: String) -> CommandResult<ProjectManifest> {
    blocking(move || recorder::open_project(&PathBuf::from(path))).await
}

#[tauri::command]
pub async fn export_project(project_path: String, preset: String) -> CommandResult<String> {
    blocking(move || {
        recorder::export_project(&PathBuf::from(project_path), &preset)
            .map(|path| path.display().to_string())
    })
    .await
}

#[tauri::command]
pub fn recordings_folder() -> CommandResult<String> {
    recorder::recordings_folder()
        .map(|path| path.display().to_string())
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn open_recordings_folder() -> CommandResult<String> {
    blocking(|| recorder::open_recordings_folder().map(|path| path.display().to_string())).await
}

#[tauri::command]
pub async fn reveal_project(path: String) -> CommandResult<String> {
    blocking(move || {
        recorder::reveal_project(&PathBuf::from(path)).map(|path| path.display().to_string())
    })
    .await
}

#[tauri::command]
pub async fn reveal_project_video(path: String) -> CommandResult<String> {
    blocking(move || {
        recorder::reveal_project_video(&PathBuf::from(path)).map(|path| path.display().to_string())
    })
    .await
}

#[tauri::command]
pub async fn open_screen_recording_settings() -> CommandResult<()> {
    blocking(recorder::open_screen_recording_settings).await
}

#[tauri::command]
pub async fn screen_recording_permission_granted() -> CommandResult<bool> {
    blocking(recorder::screen_recording_permission_granted).await
}

#[tauri::command]
pub async fn request_screen_recording_permission() -> CommandResult<bool> {
    blocking(recorder::request_screen_recording_permission).await
}

async fn blocking<T: Send + 'static>(
    action: impl FnOnce() -> Result<T, RecorderError> + Send + 'static,
) -> CommandResult<T> {
    tauri::async_runtime::spawn_blocking(action)
        .await
        .map_err(|error| error.to_string())?
        .map_err(|error| error.to_string())
}
