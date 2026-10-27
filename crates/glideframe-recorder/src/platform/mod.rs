use std::{path::Path, process::Child};

use crate::{
    models::{
        AudioDevice, AudioDeviceKind, CameraDevice, CaptureSource, ProjectManifest,
        RecordingOptions,
    },
    recorder::{ExportRequest, RecorderResult},
};

#[cfg(not(target_os = "macos"))]
use crate::recorder::RecorderError;
#[cfg(any(not(target_os = "macos"), test))]
use std::process::Command;
#[cfg(not(target_os = "macos"))]
use std::process::Stdio;

#[cfg(target_os = "macos")]
pub(crate) mod macos;
#[cfg(windows)]
mod windows;

#[cfg(windows)]
pub fn run_recording_worker() -> RecorderResult<()> {
    windows::run_recording_worker()
}

pub trait RecorderBackend {
    fn list_capture_sources() -> RecorderResult<Vec<CaptureSource>>;
    fn list_audio_devices() -> RecorderResult<Vec<AudioDevice>>;
    fn list_camera_devices() -> RecorderResult<Vec<CameraDevice>>;
    fn ensure_capture_available() -> RecorderResult<()>;
    fn start_capture(
        options: &RecordingOptions,
        target: &CaptureSource,
        manifest: &ProjectManifest,
        project_path: &Path,
    ) -> RecorderResult<Vec<Child>>;
}

pub fn list_capture_sources() -> RecorderResult<Vec<CaptureSource>> {
    #[cfg(target_os = "macos")]
    {
        macos::MacosBackend::list_capture_sources()
    }
    #[cfg(windows)]
    {
        windows::WindowsBackend::list_capture_sources()
    }
    #[cfg(not(any(target_os = "macos", windows)))]
    {
        Ok(Vec::new())
    }
}

pub fn list_audio_devices() -> RecorderResult<Vec<AudioDevice>> {
    #[cfg(target_os = "macos")]
    {
        macos::MacosBackend::list_audio_devices()
    }
    #[cfg(windows)]
    {
        windows::WindowsBackend::list_audio_devices()
    }
    #[cfg(not(any(target_os = "macos", windows)))]
    {
        Ok(default_audio_devices())
    }
}

pub fn list_camera_devices() -> RecorderResult<Vec<CameraDevice>> {
    #[cfg(target_os = "macos")]
    {
        macos::MacosBackend::list_camera_devices()
    }
    #[cfg(windows)]
    {
        windows::WindowsBackend::list_camera_devices()
    }
    #[cfg(not(any(target_os = "macos", windows)))]
    {
        Ok(Vec::new())
    }
}

pub fn ensure_capture_available() -> RecorderResult<()> {
    #[cfg(target_os = "macos")]
    {
        macos::MacosBackend::ensure_capture_available()
    }
    #[cfg(windows)]
    {
        windows::WindowsBackend::ensure_capture_available()
    }
    #[cfg(not(any(target_os = "macos", windows)))]
    {
        Err(RecorderError::UnsupportedPlatform)
    }
}

pub fn screen_capture_access_status() -> RecorderResult<bool> {
    #[cfg(target_os = "macos")]
    {
        macos::screen_capture_access_status()
    }
    #[cfg(not(target_os = "macos"))]
    {
        Ok(true)
    }
}

pub fn request_screen_capture_access() -> RecorderResult<bool> {
    #[cfg(target_os = "macos")]
    {
        macos::request_screen_capture_access()
    }
    #[cfg(not(target_os = "macos"))]
    {
        Ok(true)
    }
}

pub fn start_capture(
    options: &RecordingOptions,
    target: &CaptureSource,
    manifest: &ProjectManifest,
    project_path: &Path,
) -> RecorderResult<Vec<Child>> {
    #[cfg(target_os = "macos")]
    {
        macos::MacosBackend::start_capture(options, target, manifest, project_path)
    }
    #[cfg(windows)]
    {
        windows::WindowsBackend::start_capture(options, target, manifest, project_path)
    }
    #[cfg(not(any(target_os = "macos", windows)))]
    {
        let _ = (options, target, manifest, project_path);
        Err(RecorderError::UnsupportedPlatform)
    }
}

