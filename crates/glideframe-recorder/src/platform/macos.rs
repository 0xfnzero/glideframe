use crate::{
    models::{AudioDevice, CameraDevice, CaptureSource, ProjectManifest, RecordingOptions},
    platform::RecorderBackend,
    recorder::{RecorderError, RecorderResult},
};
use libloading::Library;
use serde::{de::DeserializeOwned, Serialize};
use std::{
    ffi::{c_char, CStr, CString},
    path::{Path, PathBuf},
    process::Child,
    sync::OnceLock,
};

pub struct MacosBackend;
impl RecorderBackend for MacosBackend {
    fn list_capture_sources() -> RecorderResult<Vec<CaptureSource>> {
        call("list-capture-sources", &())
    }
    fn list_audio_devices() -> RecorderResult<Vec<AudioDevice>> {
        call("list-audio-devices", &())
    }
    fn list_camera_devices() -> RecorderResult<Vec<CameraDevice>> {
        call("list-camera-devices", &())
    }
    fn ensure_capture_available() -> RecorderResult<()> {
        bridge().map(|_| ())
    }
    fn start_capture(
        options: &RecordingOptions,
        target: &CaptureSource,
        _: &ProjectManifest,
        project_path: &Path,
    ) -> RecorderResult<Vec<Child>> {
        let _: bool = call(
            "start-recording",
            &serde_json::json!({"options": options, "target": target, "projectPath": project_path}),
        )?;
        Ok(Vec::new())
    }
}
pub fn screen_capture_access_status() -> RecorderResult<bool> {
    call("screen-capture-status", &())
}
pub fn request_screen_capture_access() -> RecorderResult<bool> {
    call("request-screen-capture-access", &())
}
pub fn pause_capture() -> RecorderResult<()> {
    call::<bool>("pause-recording", &()).map(|_| ())
}
pub fn resume_capture() -> RecorderResult<()> {
    call::<bool>("resume-recording", &()).map(|_| ())
}
pub fn finish_capture(project_path: &Path) -> RecorderResult<()> {
    let result: serde_json::Value = call("stop-recording", &())?;
    std::fs::write(
        project_path.join("recording-result.json"),
        serde_json::to_vec(&result)?,
    )?;
    Ok(())
}
pub fn export_media(project_path: &Path, preset: &str, destination: &Path) -> RecorderResult<()> {
    call::<String>("export-project", &serde_json::json!({"projectPath": project_path, "preset": preset, "destination": destination})).map(|_| ())
}
fn bridge() -> RecorderResult<&'static Library> {
    static BRIDGE: OnceLock<Result<Library, String>> = OnceLock::new();
    BRIDGE.get_or_init(|| {
        let executable = std::env::current_exe().map_err(|error| error.to_string())?;
        let directory = executable.parent().ok_or("Could not locate the application directory")?;
        let bundled = directory.join("../Resources/libGlideFrameCaptureBridge.dylib");
        let path = if bundled.is_file() { bundled } else if executable.ancestors().any(|path| path.extension().is_some_and(|ext| ext == "app")) {
            return Err("The application is missing its capture bridge. Rebuild or reinstall GlideFrame Desktop.".into());
        } else {
            PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../.build/release/libGlideFrameCaptureBridge.dylib")
        };
        // Keep Swift tasks and capture sessions alive for the entire app lifetime.
        unsafe { Library::new(path) }.map_err(|error| error.to_string())
    }).as_ref().map_err(|error| RecorderError::CaptureBackendUnavailable(error.clone()))
}
pub(crate) fn call<T: DeserializeOwned>(
    command: &str,
    arguments: &impl Serialize,
) -> RecorderResult<T> {
    let library = bridge()?;
    let command = CString::new(command)
        .map_err(|error| RecorderError::CaptureBackendUnavailable(error.to_string()))?;
    let arguments = CString::new(serde_json::to_string(arguments)?)
        .map_err(|error| RecorderError::CaptureBackendUnavailable(error.to_string()))?;
    unsafe {
        let invoke = library
            .get::<unsafe extern "C" fn(*const c_char, *const c_char) -> *mut c_char>(
                b"glideframe_bridge_call\0",
            )
            .map_err(|error| RecorderError::CaptureBackendUnavailable(error.to_string()))?;
        let release = library
            .get::<unsafe extern "C" fn(*mut c_char)>(b"glideframe_bridge_free\0")
            .map_err(|error| RecorderError::CaptureBackendUnavailable(error.to_string()))?;
        let pointer = invoke(command.as_ptr(), arguments.as_ptr());
        if pointer.is_null() {
            return Err(RecorderError::CaptureBackendUnavailable(
                "Capture bridge returned no response.".into(),
            ));
        }
        let bytes = CStr::from_ptr(pointer).to_bytes().to_vec();
        release(pointer);
        let response: serde_json::Value = serde_json::from_slice(&bytes)?;
        if let Some(error) = response.get("error").and_then(|value| value.as_str()) {
            return Err(RecorderError::CaptureBackendUnavailable(error.into()));
        }
        Ok(serde_json::from_value(response["value"].clone())?)
    }
}
