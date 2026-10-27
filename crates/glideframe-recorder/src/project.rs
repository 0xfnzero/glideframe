use std::{
    fs,
    io::ErrorKind,
    path::{Path, PathBuf},
};

use chrono::{Datelike, Local, Utc};
use thiserror::Error;
use uuid::Uuid;

use crate::models::{
    CaptureSource, MediaSource, MediaSourceKind, MediaTrack, ProjectManifest, ProjectSummary,
    RecordingOptions, RecoveryJournal, RecoveryState,
};

#[derive(Debug, Error)]
pub enum ProjectError {
    #[error("Could not locate the system Videos directory.")]
    MissingVideosDirectory,
    #[error("Project path must be a .svproject directory: {0}")]
    InvalidProjectPath(String),
    #[error("Unsupported project schema version {0}.")]
    UnsupportedSchema(u32),
    #[error("Invalid project edit: {0}")]
    InvalidEdit(String),
    #[error("Could not create a unique recording project directory after multiple attempts.")]
    UniqueProjectPathExhausted,
    #[error("{0}")]
    Io(#[from] std::io::Error),
    #[error("{0}")]
    Json(#[from] serde_json::Error),
}

#[derive(Debug, Clone)]
pub struct ProjectStore {
    root: PathBuf,
}

impl ProjectStore {
    pub fn default() -> Result<Self, ProjectError> {
        Ok(Self {
            root: Self::default_root_path()?,
        })
    }

    pub fn for_root(root: PathBuf) -> Self {
        Self { root }
    }

    pub fn default_root_path() -> Result<PathBuf, ProjectError> {
        let videos = dirs::video_dir().ok_or(ProjectError::MissingVideosDirectory)?;
        Ok(videos.join("GlideFrame").join("Projects"))
    }

    pub fn create_recording_project(
        &self,
        options: &RecordingOptions,
        target: &CaptureSource,
    ) -> Result<(ProjectManifest, PathBuf), ProjectError> {
        let project_path = self.create_unique_project_directory()?;

        fs::create_dir(project_path.join("media"))?;
        fs::create_dir(project_path.join("exports"))?;

        let mut manifest = ProjectManifest::new("Untitled Recording");
        let screen_source_id = Uuid::new_v4();
        manifest.sources.push(MediaSource {
            id: screen_source_id,
            kind: MediaSourceKind::Screen,
            relative_path: "media/screen.mp4".to_string(),
            duration: 0.0,
            width: Some(recording_width(options, target)),
            height: Some(recording_height(options, target)),
            frame_rate: Some(options.frame_rate as f64),
        });
        manifest.tracks.push(MediaTrack {
            id: Uuid::new_v4(),
            source_id: screen_source_id,
            kind: MediaSourceKind::Screen,
            is_enabled: true,
            volume: 1.0,
        });

        if options.record_microphone {
            let source_id = Uuid::new_v4();
            manifest.sources.push(MediaSource {
                id: source_id,
                kind: MediaSourceKind::Microphone,
                relative_path: "media/microphone.wav".to_string(),
                duration: 0.0,
                width: None,
                height: None,
                frame_rate: None,
            });
            manifest.tracks.push(MediaTrack {
                id: Uuid::new_v4(),
                source_id,
                kind: MediaSourceKind::Microphone,
                is_enabled: true,
                volume: 1.0,
            });
        }

        if options.record_system_audio {
            let source_id = Uuid::new_v4();
            manifest.sources.push(MediaSource {
                id: source_id,
                kind: MediaSourceKind::SystemAudio,
                relative_path: system_audio_relative_path().to_string(),
                duration: 0.0,
                width: None,
                height: None,
                frame_rate: None,
            });
            manifest.tracks.push(MediaTrack {
                id: Uuid::new_v4(),
                source_id,
                kind: MediaSourceKind::SystemAudio,
                is_enabled: true,
                volume: 1.0,
            });
        }

        if options.record_camera {
            let source_id = Uuid::new_v4();
            manifest.sources.push(MediaSource {
                id: source_id,
                kind: MediaSourceKind::Camera,
                relative_path: "media/camera.mp4".to_string(),
                duration: 0.0,
                width: None,
                height: None,
                frame_rate: Some(options.frame_rate as f64),
            });
            manifest.tracks.push(MediaTrack {
                id: Uuid::new_v4(),
                source_id,
                kind: MediaSourceKind::Camera,
                is_enabled: true,
                volume: 1.0,
            });
        }

        self.save(&manifest, &project_path)?;
        Ok((manifest, project_path))
    }

    fn create_unique_project_directory(&self) -> Result<PathBuf, ProjectError> {
        let now = Local::now();
        let day = format!("{:04}-{:02}-{:02}", now.year(), now.month(), now.day());
        let day_path = self.root.join(day);
        fs::create_dir_all(&day_path)?;

        for _ in 0..64 {
            let now = Local::now();
            let short_id = Uuid::new_v4()
                .simple()
                .to_string()
                .chars()
                .take(8)
                .collect::<String>();
            let project_name = format!(
                "recording-{}-{}.svproject",
                now.format("%Y%m%d-%H%M%S"),
                short_id
            );
            let project_path = day_path.join(project_name);

            match fs::create_dir(&project_path) {
                Ok(()) => return Ok(project_path),
                Err(error) if error.kind() == ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error.into()),
            }
        }

        Err(ProjectError::UniqueProjectPathExhausted)
    }

    pub fn save(
        &self,
        manifest: &ProjectManifest,
        project_path: &Path,
    ) -> Result<(), ProjectError> {
        validate_project_path(project_path)?;
        let mut copy = manifest.clone();
        copy.updated_at = Utc::now();
        let json = serde_json::to_string_pretty(&copy)?;
        let destination = project_path.join("manifest.json");
        let temporary = project_path.join(format!("manifest.{}.tmp", Uuid::new_v4()));
        fs::write(&temporary, json)?;
        replace_file(&temporary, &destination)?;
        Ok(())
    }

    pub fn load(&self, project_path: &Path) -> Result<ProjectManifest, ProjectError> {
        validate_project_path(project_path)?;
        let json = fs::read_to_string(project_path.join("manifest.json"))?;
        let manifest: ProjectManifest = serde_json::from_str(&json)?;
        if manifest.schema_version > 1 {
            return Err(ProjectError::UnsupportedSchema(manifest.schema_version));
        }
        Ok(manifest)
    }

    pub fn save_edits(
        &self,
        project_path: &Path,
        edits: crate::models::ProjectEdits,
    ) -> Result<ProjectManifest, ProjectError> {
        let current = self.load(project_path)?;
        if !(0.0..=140.0).contains(&edits.canvas.padding)
            || !(0.0..=40.0).contains(&edits.canvas.corner_radius)
            || edits.export_preset.width < 2
            || edits.export_preset.height < 2
            || edits.export_preset.width > 7680
            || edits.export_preset.height > 7680
            || ![24, 30, 60].contains(&edits.export_preset.frame_rate)
            || edits.edit_graph.clips.iter().any(|clip| {
                let range = &clip.source_range;
                range.start < 0.0
                    || range.duration <= 0.0
                    || range.start + range.duration > current.duration + 0.05
            })
        {
            return Err(ProjectError::InvalidEdit(
                "Canvas, export dimensions or trim range is out of bounds.".into(),
            ));
        }
        // Merge into the original JSON so newer/native metadata survives an edit.
        let mut document: serde_json::Value =
            serde_json::from_str(&fs::read_to_string(project_path.join("manifest.json"))?)?;
        merge_json(&mut document, serde_json::to_value(edits)?);
        document["updatedAt"] = serde_json::to_value(Utc::now().to_rfc3339())?;
        let manifest: ProjectManifest = serde_json::from_value(document.clone())?;
        let temporary = project_path.join(format!("manifest.{}.tmp", Uuid::new_v4()));
        fs::write(&temporary, serde_json::to_string_pretty(&document)?)?;
        replace_file(&temporary, &project_path.join("manifest.json"))?;
        Ok(manifest)
    }

    pub fn list_projects(&self) -> Result<Vec<ProjectSummary>, ProjectError> {
        if !self.root.exists() {
            return Ok(Vec::new());
        }

        let mut projects = Vec::new();
        let default_root = Self::default_root_path()?;
        let search_root = if self.root == default_root {
            self.root.parent().unwrap_or(&self.root)
        } else {
            &self.root
        };
        for path in package_paths(search_root, 2)? {
            if let Ok(manifest) = self.load(&path) {
                projects.push(ProjectSummary {
                    id: manifest.id,
                    title: manifest.title,
                    updated_at: manifest.updated_at,
                    duration: manifest.duration,
                    package_path: path.display().to_string(),
                });
            }
        }
        projects.sort_by(|lhs, rhs| rhs.updated_at.cmp(&lhs.updated_at));
        Ok(projects)
    }

    pub fn write_recovery_journal(
        &self,
        journal: &RecoveryJournal,
        project_path: &Path,
    ) -> Result<(), ProjectError> {
        validate_project_path(project_path)?;
        let json = serde_json::to_string_pretty(journal)?;
        fs::write(project_path.join("recovery.json"), json)?;
        Ok(())
    }

    pub fn clear_recovery_journal(&self, project_path: &Path) -> Result<(), ProjectError> {
        validate_project_path(project_path)?;
        let path = project_path.join("recovery.json");
        if path.exists() {
            fs::remove_file(path)?;
        }
        Ok(())
    }

    pub fn recover_interrupted_projects(&self) -> Result<Vec<ProjectSummary>, ProjectError> {
        let mut recovered = Vec::new();
        for project in self.list_projects()? {
            let package_path = PathBuf::from(&project.package_path);
            let journal_path = package_path.join("recovery.json");
            if !journal_path.exists() {
                continue;
            }
            let json = fs::read_to_string(&journal_path)?;
            let mut journal: RecoveryJournal = serde_json::from_str(&json)?;
            if journal.owner_process_id.is_some_and(process_is_alive) {
                continue;
            }
            journal.state = RecoveryState::Interrupted;
            self.write_recovery_journal(&journal, &package_path)?;
            recovered.push(project);
        }
        Ok(recovered)
    }

    pub fn remove_project(&self, project_path: &Path) -> Result<(), ProjectError> {
        validate_project_path(project_path)?;
        if project_path.exists() {
            fs::remove_dir_all(project_path)?;
        }
        Ok(())
    }
}

fn merge_json(destination: &mut serde_json::Value, source: serde_json::Value) {
    if let (Some(destination), Some(source)) = (destination.as_object_mut(), source.as_object()) {
        for (key, value) in source {
            merge_json(
                destination
                    .entry(key.clone())
                    .or_insert(serde_json::Value::Null),
                value.clone(),
            );
        }
    } else {
        *destination = source;
    }
}

// Journals from the other desktop client are not interrupted while its process lives.
fn process_is_alive(pid: u32) -> bool {
    if pid == 0 || pid > i32::MAX as u32 {
        return false;
    }
    #[cfg(target_os = "macos")]
    {
        unsafe { libc::kill(pid as i32, 0) == 0 || *libc::__error() == libc::EPERM }
    }
    #[cfg(windows)]
    {
        use windows::Win32::{
            Foundation::CloseHandle,
            System::Threading::{
                GetExitCodeProcess, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION,
            },
        };
        unsafe {
            let Ok(handle) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) else {
                return false;
            };
            let mut code = 0;
            let alive = GetExitCodeProcess(handle, &mut code).is_ok() && code == 259;
            let _ = CloseHandle(handle);
            alive
        }
    }
    #[cfg(not(any(target_os = "macos", windows)))]
    {
        pid == std::process::id()
    }
}

