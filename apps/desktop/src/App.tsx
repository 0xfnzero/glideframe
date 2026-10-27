import { useCallback, useEffect, useRef, useState } from "react";
import { convertFileSrc } from "@tauri-apps/api/core";
import {
  AlertCircle,
  ArrowLeftRight,
  CheckCircle2,
  Circle,
  Folder,
  Globe2,
  Monitor,
  Pause,
  Play,
  RefreshCw,
  Square,
  Upload,
} from "lucide-react";
import { api } from "./tauri";
import { Dialog } from "./components/Dialog";
import { RecordingSetup } from "./components/RecordingSetup";
import { Studio, formatTime } from "./components/Studio";
import { Converter } from "./components/Converter";
import type {
  AudioDevice,
  CameraDevice,
  CaptureSource,
  ProjectManifest,
  ProjectSummary,
  RecordingOptions,
  RecordingSession,
  Translate,
} from "./types";

const defaultOptions: RecordingOptions = {
  frameRate: 30,
  recordSystemAudio: true,
  recordMicrophone: true,
  recordCamera: false,
  countdown: 3,
};
const errorMessage = (cause: unknown) =>
  cause instanceof Error ? cause.message : String(cause);

export function App() {
  const [language, setLanguage] = useState(
    () =>
      localStorage.getItem("glideframe.language") ??
      (navigator.language.startsWith("zh") ? "zh-Hans" : "en"),
  );
  const t: Translate = (zh, en) => (language === "zh-Hans" ? zh : en);
  const [sources, setSources] = useState<CaptureSource[]>([]);
  const [audio, setAudio] = useState<AudioDevice[]>([]);
  const [cameras, setCameras] = useState<CameraDevice[]>([]);
  const [options, setOptions] = useState<RecordingOptions>(defaultOptions);
  const [session, setSession] = useState<RecordingSession | null>(null);
  const [manifest, setManifest] = useState<ProjectManifest | null>(null);
  const [projectPath, setProjectPath] = useState<string | null>(null);
  const [projects, setProjects] = useState<ProjectSummary[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [sourceError, setSourceError] = useState<string | null>(null);
  const [deviceError, setDeviceError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [loadingSources, setLoadingSources] = useState(false);
  const [setup, setSetup] = useState(false);
  const [exportDialog, setExportDialog] = useState(false);
  const [converter, setConverter] = useState(false);
  const [exportPreset, setExportPreset] = useState("project");
  const [exportPath, setExportPath] = useState<string | null>(null);
  const [recordingsFolder, setRecordingsFolder] = useState<string | null>(null);
  const [recordingSaved, setRecordingSaved] = useState(false);
  const [countdown, setCountdown] = useState<number | null>(null);
  const [clock, setClock] = useState(Date.now());
  const [pausedAt, setPausedAt] = useState<number | null>(null);
  const [pausedMilliseconds, setPausedMilliseconds] = useState(0);
  const [saveState, setSaveState] = useState<"saved" | "saving" | "error">(
    "saved",
  );
  const pendingSave = useRef<{
    manifest: ProjectManifest;
    path: string;
    revision: number;
  } | null>(null);
  const saveQueue = useRef<Promise<void>>(Promise.resolve());
  const saveTimer = useRef<number | undefined>(undefined);
  const revision = useRef(0);

  useEffect(() => {
    localStorage.setItem("glideframe.language", language);
    document.documentElement.lang = language;
  }, [language]);
  useEffect(() => {
    void refreshProjects();
    void api.recordingsFolder().then(setRecordingsFolder).catch(() => {});
  }, []);
  useEffect(() => {
    if (!session) return;
    const timer = window.setInterval(() => setClock(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, [session]);
  useEffect(() => {
    if (!sourceError || !setup) return;
    const refresh = () => {
      if (document.visibilityState === "visible") void refreshDevices();
    };
    window.addEventListener("focus", refresh);
    return () => window.removeEventListener("focus", refresh);
  }, [sourceError, setup]);
  const closeSetup = useCallback(() => setSetup(false), []);
  const closeExport = useCallback(() => setExportDialog(false), []);
  const closeConverter = useCallback(() => setConverter(false), []);

  async function run(action: () => Promise<void>) {
    setBusy(true);
    setError(null);
    try {
      await action();
    } catch (cause) {
      setError(errorMessage(cause));
    } finally {
      setBusy(false);
    }
  }
  async function refreshProjects() {
    try {
      await api.recoverInterruptedProjects();
      setProjects(await api.listProjects());
    } catch (cause) {
      setError(errorMessage(cause));
    }
  }
  async function refreshDevices() {
    setLoadingSources(true);
    setSourceError(null);
    setDeviceError(null);
    const [nextSources, nextAudio, nextCameras] = await Promise.allSettled([
      api.listCaptureSources(),
      api.listAudioDevices(),
      api.listCameraDevices(),
    ]);
    if (nextSources.status === "fulfilled") {
      setSources(nextSources.value);
      setOptions((current) => ({
        ...current,
        targetId: nextSources.value.some((item) => item.id === current.targetId)
          ? current.targetId
          : nextSources.value[0]?.id,
      }));
    } else {
      setSources([]);
      setSourceError(errorMessage(nextSources.reason));
    }
    if (nextAudio.status === "fulfilled") setAudio(nextAudio.value);
    else setDeviceError(errorMessage(nextAudio.reason));
    if (nextCameras.status === "fulfilled") {
      setCameras(nextCameras.value);
      if (!nextCameras.value.length)
        setOptions((current) => ({ ...current, recordCamera: false }));
    } else {
      setCameras([]);
      setOptions((current) => ({ ...current, recordCamera: false }));
      setDeviceError(errorMessage(nextCameras.reason));
    }
    setLoadingSources(false);
  }
  async function persist() {
    window.clearTimeout(saveTimer.current);
    const pending = pendingSave.current;
    if (!pending) {
      await saveQueue.current;
      return;
    }
    pendingSave.current = null;
    const job = saveQueue.current
      .catch(() => {})
      .then(async () => {
        try {
          await api.saveProjectEdits(pending.path, {
            canvas: pending.manifest.canvas,
            editGraph: pending.manifest.editGraph,
            exportPreset: pending.manifest.exportPreset,
          });
          if (revision.current === pending.revision) setSaveState("saved");
        } catch (cause) {
          if (!pendingSave.current) pendingSave.current = pending;
          setSaveState("error");
          setError(errorMessage(cause));
          throw cause;
        }
      });
    saveQueue.current = job;
    await job;
  }
  function updateManifest(next: ProjectManifest) {
    if (!projectPath) return;
    setManifest(next);
    setSaveState("saving");
    pendingSave.current = {
      manifest: next,
      path: projectPath,
      revision: ++revision.current,
    };
    window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => {
      void persist().catch(() => {});
    }, 450);
  }
  function selectProject(project: ProjectSummary) {
    void run(async () => {
      await persist();
      const next = await api.openProject(project.packagePath);
      setManifest(next);
      setProjectPath(project.packagePath);
      setExportPath(null);
      setRecordingSaved(false);
      setSaveState("saved");
    });
  }
  function showSetup() {
    setError(null);
    setSetup(true);
    void refreshDevices();
  }
  async function start() {
    const source =
      sources.find((item) => item.id === options.targetId) ?? sources[0];
    if (!source) return;
    await run(async () => {
      await persist();
      const recordingOptions = { ...options, targetId: source.id };
      for (let remaining = options.countdown; remaining > 0; remaining--) {
        setCountdown(remaining);
        await new Promise((resolve) => window.setTimeout(resolve, 1000));
      }
      setCountdown(null);
      const next = await api.startRecording(recordingOptions);
      setPausedAt(null);
      setPausedMilliseconds(0);
      setClock(Date.now());
      setSession(next);
      setProjectPath(next.projectPath);
      setManifest(null);
      setExportPath(null);
      setRecordingSaved(false);
      setSetup(false);
    });
    setCountdown(null);
  }
  function pause() {
    if (session)
      void run(async () => {
        setSession(await api.pauseRecording(session.id));
        setPausedAt(Date.now());
      });
  }
  function resume() {
    if (session)
      void run(async () => {
        setSession(await api.resumeRecording(session.id));
        if (pausedAt !== null)
          setPausedMilliseconds((value) => value + Date.now() - pausedAt);
        setPausedAt(null);
      });
  }
  function stop() {
    if (!session) return;
    const previous = session;
    void run(async () => {
      setSession({ ...session, state: "finalizing" });
      try {
        const next = await api.stopRecording(previous.id);
        setManifest(next);
        setProjectPath(previous.projectPath);
        setSession(null);
        setSaveState("saved");
        setRecordingSaved(true);
        await refreshProjects();
      } catch (cause) {
        setSession(previous);
        throw cause;
      }
    });
  }
  function exportProject() {
    if (projectPath)
      void run(async () => {
        await persist();
        setExportPath(await api.exportProject(projectPath, exportPreset));
        setExportDialog(false);
      });
  }
  const elapsed = session?.startedAt
    ? Math.max(
        0,
        ((pausedAt ?? clock) -
          Date.parse(session.startedAt) -
          pausedMilliseconds) /
          1000,
      )
    : 0;
  const screenSource = manifest?.sources.find((source) => source.kind === "screen");
  const separator = projectPath?.includes("\\") ? "\\" : "/";
  const recordingFile = projectPath && screenSource
    ? `${projectPath}${separator}${screenSource.relativePath.replaceAll("/", separator)}`
    : null;
  const presetWidth = manifest?.exportPreset.width ?? 1920;
  const presetHeight = manifest?.exportPreset.height ?? 1080;
  const shortEdge = Math.min(presetWidth, presetHeight),
    longEdge = Math.max(presetWidth, presetHeight);
  const outputSize =
    manifest?.canvas.aspectRatio === "square"
      ? `${shortEdge} × ${shortEdge}`
      : manifest?.canvas.aspectRatio === "portrait"
        ? `${shortEdge} × ${longEdge}`
        : `${longEdge} × ${shortEdge}`;
  const date = (value: string) =>
    new Intl.DateTimeFormat(language === "zh-Hans" ? "zh-CN" : "en", {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    }).format(new Date(value));
  return (
    <main className="app-shell">
      <aside className="library">
        <div className="brand">
          <span className="brand-mark" />
          <span>GlideFrame</span>
        </div>
        <header className="library-heading">
          <span>{t("项目", "Projects")}</span>
          <button
            className="icon-button"
            title={t("刷新项目", "Refresh projects")}
            disabled={busy || !!session}
            onClick={() => void refreshProjects()}
          >
            <RefreshCw />
          </button>
        </header>
        <nav className="project-list" aria-label={t("项目", "Projects")}>
          {projects.map((project) => (
            <button
              key={project.id}
              className={`project-row ${project.packagePath === projectPath ? "selected" : ""}`}
              aria-current={
                project.packagePath === projectPath ? "page" : undefined
              }
              disabled={busy || !!session}
              onClick={() => selectProject(project)}
            >
              <span>
                {project.title === "Untitled Recording"
                  ? t("未命名录制", "Untitled Recording")
                  : project.title}
              </span>
              <small>
                {formatTime(project.duration)}
                <span>·</span>
                {date(project.updatedAt)}
              </small>
            </button>
          ))}
          {!projects.length && (
            <p className="empty-library muted">
              {t("还没有录制项目", "No recordings yet")}
            </p>
          )}
        </nav>
        <footer className="library-footer">
          <button
            className="library-folder-button"
            onClick={() => void run(async () => { await api.openRecordingsFolder(); })}
          >
            <Folder />
            {t("打开全部录制文件夹", "All recordings folder")}
          </button>
          {recordingsFolder && <span className="library-folder-path" title={recordingsFolder}>{recordingsFolder}</span>}
        </footer>
      </aside>
      <div className="workspace">
        <header className="toolbar">
          <span className="project-title">
            {manifest?.title === "Untitled Recording"
              ? t("未命名录制", "Untitled Recording")
              : (manifest?.title ?? "")}
          </span>
          {session && (
            <div className="recording-controls">
              <span
                className={`status-dot ${session.state === "paused" ? "paused" : ""}`}
              />
              <span className="timecode">{formatTime(elapsed)}</span>
              <span className="caption muted">
                {session.state === "paused"
                  ? t("已暂停", "Paused")
                  : session.state === "finalizing"
                    ? t("正在保存…", "Finalizing…")
                    : t("录制中", "Recording")}
              </span>
              <button
                className="icon-button"
                disabled={busy}
                title={
                  session.state === "paused"
                    ? t("继续录制", "Resume recording")
                    : t("暂停录制", "Pause recording")
                }
                onClick={session.state === "paused" ? resume : pause}
              >
                {session.state === "paused" ? <Play /> : <Pause />}
              </button>
              <button
                className="icon-button stop-button"
                title={t("停止录制", "Stop recording")}
                disabled={busy}
                onClick={stop}
              >
                <Square fill="currentColor" />
              </button>
            </div>
          )}
          <div className="toolbar-actions">
            <button className="record-button" disabled={busy || !!session} onClick={showSetup}>
              <Circle />
              {t("新建录制", "New Recording")}
            </button>
            <button
              disabled={busy || !!session || !manifest}
              onClick={() => {
                setExportPath(null);
                setExportDialog(true);
              }}
            >
              <Upload />
              {t("导出", "Export")}
            </button>
            <button
              disabled={busy || !!session}
              onClick={() => setConverter(true)}
            >
              <ArrowLeftRight />
              {t("格式转换", "Convert")}
            </button>
            <label className="language-control" title={t("语言", "Language")}>
              <Globe2 />
              <select
                aria-label={t("语言", "Language")}
                value={language}
                onChange={(event) => setLanguage(event.target.value)}
              >
                <option value="zh-Hans">简体中文</option>
                <option value="en">English</option>
              </select>
            </label>
          </div>
        </header>
        {!session && projectPath && (
          <div className={`file-location ${recordingSaved ? "just-saved" : ""}`} role={recordingSaved ? "status" : undefined}>
            {recordingSaved ? <CheckCircle2 /> : <Folder />}
            <div className="file-location-details">
              <strong>{recordingSaved ? t("录制已保存", "Recording saved") : t("录制文件", "Recorded video")}</strong>
              <span className="file-path" title={recordingFile ?? projectPath}>{recordingFile ?? projectPath}</span>
            </div>
            <button onClick={() => void run(async () => {
              if (recordingFile) await api.revealProjectVideo(projectPath);
              else await api.revealProject(projectPath);
            })}>
              <Folder />
              {recordingFile ? t("打开视频文件夹", "Show video in folder") : t("打开项目文件夹", "Show project in folder")}
            </button>
          </div>
        )}
        {error && (
          <div className="notice error" role="alert">
            <AlertCircle />
            <span>{error}</span>
            {saveState === "error" && (
              <button onClick={() => void persist().catch(() => {})}>
                {t("重试保存", "Retry saving")}
              </button>
            )}
            <button
              className="notice-close"
              onClick={() => setError(null)}
              aria-label={t("关闭提示", "Dismiss")}
            >
              ×
            </button>
          </div>
        )}
        {exportPath && (
          <div className="notice success" role="status">
            <CheckCircle2 />
            <span className="file-location-details">
              <strong>{t("视频已导出", "Video exported")}</strong>
              <span className="file-path" title={exportPath}>{exportPath}</span>
            </span>
            <button
              onClick={() =>
                void run(async () => {
                  await api.revealProject(exportPath);
                })
              }
            >
              <Folder />
              {t("打开导出文件夹", "Show exported video")}
            </button>
            <button
              className="notice-close"
              onClick={() => setExportPath(null)}
              aria-label={t("关闭提示", "Dismiss")}
            >
              ×
            </button>
          </div>
        )}
        {session ? (
          <div className="live-preview">
            {session.livePreviewPath && (
              <img
                alt={t("实时预览", "Live preview")}
                src={`${convertFileSrc(session.livePreviewPath)}?v=${clock}`}
              />
            )}
            <span className="live-badge">
              <span className="status-dot" />
              {t("实时预览", "Live preview")}
            </span>
          </div>
        ) : manifest && projectPath ? (
          <Studio
            disabled={busy}
            manifest={manifest}
            path={projectPath}
            onChange={updateManifest}
            t={t}
          />
        ) : (
          <div className="welcome">
            <div className="welcome-symbol">
              <Monitor />
              <span />
            </div>
            <h1>{t("制作精致的产品演示", "Create polished product demos")}</h1>
            <p>
              {t(
                "录制屏幕或窗口，再使用自动运镜和轻量编辑器完成视频。",
                "Record a screen or window, then finish your video with Auto Polish and lightweight editing.",
              )}
            </p>
            <button className="record-button" onClick={showSetup} disabled={busy}>
              <Circle />
              {t("新建录制", "New Recording")}
            </button>
          </div>
        )}
      </div>
      {setup && (
        <RecordingSetup
          sources={sources}
          cameras={cameras}
          audio={audio}
          options={options}
          onOptions={setOptions}
          onRefresh={() => void refreshDevices()}
          onStart={() => void start()}
          onClose={closeSetup}
          busy={busy || loadingSources}
          countdown={countdown}
          sourceError={sourceError}
          deviceError={deviceError}
          actionError={error}
          onPermission={() =>
            void run(async () => {
              await api.requestScreenRecordingPermission();
              await refreshDevices();
            })
          }
          onSettings={() =>
            void api
              .openScreenRecordingSettings()
              .catch((cause) => setError(errorMessage(cause)))
          }
          t={t}
        />
      )}
      {exportDialog && (
        <Dialog
          title={t("导出视频", "Export Video")}
          closeLabel={t("关闭", "Close")}
          onClose={closeExport}
          locked={busy}
          className="export-dialog"
        >
          {error && (
            <div className="notice error" role="alert">
              <span>{error}</span>
            </div>
          )}
          <div className="dialog-body">
            <p className="muted">
              {t(
                "导出会应用已保存的画面样式、裁剪和运镜。",
                "Export applies your saved canvas, trim and zoom edits.",
              )}
            </p>
            <label className="control-row">
              <span>{t("分辨率", "Resolution")}</span>
              <select
                disabled={busy}
                value={exportPreset}
                onChange={(event) => setExportPreset(event.target.value)}
              >
                <option value="project">
                  {t("项目设置", "Project settings")} · {outputSize}
                </option>
                <option value="hd">1080p</option>
                <option value="ultraHD">4K</option>
                <option value="source">
                  {t("原始尺寸（无留白）", "Source size (no padding)")}
                </option>
              </select>
            </label>
            <p className="caption muted">
              MP4 ·{" "}
              {manifest?.exportPreset.codec === "hevc"
                ? "H.265 / HEVC"
                : "H.264"}
            </p>
          </div>
          <footer className="dialog-footer">
            <span className="caption muted">
              {busy
                ? t("正在导出，请稍候…", "Exporting, please wait…")
                : t(
                    "保存到项目的 exports 文件夹",
                    "Save to the project’s exports folder",
                  )}
            </span>
            <div className="button-row">
              <button disabled={busy} onClick={closeExport}>
                {t("取消", "Cancel")}
              </button>
              <button
                className="primary-button"
                disabled={busy}
                onClick={exportProject}
              >
                {t("导出", "Export")}
              </button>
            </div>
          </footer>
        </Dialog>
      )}
      {converter && <Converter onClose={closeConverter} t={t} />}
    </main>
  );
}
