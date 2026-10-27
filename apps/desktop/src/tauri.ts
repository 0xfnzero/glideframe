import { invoke } from "@tauri-apps/api/core";
import type {
  AudioDevice,
  CameraDevice,
  CaptureSource,
  ConversionSettings,
  ProjectEdits,
  ProjectManifest,
  ProjectSummary,
  RecordingOptions,
  RecordingSession,
} from "./types";

const isTauri = "__TAURI_INTERNALS__" in window;

function unavailable<T>(message: string): Promise<T> {
  return Promise.reject(new Error(message));
}

export const api = {
  conversionStatus: () => invoke<string>("conversion_status"),
  convertMedia: (
    input: string,
    outputDirectory: string,
    settings: ConversionSettings,
  ) => invoke<string>("convert_media", { input, outputDirectory, settings }),
  cancelConversion: () => invoke<void>("cancel_conversion"),
  listCaptureSources: () =>
    isTauri
      ? invoke<CaptureSource[]>("list_capture_sources")
      : Promise.resolve<CaptureSource[]>([
          {
            id: "display:primary",
            type: "display",
            title: "Primary display",
            subtitle: "Preview source shown outside Tauri",
            nativeId: 0,
            displayId: 0,
            frame: { x: 0, y: 0, width: 1920, height: 1080 },
          },
        ]),
  listAudioDevices: () =>
    isTauri
      ? invoke<AudioDevice[]>("list_audio_devices")
      : Promise.resolve<AudioDevice[]>([
          {
            id: "system:default",
            name: "Default system output",
            isDefault: true,
            kind: "systemAudio",
          },
          {
            id: "microphone:default",
            name: "Default microphone",
            isDefault: true,
            kind: "microphone",
          },
        ]),
  listCameraDevices: () =>
    isTauri
      ? invoke<CameraDevice[]>("list_camera_devices")
      : Promise.resolve<CameraDevice[]>([]),
  listProjects: () =>
    isTauri
      ? invoke<ProjectSummary[]>("list_projects")
      : Promise.resolve<ProjectSummary[]>([]),
  recoverInterruptedProjects: () =>
    isTauri
      ? invoke<ProjectSummary[]>("recover_interrupted_projects")
      : Promise.resolve<ProjectSummary[]>([]),
  startRecording: (options: RecordingOptions) =>
    isTauri
      ? invoke<RecordingSession>("start_recording", { options })
      : unavailable<RecordingSession>(
          "Recording is only available inside the GlideFrame desktop app.",
        ),
  pauseRecording: (sessionId: string) =>
    invoke<RecordingSession>("pause_recording", { sessionId }),
  resumeRecording: (sessionId: string) =>
    invoke<RecordingSession>("resume_recording", { sessionId }),
  stopRecording: (sessionId: string) =>
    invoke<ProjectManifest>("stop_recording", { sessionId }),
  openProject: (path: string) =>
    invoke<ProjectManifest>("open_project", { path }),
  saveProjectEdits: (path: string, edits: ProjectEdits) =>
    invoke<ProjectManifest>("save_project_edits", { path, edits }),
  exportProject: (projectPath: string, preset: string) =>
    invoke<string>("export_project", { projectPath, preset }),
  openRecordingsFolder: () => invoke<string>("open_recordings_folder"),
  recordingsFolder: () => invoke<string>("recordings_folder"),
  openScreenRecordingSettings: () =>
    invoke<void>("open_screen_recording_settings"),
  screenRecordingPermissionGranted: () =>
    isTauri
      ? invoke<boolean>("screen_recording_permission_granted")
      : Promise.resolve(true),
  requestScreenRecordingPermission: () =>
    isTauri
      ? invoke<boolean>("request_screen_recording_permission")
      : Promise.resolve(true),
  revealProject: (path: string) => invoke<string>("reveal_project", { path }),
  revealProjectVideo: (path: string) =>
    invoke<string>("reveal_project_video", { path }),
};
