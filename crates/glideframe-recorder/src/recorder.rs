#[cfg(not(target_os = "macos"))]
use std::io::Write;
use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
    process::{Child, Command},
    time::{Duration, Instant},
};

use chrono::Utc;
use serde::Deserialize;
use thiserror::Error;
use uuid::Uuid;

use crate::{
    cursor::CursorTracker,
    models::{
        AudioDevice, CameraDevice, CaptureSource, FrameRect, ProjectManifest, ProjectSummary,
        RecordingOptions, RecordingSession, RecordingState, RecoveryJournal, RecoveryState,
    },
    platform,
    project::{ProjectError, ProjectStore},
};

#[derive(Debug, Error)]
#[cfg_attr(not(windows), allow(dead_code))]
pub enum RecorderError {
    #[error("{0}")]
    Project(#[from] ProjectError),
    #[error("Select a recording source before starting.")]
    MissingTarget,
    #[error("Recording session was not found.")]
    MissingSession,
    #[error("Recording session is not in a state that allows this action.")]
    InvalidState,
    #[error("Another recording is already active. Stop it before starting a new one.")]
    ActiveRecordingExists,
    #[error("Invalid recording options: {0}")]
    InvalidOptions(String),
    #[error(
        "FFmpeg is required for the desktop recorder. Install ffmpeg and ensure it is on PATH."
    )]
    MissingFfmpeg,
    #[error("Camera recording is not available in this desktop recorder backend yet. Turn camera recording off and start again.")]
    CameraCaptureUnsupported,
    #[error("Recording did not produce the required media file: {0}")]
    MissingMediaFile(String),
    #[error("Unsupported export preset: {0}")]
    UnsupportedExportPreset(String),
    #[error("Recording is not available on this platform yet.")]
    UnsupportedPlatform,
    #[error("The macOS recorder is unavailable: {0}")]
    CaptureBackendUnavailable(String),
    #[error("{0}")]
    Io(#[from] std::io::Error),
    #[error("{0}")]
    Json(#[from] serde_json::Error),
}

pub type RecorderResult<T> = Result<T, RecorderError>;

#[derive(Debug)]
pub struct SessionManager {
    store: ProjectStore,
    mode: CaptureMode,
    sessions: HashMap<Uuid, ActiveSession>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[cfg_attr(not(test), allow(dead_code))]
enum CaptureMode {
    Native,
    Stub,
}

#[derive(Debug)]
struct ActiveSession {
    public: RecordingSession,
    project_path: PathBuf,
    manifest: ProjectManifest,
    started: Instant,
    paused_started: Option<Instant>,
    paused_duration: Duration,
    cursor_tracker: Option<CursorTracker>,
    #[cfg_attr(target_os = "macos", allow(dead_code))]
    children: Vec<Child>,
}

impl SessionManager {
    pub fn native() -> Self {
        Self {
            store: ProjectStore::default()
                .unwrap_or_else(|_| ProjectStore::for_root(PathBuf::from("."))),
            mode: CaptureMode::Native,
            sessions: HashMap::new(),
        }
    }

    #[cfg(test)]
    pub fn stub_for_root(root: PathBuf) -> Self {
        Self {
            store: ProjectStore::for_root(root),
            mode: CaptureMode::Stub,
            sessions: HashMap::new(),
        }
    }

    #[cfg(any(test, windows))]
    #[allow(dead_code)]
    pub fn native_for_root(root: PathBuf) -> Self {
        Self {
            store: ProjectStore::for_root(root),
            mode: CaptureMode::Native,
            sessions: HashMap::new(),
        }
    }

    pub fn start(&mut self, options: RecordingOptions) -> RecorderResult<RecordingSession> {
        if !self.sessions.is_empty() {
            return Err(RecorderError::ActiveRecordingExists);
        }
        validate_options(&options)?;
        if options.target_id.as_deref().unwrap_or_default().is_empty() {
            return Err(RecorderError::MissingTarget);
        }
        if matches!(self.mode, CaptureMode::Native) {
            platform::ensure_capture_available()?;
        }

        let target = match self.mode {
            CaptureMode::Native => resolve_target(&options)?,
            CaptureMode::Stub => stub_target(&options),
        };
        let (manifest, project_path) = self.store.create_recording_project(&options, &target)?;
        self.write_recovery(&manifest, &project_path, RecoveryState::Preparing)?;
        let children =
            match self.start_capture_for_mode(&options, &target, &manifest, &project_path) {
                Ok(children) => children,
                Err(error) => {
                    let _ = self.store.remove_project(&project_path);
                    return Err(error);
                }
            };
        self.write_recovery(&manifest, &project_path, RecoveryState::Recording)?;
        let cursor_tracker = Some(CursorTracker::start(recording_bounds(&options, &target)));
        let session = RecordingSession {
            id: Uuid::new_v4(),
            state: RecordingState::Recording,
            project_path: project_path.display().to_string(),
            live_preview_path: Some(
                project_path
                    .join("media")
                    .join("live-preview.jpg")
                    .display()
                    .to_string(),
            ),
            started_at: Some(Utc::now()),
            options,
        };

        self.sessions.insert(
            session.id,
            ActiveSession {
                public: session.clone(),
                project_path,
                manifest,
                started: Instant::now(),
                paused_started: None,
                paused_duration: Duration::ZERO,
                cursor_tracker,
                children,
            },
        );
        Ok(session)
    }

    fn start_capture_for_mode(
        &self,
        options: &RecordingOptions,
        target: &CaptureSource,
        manifest: &ProjectManifest,
        project_path: &Path,
    ) -> RecorderResult<Vec<Child>> {
        match self.mode {
            CaptureMode::Native => platform::start_capture(options, target, manifest, project_path),
            CaptureMode::Stub => {
                write_stub_media(project_path, manifest)?;
                Ok(Vec::new())
            }
        }
    }

    pub fn pause(&mut self, session_id: Uuid) -> RecorderResult<RecordingSession> {
        let session = self
            .sessions
            .get_mut(&session_id)
            .ok_or(RecorderError::MissingSession)?;
        if session.public.state != RecordingState::Recording {
            return Err(RecorderError::InvalidState);
        }
        if self.mode == CaptureMode::Native {
            #[cfg(target_os = "macos")]
            platform::pause_capture()?;
            #[cfg(not(target_os = "macos"))]
            pause_capture(&mut session.children)?;
        }
        session.paused_started = Some(Instant::now());
        session.public.state = RecordingState::Paused;
        Ok(session.public.clone())
    }

    pub fn resume(&mut self, session_id: Uuid) -> RecorderResult<RecordingSession> {
        let session = self
            .sessions
            .get_mut(&session_id)
            .ok_or(RecorderError::MissingSession)?;
        if session.public.state != RecordingState::Paused {
            return Err(RecorderError::InvalidState);
        }
        if self.mode == CaptureMode::Native {
            #[cfg(target_os = "macos")]
            platform::resume_capture()?;
            #[cfg(not(target_os = "macos"))]
            resume_capture(&mut session.children)?;
        }
        if let Some(paused_started) = session.paused_started.take() {
            session.paused_duration += paused_started.elapsed();
        }
        session.public.state = RecordingState::Recording;
        Ok(session.public.clone())
    }

    pub fn stop(&mut self, session_id: Uuid) -> RecorderResult<ProjectManifest> {
        let manifest = {
            let session = self
                .sessions
                .get_mut(&session_id)
                .ok_or(RecorderError::MissingSession)?;
            if !matches!(
                session.public.state,
                RecordingState::Recording | RecordingState::Paused | RecordingState::Finalizing
            ) {
                return Err(RecorderError::InvalidState);
            }

            let previous_state = session.public.state;
            session.public.state = RecordingState::Finalizing;
            self.store.write_recovery_journal(
                &RecoveryJournal {
                    project_id: session.manifest.id,
                    state: RecoveryState::Finalizing,
                    started_at: session.public.started_at.unwrap_or_else(Utc::now),
                    source_paths: source_paths(&session.manifest),
                    owner_process_id: Some(std::process::id()),
                },
                &session.project_path,
            )?;
            if let Some(paused_started) = session.paused_started.take() {
                session.paused_duration += paused_started.elapsed();
            }
            let finalization = {
                #[cfg(target_os = "macos")]
                {
                    if self.mode == CaptureMode::Native {
                        platform::finish_capture(&session.project_path)
                    } else {
                        Ok(())
                    }
                }
                #[cfg(not(target_os = "macos"))]
                {
                    finalize_capture(&mut session.children)
                }
            };
            if let Err(error) = finalization {
                session.public.state = previous_state;
                return Err(error);
            }

            let wall_clock_duration = session
                .started
                .elapsed()
                .saturating_sub(session.paused_duration)
                .as_secs_f64();
            if let Err(error) = validate_recorded_media(&session.project_path, &session.manifest) {
                session.public.state = previous_state;
                return Err(error);
            }

            let native_result = read_native_recording_result(&session.project_path)?;
            let recorded_duration = native_result
                .as_ref()
                .map(|result| result.duration)
                .unwrap_or(wall_clock_duration);
            if let Some(result) = native_result.as_ref() {
                apply_native_recording_result(&mut session.manifest, result);
            }

            session.manifest.duration = recorded_duration;
            session.manifest.pointer_events = session
                .cursor_tracker
                .take()
                .map(|tracker| tracker.stop(recorded_duration))
                .unwrap_or_default();
            for source in &mut session.manifest.sources {
                source.duration = recorded_duration;
            }
            self.store.save(&session.manifest, &session.project_path)?;
            self.store.clear_recovery_journal(&session.project_path)?;
            let _ = fs::remove_file(session.project_path.join("recording-result.json"));
            session.manifest.clone()
        };
        self.sessions.remove(&session_id);
        Ok(manifest)
    }

    fn write_recovery(
        &self,
        manifest: &ProjectManifest,
        project_path: &Path,
        state: RecoveryState,
    ) -> RecorderResult<()> {
        self.store.write_recovery_journal(
            &RecoveryJournal {
                project_id: manifest.id,
                state,
                started_at: manifest.created_at,
                source_paths: source_paths(manifest),
                owner_process_id: Some(std::process::id()),
            },
            project_path,
        )?;
        Ok(())
    }
}

pub fn list_capture_sources() -> RecorderResult<Vec<CaptureSource>> {
    platform::list_capture_sources()
}

pub fn list_audio_devices() -> RecorderResult<Vec<AudioDevice>> {
    platform::list_audio_devices()
}

pub fn list_camera_devices() -> RecorderResult<Vec<CameraDevice>> {
    platform::list_camera_devices()
}

pub fn open_project(path: &Path) -> RecorderResult<ProjectManifest> {
    Ok(ProjectStore::for_root(PathBuf::from(".")).load(path)?)
}

pub fn list_projects() -> RecorderResult<Vec<ProjectSummary>> {
    Ok(ProjectStore::default()?.list_projects()?)
}

pub fn recover_interrupted_projects() -> RecorderResult<Vec<ProjectSummary>> {
    Ok(ProjectStore::default()?.recover_interrupted_projects()?)
}

pub fn export_project(project_path: &Path, preset: &str) -> RecorderResult<PathBuf> {
    let manifest = ProjectStore::for_root(PathBuf::from(".")).load(project_path)?;
    let screen = screen_source_path(project_path, &manifest);
    if !screen.is_file() {
        return Err(RecorderError::Io(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            "screen source media is missing; record or repair the project before exporting.",
        )));
    }
    let exports = project_path.join("exports");
    fs::create_dir_all(&exports)?;
    let export_preset = ExportRequest::parse(preset)?;
    let destination = exports.join(format!("{}-{}.mp4", manifest.id, export_preset.name));
    platform::export_media(project_path, &manifest, &export_preset, &destination)?;
    Ok(destination)
}

pub fn recordings_folder() -> RecorderResult<PathBuf> {
    Ok(ProjectStore::default_root_path()?)
}

pub fn open_recordings_folder() -> RecorderResult<PathBuf> {
    let root = recordings_folder()?;
    fs::create_dir_all(&root)?;
    open_path(&root)?;
    Ok(root)
}

pub fn open_screen_recording_settings() -> RecorderResult<()> {
    open_screen_recording_settings_for_platform()
}

pub fn screen_recording_permission_granted() -> RecorderResult<bool> {
    platform::screen_capture_access_status()
}

pub fn request_screen_recording_permission() -> RecorderResult<bool> {
    platform::request_screen_capture_access()
}

pub fn reveal_project(project_path: &Path) -> RecorderResult<PathBuf> {
    if !project_path.exists() {
        return Err(RecorderError::Io(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            format!("Project was not found: {}", project_path.display()),
        )));
    }
    reveal_path(project_path)?;
    Ok(project_path.to_path_buf())
}

