use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct FrameRect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum CaptureSourceType {
    Display,
    Window,
    Region,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CaptureSource {
    pub id: String,
    #[serde(rename = "type")]
    pub source_type: CaptureSourceType,
    pub title: String,
    pub subtitle: String,
    pub native_id: Option<u64>,
    pub display_id: Option<u64>,
    pub frame: FrameRect,
    pub app_icon_path: Option<String>,
    pub preview_image_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum AudioDeviceKind {
    SystemAudio,
    Microphone,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AudioDevice {
    pub id: String,
    pub name: String,
    pub is_default: bool,
    pub kind: AudioDeviceKind,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CameraDevice {
    pub id: String,
    pub name: String,
    pub is_default: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RecordingOptions {
    pub target_id: Option<String>,
    pub frame_rate: u32,
    pub record_system_audio: bool,
    pub record_microphone: bool,
    pub record_camera: bool,
    pub countdown: u32,
    pub region: Option<FrameRect>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProjectSummary {
    pub id: Uuid,
    pub title: String,
    #[serde(with = "iso8601_seconds")]
    pub updated_at: DateTime<Utc>,
    pub duration: f64,
    pub package_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RecoveryJournal {
    #[serde(rename = "projectID", alias = "projectId")]
    pub project_id: Uuid,
    pub state: RecoveryState,
    #[serde(with = "iso8601_seconds")]
    pub started_at: DateTime<Utc>,
    pub source_paths: Vec<String>,
    #[serde(
        default,
        rename = "ownerProcessID",
        alias = "ownerProcessId",
        skip_serializing_if = "Option::is_none"
    )]
    pub owner_process_id: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum RecoveryState {
    Preparing,
    Recording,
    Finalizing,
    Interrupted,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum RecordingState {
    Idle,
    Preparing,
    Countdown,
    Recording,
    Paused,
    Finalizing,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct RecordingSession {
    pub id: Uuid,
    pub state: RecordingState,
    pub project_path: String,
    pub live_preview_path: Option<String>,
    #[serde(with = "optional_iso8601_seconds")]
    pub started_at: Option<DateTime<Utc>>,
    pub options: RecordingOptions,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ProjectManifest {
    pub schema_version: u32,
    pub id: Uuid,
    pub title: String,
    #[serde(with = "iso8601_seconds")]
    pub created_at: DateTime<Utc>,
    #[serde(with = "iso8601_seconds")]
    pub updated_at: DateTime<Utc>,
    pub duration: f64,
    pub canvas: CanvasStyle,
    pub sources: Vec<MediaSource>,
    pub tracks: Vec<MediaTrack>,
    pub edit_graph: EditGraph,
    pub pointer_events: Vec<PointerEvent>,
    pub captions: Vec<CaptionCue>,
    pub export_preset: ExportPreset,
}

/// Only editor-owned fields may be changed through the desktop editor.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ProjectEdits {
    pub canvas: CanvasStyle,
    pub edit_graph: EditGraph,
    pub export_preset: ExportPreset,
}

impl ProjectManifest {
    pub fn new(title: impl Into<String>) -> Self {
        let now = Utc::now();
        Self {
            schema_version: 1,
            id: Uuid::new_v4(),
            title: title.into(),
            created_at: now,
            updated_at: now,
            duration: 0.0,
            canvas: CanvasStyle::default(),
            sources: Vec::new(),
            tracks: Vec::new(),
            edit_graph: EditGraph::default(),
            pointer_events: Vec::new(),
            captions: Vec::new(),
            export_preset: ExportPreset::hd(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum MediaSourceKind {
    Screen,
    SystemAudio,
    Microphone,
    Camera,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MediaSource {
    pub id: Uuid,
    pub kind: MediaSourceKind,
    pub relative_path: String,
    pub duration: f64,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub frame_rate: Option<f64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MediaTrack {
    pub id: Uuid,
    #[serde(rename = "sourceID", alias = "sourceId")]
    pub source_id: Uuid,
    pub kind: MediaSourceKind,
    pub is_enabled: bool,
    pub volume: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct EditGraph {
    pub clips: Vec<ClipEdit>,
    pub zoom_keyframes: Vec<ZoomKeyframe>,
    pub camera_layout: CameraLayout,
    pub remove_silence: bool,
    pub noise_reduction: f64,
}

impl Default for EditGraph {
    fn default() -> Self {
        Self {
            clips: Vec::new(),
            zoom_keyframes: Vec::new(),
            camera_layout: CameraLayout::BubbleBottomRight,
            remove_silence: false,
            noise_reduction: 0.35,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ClipEdit {
    pub id: Uuid,
    pub source_range: MediaTimeRange,
    pub is_removed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct MediaTimeRange {
    pub start: f64,
    pub duration: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ZoomKeyframe {
    pub id: Uuid,
    pub time: f64,
    pub scale: f64,
    pub focus_x: f64,
    pub focus_y: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum PointerEventKind {
    Move,
    Click,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct PointerEvent {
    pub id: Uuid,
    pub time: f64,
    pub x: f64,
    pub y: f64,
    pub kind: PointerEventKind,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CaptionCue {
    pub id: Uuid,
    pub range: MediaTimeRange,
    pub text: String,
    pub translated_text: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct CanvasStyle {
    pub aspect_ratio: AspectRatio,
    pub background: CanvasBackground,
    pub padding: f64,
    pub corner_radius: f64,
    pub shadow: f64,
}

impl Default for CanvasStyle {
    fn default() -> Self {
        Self {
            aspect_ratio: AspectRatio::Landscape,
            background: CanvasBackground::Graphite,
            padding: 64.0,
            corner_radius: 18.0,
            shadow: 0.28,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum AspectRatio {
    Landscape,
    Portrait,
    Square,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum CanvasBackground {
    Graphite,
    Daylight,
    Mint,
    Coral,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum CameraLayout {
    Hidden,
    BubbleBottomRight,
    BubbleBottomLeft,
    SideBySide,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ExportPreset {
    pub width: u32,
    pub height: u32,
    pub frame_rate: u32,
    pub codec: ExportCodec,
}

impl ExportPreset {
    pub fn hd() -> Self {
        Self {
            width: 1920,
            height: 1080,
            frame_rate: 30,
            codec: ExportCodec::H264,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum ExportCodec {
    H264,
    Hevc,
}

mod iso8601_seconds {
    use chrono::{DateTime, SecondsFormat, Utc};
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S>(value: &DateTime<Utc>, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&value.to_rfc3339_opts(SecondsFormat::Secs, true))
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<DateTime<Utc>, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        DateTime::parse_from_rfc3339(&value)
            .map(|date| date.with_timezone(&Utc))
            .map_err(serde::de::Error::custom)
    }
}

mod optional_iso8601_seconds {
    use chrono::{DateTime, SecondsFormat, Utc};
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S>(value: &Option<DateTime<Utc>>, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        match value {
            Some(date) => {
                serializer.serialize_some(&date.to_rfc3339_opts(SecondsFormat::Secs, true))
            }
            None => serializer.serialize_none(),
        }
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Option<DateTime<Utc>>, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = Option::<String>::deserialize(deserializer)?;
        value
            .map(|date| {
                DateTime::parse_from_rfc3339(&date)
                    .map(|date| date.with_timezone(&Utc))
                    .map_err(serde::de::Error::custom)
            })
            .transpose()
    }
}