#[cfg(target_os = "macos")]
pub fn pause_capture() -> RecorderResult<()> {
    macos::pause_capture()
}
#[cfg(target_os = "macos")]
pub fn resume_capture() -> RecorderResult<()> {
    macos::resume_capture()
}
#[cfg(target_os = "macos")]
pub fn finish_capture(project_path: &Path) -> RecorderResult<()> {
    macos::finish_capture(project_path)
}

pub(crate) fn export_media(
    project_path: &Path,
    manifest: &ProjectManifest,
    preset: &ExportRequest,
    destination: &Path,
) -> RecorderResult<()> {
    #[cfg(target_os = "macos")]
    {
        let _ = manifest;
        macos::export_media(project_path, &preset.name, destination)
    }
    #[cfg(not(target_os = "macos"))]
    {
        crate::export::export(project_path, manifest, preset, destination)
    }
}

#[cfg(windows)]
pub(crate) fn wait_for_recording_ready(
    mut child: Child,
    project_path: &Path,
) -> RecorderResult<Vec<Child>> {
    use std::{
        io::Read,
        time::{Duration, Instant},
    };
    let ready = project_path.join("recording-ready.json");
    let deadline = Instant::now() + Duration::from_secs(45);
    loop {
        if ready.is_file() {
            let _ = std::fs::remove_file(ready);
            return Ok(vec![child]);
        }
        if let Some(status) = child.try_wait()? {
            let mut message = String::new();
            if let Some(mut stderr) = child.stderr.take() {
                let _ = stderr.read_to_string(&mut message);
            }
            return Err(RecorderError::Io(std::io::Error::other(format!(
                "Recorder could not start ({status}): {}",
                message.trim()
            ))));
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            let _ = child.wait();
            return Err(RecorderError::Io(std::io::Error::other("The recorder did not become ready. Check screen, microphone and camera permissions, then retry.")));
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

#[allow(dead_code)]
pub(crate) fn default_audio_devices() -> Vec<AudioDevice> {
    vec![
        AudioDevice {
            id: "system:default".to_string(),
            name: "Default system output".to_string(),
            is_default: true,
            kind: AudioDeviceKind::SystemAudio,
        },
        AudioDevice {
            id: "microphone:default".to_string(),
            name: "Default microphone".to_string(),
            is_default: true,
            kind: AudioDeviceKind::Microphone,
        },
    ]
}

#[cfg(not(target_os = "macos"))]
pub(crate) fn ensure_ffmpeg_available() -> RecorderResult<()> {
    if !ffmpeg_command()
        .arg("-version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|status| status.success())
    {
        return Err(RecorderError::MissingFfmpeg);
    }
    Ok(())
}

#[cfg(any(not(target_os = "macos"), test))]
pub(crate) fn ffmpeg_command() -> Command {
    #[cfg(windows)]
    {
        let bundled = std::env::current_exe().ok().and_then(|path| {
            path.parent()
                .map(|parent| parent.join("glideframe-ffmpeg.exe"))
        });
        let program = bundled
            .filter(|path| path.is_file())
            .map(|path| path.into_os_string())
            .unwrap_or_else(|| "ffmpeg.exe".into());
        windows::hidden_command(program)
    }
    #[cfg(not(windows))]
    {
        let path = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .into_iter()
            .find(|path| Path::new(path).is_file())
            .unwrap_or("ffmpeg");
        Command::new(path)
    }
}

#[cfg(any(windows, test))]
pub(crate) fn ffprobe_command() -> Command {
    #[cfg(windows)]
    {
        let bundled = std::env::current_exe().ok().and_then(|path| {
            path.parent()
                .map(|parent| parent.join("glideframe-ffprobe.exe"))
        });
        let program = bundled
            .filter(|path| path.is_file())
            .map(|path| path.into_os_string())
            .unwrap_or_else(|| "ffprobe.exe".into());
        windows::hidden_command(program)
    }
    #[cfg(not(windows))]
    {
        Command::new("ffprobe")
    }
}