pub fn reveal_project_video(project_path: &Path) -> RecorderResult<PathBuf> {
    let manifest = ProjectStore::for_root(PathBuf::from(".")).load(project_path)?;
    let video_path = screen_source_path(project_path, &manifest);
    if !video_path.is_file() {
        return Err(RecorderError::Io(std::io::Error::new(
            std::io::ErrorKind::NotFound,
            format!("Recorded video was not found: {}", video_path.display()),
        )));
    }
    reveal_path(&video_path)?;
    Ok(video_path)
}

fn open_path(path: &Path) -> RecorderResult<()> {
    let status = platform_open_command(path).status()?;
    if status.success() {
        Ok(())
    } else {
        Err(RecorderError::Io(std::io::Error::new(
            std::io::ErrorKind::Other,
            format!("Could not open path: {}", path.display()),
        )))
    }
}

fn reveal_path(path: &Path) -> RecorderResult<()> {
    let status = platform_reveal_command(path).status()?;
    if status.success() {
        Ok(())
    } else {
        Err(RecorderError::Io(std::io::Error::new(
            std::io::ErrorKind::Other,
            format!("Could not reveal path: {}", path.display()),
        )))
    }
}

#[cfg(target_os = "macos")]
fn open_screen_recording_settings_for_platform() -> RecorderResult<()> {
    let status = Command::new("open")
        .arg("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        .status()?;
    if status.success() {
        Ok(())
    } else {
        Err(RecorderError::Io(std::io::Error::new(
            std::io::ErrorKind::Other,
            "Could not open Screen Recording privacy settings.",
        )))
    }
}

#[cfg(not(target_os = "macos"))]
fn open_screen_recording_settings_for_platform() -> RecorderResult<()> {
    Ok(())
}

#[cfg(target_os = "macos")]
fn platform_open_command(path: &Path) -> Command {
    let mut command = Command::new("open");
    command.arg(path);
    command
}

#[cfg(target_os = "macos")]
fn platform_reveal_command(path: &Path) -> Command {
    let mut command = Command::new("open");
    command.arg("-R").arg(path);
    command
}

#[cfg(windows)]
fn platform_open_command(path: &Path) -> Command {
    let mut command = Command::new("explorer");
    command.arg(path);
    command
}

#[cfg(windows)]
fn platform_reveal_command(path: &Path) -> Command {
    let mut command = Command::new("explorer");
    command.arg(format!("/select,{}", path.display()));
    command
}

#[cfg(not(any(target_os = "macos", windows)))]
fn platform_open_command(path: &Path) -> Command {
    let mut command = Command::new("xdg-open");
    command.arg(path);
    command
}

#[cfg(not(any(target_os = "macos", windows)))]
fn platform_reveal_command(path: &Path) -> Command {
    let target = path.parent().unwrap_or(path);
    platform_open_command(target)
}

#[cfg(not(target_os = "macos"))]
fn pause_capture(children: &mut [Child]) -> RecorderResult<()> {
    send_ffmpeg_interactive_command(children, b"p")
}

#[cfg(not(target_os = "macos"))]
fn resume_capture(children: &mut [Child]) -> RecorderResult<()> {
    send_ffmpeg_interactive_command(children, b"p")
}

#[cfg(not(target_os = "macos"))]
fn send_ffmpeg_interactive_command(children: &mut [Child], command: &[u8]) -> RecorderResult<()> {
    for child in children.iter_mut() {
        if let Some(stdin) = child.stdin.as_mut() {
            stdin.write_all(command)?;
        }
    }
    Ok(())
}

fn validate_options(options: &RecordingOptions) -> RecorderResult<()> {
    if !matches!(options.frame_rate, 24 | 30 | 60) {
        return Err(RecorderError::InvalidOptions(
            "frameRate must be 24, 30, or 60.".to_string(),
        ));
    }
    if options.countdown > 10 {
        return Err(RecorderError::InvalidOptions(
            "countdown must be 10 seconds or less.".to_string(),
        ));
    }
    if let Some(region) = &options.region {
        if region.width < 64.0 || region.height < 64.0 {
            return Err(RecorderError::InvalidOptions(
                "region must be at least 64 x 64 pixels.".to_string(),
            ));
        }
    }
    Ok(())
}

fn resolve_target(options: &RecordingOptions) -> RecorderResult<CaptureSource> {
    let target_id = options.target_id.as_deref().unwrap_or_default();
    platform::list_capture_sources()?
        .into_iter()
        .find(|source| source.id == target_id)
        .ok_or(RecorderError::MissingTarget)
}

fn stub_target(options: &RecordingOptions) -> CaptureSource {
    let frame = options.region.clone().unwrap_or(FrameRect {
        x: 0.0,
        y: 0.0,
        width: 1920.0,
        height: 1080.0,
    });
    CaptureSource {
        id: options
            .target_id
            .clone()
            .unwrap_or_else(|| "display:primary".to_string()),
        source_type: crate::models::CaptureSourceType::Display,
        title: "Test display".to_string(),
        subtitle: "Stub capture source".to_string(),
        native_id: Some(0),
        display_id: Some(0),
        frame,
        app_icon_path: None,
        preview_image_path: None,
    }
}

fn recording_bounds(options: &RecordingOptions, target: &CaptureSource) -> FrameRect {
    options
        .region
        .clone()
        .unwrap_or_else(|| target.frame.clone())
}

fn source_paths(manifest: &ProjectManifest) -> Vec<String> {
    manifest
        .sources
        .iter()
        .map(|source| source.relative_path.clone())
        .collect()
}

pub(crate) fn screen_source_path(project_path: &Path, manifest: &ProjectManifest) -> PathBuf {
    manifest
        .sources
        .iter()
        .find(|source| matches!(source.kind, crate::models::MediaSourceKind::Screen))
        .map(|source| project_path.join(&source.relative_path))
        .unwrap_or_else(|| project_path.join("media").join("screen.mp4"))
}

#[cfg(not(target_os = "macos"))]
fn finalize_capture(children: &mut Vec<Child>) -> RecorderResult<()> {
    for child in children.iter_mut() {
        if let Some(stdin) = child.stdin.as_mut() {
            let _ = stdin.write_all(b"q");
        }
    }

    for child in children.drain(..) {
        let output = child.wait_with_output()?;
        if !output.status.success() {
            return Err(RecorderError::Io(std::io::Error::new(
                std::io::ErrorKind::Other,
                format!(
                    "Recorder exited with status {}: {}",
                    output.status,
                    String::from_utf8_lossy(&output.stderr)
                ),
            )));
        }
    }
    Ok(())
}

fn validate_recorded_media(project_path: &Path, manifest: &ProjectManifest) -> RecorderResult<()> {
    for source in &manifest.sources {
        let path = project_path.join(&source.relative_path);
        let metadata = fs::metadata(&path)
            .map_err(|_| RecorderError::MissingMediaFile(source.relative_path.clone()))?;
        if metadata.len() == 0 {
            return Err(RecorderError::MissingMediaFile(
                source.relative_path.clone(),
            ));
        }
    }
    Ok(())
}

#[derive(Debug, Deserialize)]
struct NativeRecordingResult {
    duration: f64,
    width: u32,
    height: u32,
}

fn read_native_recording_result(
    project_path: &Path,
) -> RecorderResult<Option<NativeRecordingResult>> {
    let path = project_path.join("recording-result.json");
    if !path.is_file() {
        return Ok(None);
    }
    let json = fs::read_to_string(path)?;
    Ok(Some(serde_json::from_str(&json)?))
}

fn apply_native_recording_result(manifest: &mut ProjectManifest, result: &NativeRecordingResult) {
    for source in &mut manifest.sources {
        if matches!(source.kind, crate::models::MediaSourceKind::Screen) {
            source.width = Some(result.width);
            source.height = Some(result.height);
        }
    }
}

fn write_stub_media(project_path: &Path, manifest: &ProjectManifest) -> RecorderResult<()> {
    for source in &manifest.sources {
        let path = project_path.join(&source.relative_path);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(path, b"stub-media")?;
    }
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ExportRequest {
    pub(crate) name: String,
    pub(crate) size: ExportSize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ExportSize {
    Project,
    Source,
    Hd,
    UltraHd,
}

impl ExportRequest {
    fn parse(value: &str) -> RecorderResult<Self> {
        match value {
            "project" => Ok(Self {
                name: "project".into(),
                size: ExportSize::Project,
            }),
            "source" => Ok(Self {
                name: "source".to_string(),
                size: ExportSize::Source,
            }),
            "hd" => Ok(Self {
                name: "hd".to_string(),
                size: ExportSize::Hd,
            }),
            "ultraHD" | "ultra-hd" | "uhd" => Ok(Self {
                name: "ultraHD".to_string(),
                size: ExportSize::UltraHd,
            }),
            other => Err(RecorderError::UnsupportedExportPreset(other.to_string())),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn options() -> RecordingOptions {
        RecordingOptions {
            target_id: Some("display:primary".to_string()),
            frame_rate: 30,
            record_system_audio: true,
            record_microphone: false,
            record_camera: false,
            countdown: 0,
            region: None,
        }
    }

    #[test]
    fn stop_transitions_through_finalizing_and_returns_manifest() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let mut manager = SessionManager::stub_for_root(root.clone());
        let session = manager.start(options()).unwrap();

        assert_eq!(session.state, RecordingState::Recording);
        let manifest = manager.stop(session.id).unwrap();
        assert_eq!(manifest.schema_version, 1);
        assert!(manifest.duration >= 0.0);
        assert!(root.exists());

        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn stop_can_resume_a_session_already_marked_finalizing() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let mut manager = SessionManager::stub_for_root(root.clone());
        let session = manager.start(options()).unwrap();
        manager.sessions.get_mut(&session.id).unwrap().public.state = RecordingState::Finalizing;

        let manifest = manager.stop(session.id).unwrap();

        assert_eq!(manifest.schema_version, 1);
        assert!(!manager.sessions.contains_key(&session.id));
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn pause_and_resume_keep_session_addressable() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let mut manager = SessionManager::stub_for_root(root.clone());
        let session = manager.start(options()).unwrap();
        let paused = manager.pause(session.id).unwrap();
        let resumed = manager.resume(session.id).unwrap();

        assert_eq!(paused.state, RecordingState::Paused);
        assert_eq!(resumed.state, RecordingState::Recording);

        let _ = manager.stop(session.id);
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn rejects_concurrent_recordings() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let mut manager = SessionManager::stub_for_root(root.clone());
        let first = manager.start(options()).unwrap();
        let error = manager.start(options()).unwrap_err();

        assert!(matches!(error, RecorderError::ActiveRecordingExists));

        let _ = manager.stop(first.id);
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn rejects_invalid_region_and_frame_rate() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let mut manager = SessionManager::stub_for_root(root.clone());
        let mut bad_region = options();
        bad_region.region = Some(FrameRect {
            x: 0.0,
            y: 0.0,
            width: 12.0,
            height: 12.0,
        });
        let error = manager.start(bad_region).unwrap_err();
        assert!(matches!(error, RecorderError::InvalidOptions(_)));

        let mut bad_frame_rate = options();
        bad_frame_rate.frame_rate = 144;
        let error = manager.start(bad_frame_rate).unwrap_err();
        assert!(matches!(error, RecorderError::InvalidOptions(_)));

        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn stop_clears_recovery_journal() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let mut manager = SessionManager::stub_for_root(root.clone());
        let session = manager.start(options()).unwrap();
        let project_path = PathBuf::from(&session.project_path);
        assert!(project_path.join("recovery.json").is_file());

        manager.stop(session.id).unwrap();
        assert!(!project_path.join("recovery.json").exists());

        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn export_preset_names_are_normalized_and_invalid_values_fail() {
        assert_eq!(ExportRequest::parse("source").unwrap().name, "source");
        assert_eq!(ExportRequest::parse("hd").unwrap().name, "hd");
        assert_eq!(ExportRequest::parse("uhd").unwrap().name, "ultraHD");

        let error = ExportRequest::parse("tiny").unwrap_err();
        assert!(matches!(error, RecorderError::UnsupportedExportPreset(_)));
    }

    #[test]
    fn screen_source_path_supports_legacy_macos_source_directory() {
        let mut manifest = ProjectManifest::new("Legacy macOS");
        manifest.sources.push(crate::models::MediaSource {
            id: Uuid::new_v4(),
            kind: crate::models::MediaSourceKind::Screen,
            relative_path: "Sources/screen.mov".to_string(),
            duration: 1.0,
            width: Some(1920),
            height: Some(1080),
            frame_rate: Some(30.0),
        });

        assert_eq!(
            screen_source_path(Path::new("/tmp/example.svproject"), &manifest),
            PathBuf::from("/tmp/example.svproject/Sources/screen.mov")
        );
    }

    #[test]
    fn reveal_project_video_reports_missing_source_video() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let project_path = root.join("missing-video.svproject");
        fs::create_dir_all(project_path.join("media")).unwrap();
        let store = ProjectStore::for_root(root.clone());
        let manifest = ProjectManifest::new("Missing Video");
        store.save(&manifest, &project_path).unwrap();

        let error = reveal_project_video(&project_path).unwrap_err();

        match error {
            RecorderError::Io(io_error) => {
                assert_eq!(io_error.kind(), std::io::ErrorKind::NotFound);
                assert!(io_error
                    .to_string()
                    .contains("Recorded video was not found"));
            }
            other => panic!("unexpected error: {other}"),
        }
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn native_recording_result_updates_duration_and_screen_dimensions() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let mut manager = SessionManager::stub_for_root(root.clone());
        let session = manager.start(options()).unwrap();
        let project_path = PathBuf::from(&session.project_path);
        fs::write(
            project_path.join("recording-result.json"),
            r#"{"duration":2.5,"width":3024,"height":1964}"#,
        )
        .unwrap();

        let manifest = manager.stop(session.id).unwrap();
        let screen = manifest
            .sources
            .iter()
            .find(|source| matches!(source.kind, crate::models::MediaSourceKind::Screen))
            .unwrap();

        assert_eq!(manifest.duration, 2.5);
        assert_eq!(screen.width, Some(3024));
        assert_eq!(screen.height, Some(1964));
        assert!(!project_path.join("recording-result.json").exists());
        let _ = std::fs::remove_dir_all(root);
    }

    #[test]
    fn camera_capture_adds_camera_source_when_backend_supports_it() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let mut manager = SessionManager::stub_for_root(root.clone());
        let mut next_options = options();
        next_options.record_camera = true;
        let session = manager.start(next_options).unwrap();
        let manifest = manager.stop(session.id).unwrap();

        assert!(manifest
            .sources
            .iter()
            .any(|source| matches!(source.kind, crate::models::MediaSourceKind::Camera)));
        let _ = std::fs::remove_dir_all(root);
    }

    #[cfg(not(any(windows, target_os = "macos")))]
    #[test]
    fn unsupported_native_backend_does_not_create_empty_project() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let mut manager = SessionManager::native_for_root(root.clone());
        let error = manager.start(options()).unwrap_err();

        assert!(matches!(error, RecorderError::UnsupportedPlatform));
        assert!(!root.exists());
    }
}