fn package_paths(root: &Path, depth: usize) -> Result<Vec<PathBuf>, std::io::Error> {
    let mut paths = Vec::new();
    for entry in fs::read_dir(root)? {
        let entry = entry?;
        if !entry.file_type()?.is_dir() {
            continue;
        }
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) == Some("svproject") {
            paths.push(path);
        } else if depth > 0 {
            paths.extend(package_paths(&path, depth - 1)?);
        }
    }
    Ok(paths)
}

fn recording_width(options: &RecordingOptions, target: &CaptureSource) -> u32 {
    options
        .region
        .as_ref()
        .map(|rect| rect.width)
        .unwrap_or(target.frame.width)
        .round()
        .max(0.0) as u32
}

fn recording_height(options: &RecordingOptions, target: &CaptureSource) -> u32 {
    options
        .region
        .as_ref()
        .map(|rect| rect.height)
        .unwrap_or(target.frame.height)
        .round()
        .max(0.0) as u32
}

fn system_audio_relative_path() -> &'static str {
    #[cfg(target_os = "macos")]
    {
        "media/screen.mp4"
    }
    #[cfg(not(target_os = "macos"))]
    {
        "media/system-audio.wav"
    }
}

fn validate_project_path(project_path: &Path) -> Result<(), ProjectError> {
    if project_path.extension().and_then(|value| value.to_str()) != Some("svproject") {
        return Err(ProjectError::InvalidProjectPath(
            project_path.display().to_string(),
        ));
    }
    Ok(())
}

