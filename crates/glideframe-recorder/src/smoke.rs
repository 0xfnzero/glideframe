use crate::{
    models::RecordingOptions,
    platform,
    recorder::{RecorderResult, SessionManager},
};
use std::{path::PathBuf, time::Duration};

pub fn run() -> RecorderResult<()> {
    let root = std::env::args()
        .nth(2)
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            std::env::temp_dir().join(format!("glideframe-smoke-{}", uuid::Uuid::new_v4()))
        });
    let target = platform::list_capture_sources()?
        .into_iter()
        .next()
        .ok_or(crate::recorder::RecorderError::MissingTarget)?;
    let mut manager = SessionManager::native_for_root(root);
    let session = manager.start(RecordingOptions {
        target_id: Some(target.id),
        frame_rate: 30,
        record_system_audio: false,
        record_microphone: false,
        record_camera: false,
        countdown: 0,
        region: None,
    })?;
    std::thread::sleep(Duration::from_secs(2));
    manager.pause(session.id)?;
    std::thread::sleep(Duration::from_secs(1));
    manager.resume(session.id)?;
    std::thread::sleep(Duration::from_secs(2));
    let manifest = manager.stop(session.id)?;
    assert!(manifest.duration >= 3.0, "The recording is too short");
    let exported =
        crate::recorder::export_project(&PathBuf::from(&session.project_path), "source")?;
    println!(
        "{}",
        serde_json::json!({"projectPath": session.project_path, "duration": manifest.duration, "exportPath": exported})
    );
    Ok(())
}
