export type CaptureSourceType = "display" | "window" | "region";
export type RecordingState =
  | "idle"
  | "preparing"
  | "countdown"
  | "recording"
  | "paused"
  | "finalizing"
  | "failed";

export interface FrameRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface CaptureSource {
  id: string;
  type: CaptureSourceType;
  title: string;
  subtitle: string;
  nativeId?: number;
  displayId?: number;
  frame: FrameRect;
  appIconPath?: string;
  previewImagePath?: string;
}

export interface AudioDevice {
  id: string;
  name: string;
  isDefault: boolean;
  kind: "systemAudio" | "microphone";
}

export interface CameraDevice {
  id: string;
  name: string;
  isDefault: boolean;
}

export interface RecordingOptions {
  targetId?: string;
  frameRate: number;
  recordSystemAudio: boolean;
  recordMicrophone: boolean;
  recordCamera: boolean;
  countdown: number;
  region?: FrameRect;
}

export interface ProjectSummary {
  id: string;
  title: string;
  updatedAt: string;
  duration: number;
  packagePath: string;
}

export interface RecordingSession {
  id: string;
  state: RecordingState;
  projectPath: string;
  livePreviewPath?: string;
  startedAt?: string;
  options: RecordingOptions;
}

export interface ProjectManifest {
  schemaVersion: number;
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
  duration: number;
  canvas: CanvasStyle;
  sources: Array<{
    id: string;
    kind: "screen" | "systemAudio" | "microphone" | "camera";
    relativePath: string;
    duration: number;
    width?: number;
    height?: number;
  }>;
  tracks: Array<{
    id: string;
    sourceID: string;
    kind: string;
    isEnabled: boolean;
    volume: number;
  }>;
  editGraph: EditGraph;
  pointerEvents: Array<{
    id: string;
    time: number;
    x: number;
    y: number;
    kind: "move" | "click";
  }>;
  captions: unknown[];
  exportPreset: {
    width: number;
    height: number;
    frameRate: number;
    codec: "h264" | "hevc";
  };
}

export interface CanvasStyle {
  aspectRatio: "landscape" | "portrait" | "square";
  background: "graphite" | "daylight" | "mint" | "coral";
  padding: number;
  cornerRadius: number;
  shadow: number;
}

export interface EditGraph {
  clips: Array<{
    id: string;
    sourceRange: { start: number; duration: number };
    isRemoved: boolean;
  }>;
  zoomKeyframes: Array<{
    id: string;
    time: number;
    scale: number;
    focusX: number;
    focusY: number;
  }>;
  cameraLayout:
    | "hidden"
    | "bubbleBottomRight"
    | "bubbleBottomLeft"
    | "sideBySide";
  removeSilence: boolean;
  noiseReduction: number;
}

export type ProjectEdits = Pick<
  ProjectManifest,
  "canvas" | "editGraph" | "exportPreset"
>;
export type Translate = (chinese: string, english: string) => string;

export interface ConversionSettings {
  format: string;
  codec: string;
  resolution: string;
  frameRate: string;
  quality: string;
  includeAudio: boolean;
}