fn replace_file(temporary: &Path, destination: &Path) -> Result<(), ProjectError> {
    if !destination.exists() {
        fs::rename(temporary, destination)?;
        return Ok(());
    }

    let backup = destination.with_extension(format!(
        "{}.bak",
        destination
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or("json")
    ));
    if backup.exists() {
        fs::remove_file(&backup)?;
    }
    fs::rename(destination, &backup)?;
    match fs::rename(temporary, destination) {
        Ok(()) => {
            let _ = fs::remove_file(backup);
            Ok(())
        }
        Err(error) => {
            let _ = fs::rename(&backup, destination);
            Err(ProjectError::Io(error))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::{CaptureSourceType, FrameRect};

    #[test]
    fn editor_preserves_native_metadata_and_rejects_invalid_trim() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let store = ProjectStore::for_root(root.clone());
        let (mut manifest, path) = store
            .create_recording_project(&options(), &target())
            .unwrap();
        manifest.duration = 10.0;
        store.save(&manifest, &path).unwrap();
        let mut document: serde_json::Value =
            serde_json::from_str(&fs::read_to_string(path.join("manifest.json")).unwrap()).unwrap();
        document["nativeMetadata"] = serde_json::json!({"version": 2});
        document["canvas"]["futureOption"] = serde_json::json!(true);
        fs::write(
            path.join("manifest.json"),
            serde_json::to_vec(&document).unwrap(),
        )
        .unwrap();
        let mut edits = crate::models::ProjectEdits {
            canvas: manifest.canvas,
            edit_graph: manifest.edit_graph,
            export_preset: manifest.export_preset,
        };
        edits.canvas.background = crate::models::CanvasBackground::Mint;
        edits.edit_graph.clips.push(crate::models::ClipEdit {
            id: Uuid::new_v4(),
            source_range: crate::models::MediaTimeRange {
                start: 2.0,
                duration: 5.0,
            },
            is_removed: false,
        });
        store.save_edits(&path, edits.clone()).unwrap();
        let saved = fs::read_to_string(path.join("manifest.json")).unwrap();
        let document: serde_json::Value = serde_json::from_str(&saved).unwrap();
        assert_eq!(document["nativeMetadata"]["version"], 2);
        assert_eq!(document["canvas"]["futureOption"], true);
        assert_eq!(document["canvas"]["background"], "mint");
        edits.edit_graph.clips[0].source_range.duration = 20.0;
        assert!(store.save_edits(&path, edits).is_err());
        assert_eq!(
            saved,
            fs::read_to_string(path.join("manifest.json")).unwrap()
        );
        fs::remove_dir_all(root).unwrap();
    }

    fn target() -> CaptureSource {
        CaptureSource {
            id: "display:primary".to_string(),
            source_type: CaptureSourceType::Display,
            title: "Primary display".to_string(),
            subtitle: "Test display".to_string(),
            native_id: Some(0),
            display_id: Some(0),
            frame: FrameRect {
                x: 0.0,
                y: 0.0,
                width: 1920.0,
                height: 1080.0,
            },
            app_icon_path: None,
            preview_image_path: None,
        }
    }

    fn options() -> RecordingOptions {
        RecordingOptions {
            target_id: Some("display:primary".to_string()),
            frame_rate: 30,
            record_system_audio: true,
            record_microphone: true,
            record_camera: false,
            countdown: 0,
            region: Some(FrameRect {
                x: 10.0,
                y: 20.0,
                width: 1280.0,
                height: 720.0,
            }),
        }
    }

    #[test]
    fn creates_unique_svproject_directories() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let store = ProjectStore::for_root(root.clone());
        let (_, first) = store
            .create_recording_project(&options(), &target())
            .unwrap();
        let (_, second) = store
            .create_recording_project(&options(), &target())
            .unwrap();

        assert_ne!(first, second);
        assert_eq!(
            first.extension().and_then(|value| value.to_str()),
            Some("svproject")
        );
        let expected_day = Local::now().format("%Y-%m-%d").to_string();
        assert_eq!(
            first
                .parent()
                .and_then(|path| path.file_name())
                .and_then(|name| name.to_str()),
            Some(expected_day.as_str())
        );
        assert!(first.join("media").is_dir());
        assert!(first.join("manifest.json").is_file());

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn manifest_json_uses_swift_compatible_field_names() {
        let manifest = ProjectManifest::new("Compatibility");
        let json = serde_json::to_string(&manifest).unwrap();
        assert!(json.contains("schemaVersion"));
        assert!(json.contains("createdAt"));
        assert!(json.contains("editGraph"));
        assert!(json.contains("exportPreset"));
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert!(!value["createdAt"].as_str().unwrap().contains('.'));
        assert!(!value["updatedAt"].as_str().unwrap().contains('.'));
    }

    #[test]
    fn reads_legacy_swift_acronym_keys() {
        let recovery: RecoveryJournal = serde_json::from_str(
            r#"{
              "projectID": "68127C61-110A-49FC-8AB2-B7D625E6C980",
              "state": "interrupted",
              "startedAt": "2026-08-17T17:15:05Z",
              "sourcePaths": ["Sources"]
            }"#,
        )
        .unwrap();
        assert_eq!(
            recovery.project_id.to_string(),
            "68127c61-110a-49fc-8ab2-b7d625e6c980"
        );

        let track: MediaTrack = serde_json::from_str(
            r#"{
              "id": "FA8DA3A8-769C-41B9-97EC-217B6E91AAD3",
              "sourceID": "6FB391EA-F962-4B30-85C3-1B53300A25ED",
              "kind": "screen",
              "isEnabled": true,
              "volume": 1
            }"#,
        )
        .unwrap();
        assert_eq!(
            track.source_id.to_string(),
            "6fb391ea-f962-4b30-85c3-1b53300a25ed"
        );
    }

    #[test]
    fn lists_and_marks_interrupted_projects() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let store = ProjectStore::for_root(root.clone());
        let (manifest, path) = store
            .create_recording_project(&options(), &target())
            .unwrap();
        store
            .write_recovery_journal(
                &RecoveryJournal {
                    project_id: manifest.id,
                    state: RecoveryState::Recording,
                    started_at: manifest.created_at,
                    source_paths: vec!["media/screen.mp4".to_string()],
                    owner_process_id: None,
                },
                &path,
            )
            .unwrap();

        let recovered = store.recover_interrupted_projects().unwrap();
        assert_eq!(recovered.len(), 1);
        let journal: RecoveryJournal =
            serde_json::from_str(&fs::read_to_string(path.join("recovery.json")).unwrap()).unwrap();
        assert_eq!(journal.state, RecoveryState::Interrupted);

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn recovery_preserves_live_recordings_and_recovers_exited_owners() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let store = ProjectStore::for_root(root.clone());
        let (manifest, path) = store
            .create_recording_project(&options(), &target())
            .unwrap();
        let mut journal = RecoveryJournal {
            project_id: manifest.id,
            state: RecoveryState::Recording,
            started_at: manifest.created_at,
            source_paths: vec!["media/screen.mp4".into()],
            owner_process_id: Some(std::process::id()),
        };
        store.write_recovery_journal(&journal, &path).unwrap();
        assert!(store.recover_interrupted_projects().unwrap().is_empty());
        let saved: RecoveryJournal =
            serde_json::from_str(&fs::read_to_string(path.join("recovery.json")).unwrap()).unwrap();
        assert_eq!(saved.state, RecoveryState::Recording);
        journal.owner_process_id = Some(i32::MAX as u32);
        store.write_recovery_journal(&journal, &path).unwrap();
        assert_eq!(store.recover_interrupted_projects().unwrap().len(), 1);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn system_audio_manifest_path_matches_platform_container() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let store = ProjectStore::for_root(root.clone());
        let (manifest, _) = store
            .create_recording_project(&options(), &target())
            .unwrap();
        let source = manifest
            .sources
            .iter()
            .find(|source| matches!(source.kind, MediaSourceKind::SystemAudio))
            .unwrap();

        #[cfg(target_os = "macos")]
        assert_eq!(source.relative_path, "media/screen.mp4");
        #[cfg(not(target_os = "macos"))]
        assert_eq!(source.relative_path, "media/system-audio.wav");

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn target_dimensions_are_used_when_region_is_absent() {
        let root = std::env::temp_dir().join(Uuid::new_v4().to_string());
        let store = ProjectStore::for_root(root.clone());
        let mut next_options = options();
        next_options.region = None;
        let (manifest, _) = store
            .create_recording_project(&next_options, &target())
            .unwrap();

        assert_eq!(manifest.sources[0].width, Some(1920));
        assert_eq!(manifest.sources[0].height, Some(1080));

        let _ = fs::remove_dir_all(root);
    }
}
