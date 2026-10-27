import { useEffect, useRef, useState } from "react";
import { open } from "@tauri-apps/plugin-dialog";
import { videoDir, join } from "@tauri-apps/api/path";
import { Check, FileVideo, Folder, Plus, X } from "lucide-react";
import { api } from "../tauri";
import type { ConversionSettings, Translate } from "../types";
import { Dialog } from "./Dialog";
import { Toggle } from "./RecordingSetup";
const formats: Record<string, string[]> = {
  mp4: ["h264", "hevc"],
  mov: ["h264", "hevc", "proRes"],
  mkv: ["h264", "hevc", "vp9", "av1", "proRes"],
  webm: ["vp9", "av1"],
  avi: ["mpeg4"],
  m4v: ["h264"],
  mpegTS: ["h264", "hevc"],
  wmv: ["wmv2"],
  flv: ["flv"],
  gif: ["gif"],
  mp3: ["mp3"],
  m4a: ["aac"],
  wav: ["pcm"],
  flac: ["flac"],
  ogg: ["opus"],
  opus: ["opus"],
};
const codecNames: Record<string, string> = {
  h264: "H.264",
  hevc: "H.265 / HEVC",
  proRes: "Apple ProRes 422 HQ",
  vp9: "VP9",
  av1: "AV1",
  mpeg4: "MPEG-4",
  wmv2: "WMV 8",
  flv: "Sorenson Spark",
  gif: "GIF",
  mp3: "MP3",
  aac: "AAC",
  pcm: "PCM 16-bit",
  flac: "FLAC",
  opus: "Opus",
};
type Job = {
  input: string;
  status: "ready" | "converting" | "completed" | "failed" | "cancelled";
  output?: string;
  error?: string;
};
export function Converter({
  onClose,
  t,
}: {
  onClose: () => void;
  t: Translate;
}) {
  const [settings, setSettings] = useState<ConversionSettings>({
    format: "mp4",
    codec: "h264",
    resolution: "source",
    frameRate: "source",
    quality: "balanced",
    includeAudio: true,
  });
  const [jobs, setJobs] = useState<Job[]>([]);
  const [directory, setDirectory] = useState("");
  const [toolchainReady, setToolchainReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [running, setRunning] = useState(false);
  const cancelled = useRef(false);
  useEffect(() => {
    void api
      .conversionStatus()
      .then(() => setToolchainReady(true))
      .catch((cause) => setError(String(cause)));
    void videoDir()
      .then((root) => join(root, "GlideFrame", "Conversions"))
      .then(setDirectory);
  }, []);
  const update = (patch: Partial<ConversionSettings>) =>
    setSettings({ ...settings, ...patch });
  async function addFiles() {
    try {
      const paths = await open({ multiple: true, directory: false });
      if (paths)
        setJobs((current) => [
          ...current,
          ...paths
            .filter((input) => !current.some((job) => job.input === input))
            .map((input) => ({ input, status: "ready" as const })),
        ]);
    } catch (cause) {
      setError(String(cause));
    }
  }
  async function start() {
    cancelled.current = false;
    setRunning(true);
    setError(null);
    for (const job of jobs.filter((item) => item.status !== "completed")) {
      if (cancelled.current) break;
      setJobs((current) =>
        current.map((item) =>
          item.input === job.input
            ? { ...item, status: "converting", error: undefined }
            : item,
        ),
      );
      try {
        const output = await api.convertMedia(job.input, directory, settings);
        setJobs((current) =>
          current.map((item) =>
            item.input === job.input
              ? { ...item, output, status: "completed" }
              : item,
          ),
        );
      } catch (cause) {
        setJobs((current) =>
          current.map((item) =>
            item.input === job.input
              ? {
                  ...item,
                  status: cancelled.current ? "cancelled" : "failed",
                  error: cancelled.current ? undefined : String(cause),
                }
              : item,
          ),
        );
      }
    }
    setRunning(false);
  }
  const status = (job: Job) =>
    ({
      ready: t("待转换", "Ready"),
      converting: t("正在转换…", "Converting…"),
      completed: t("已完成", "Completed"),
      failed: t("失败", "Failed"),
      cancelled: t("已取消", "Cancelled"),
    })[job.status];
  return (
    <Dialog
      title={t("格式转换", "Format Converter")}
      onClose={onClose}
      closeLabel={t("关闭", "Close")}
      locked={running}
      className="converter-dialog"
    >
      {error && (
        <div className="notice error" role="alert">
          <span>{error}</span>
        </div>
      )}
      <div className="conversion-layout">
        <section className="conversion-files">
          <header>
            <h2>{t("文件队列", "File queue")}</h2>
            <button disabled={running} onClick={() => void addFiles()}>
              <Plus />
              {t("添加文件", "Add files")}
            </button>
          </header>
          {!jobs.length && (
            <p className="converter-empty">
              {t(
                "添加视频或音频文件，批量转换格式。",
                "Add video or audio files to convert them in a batch.",
              )}
            </p>
          )}
          {jobs.map((job) => (
            <div className="conversion-job" key={job.input}>
              <FileVideo />
              <div>
                <strong>{job.input.split(/[\\/]/).pop()}</strong>
                <small>{job.error ?? status(job)}</small>
              </div>
              {job.status === "completed" ? (
                <button
                  className="icon-button"
                  title={t("显示文件", "Reveal file")}
                  onClick={() =>
                    void api
                      .revealProject(job.output!)
                      .catch((cause) => setError(String(cause)))
                  }
                >
                  <Check />
                </button>
              ) : (
                <button
                  className="icon-button"
                  disabled={running}
                  title={t("移除", "Remove")}
                  onClick={() =>
                    setJobs((current) =>
                      current.filter((item) => item.input !== job.input),
                    )
                  }
                >
                  <X />
                </button>
              )}
            </div>
          ))}
        </section>
        <section className="conversion-settings">
          <h2>{t("输出设置", "Output settings")}</h2>
          <label className="control-row">
            <span>{t("格式", "Format")}</span>
            <select
              disabled={running}
              value={settings.format}
              onChange={(event) => {
                const format = event.target.value;
                update({
                  format,
                  codec: formats[format].includes(settings.codec)
                    ? settings.codec
                    : formats[format][0],
                });
              }}
            >
              {Object.keys(formats).map((format) => (
                <option key={format} value={format}>
                  {format === "mpegTS" ? "MPEG-TS" : format.toUpperCase()}
                </option>
              ))}
            </select>
          </label>
          <label className="control-row">
            <span>{t("编码", "Codec")}</span>
            <select
              disabled={running}
              value={settings.codec}
              onChange={(event) => update({ codec: event.target.value })}
            >
              {formats[settings.format].map((codec) => (
                <option key={codec} value={codec}>
                  {codecNames[codec]}
                </option>
              ))}
            </select>
          </label>
          <label className="control-row">
            <span>{t("分辨率", "Resolution")}</span>
            <select
              disabled={running}
              value={settings.resolution}
              onChange={(event) => update({ resolution: event.target.value })}
            >
              {[
                ["source", t("原始", "Source")],
                ["uhd2160", "4K"],
                ["fullHD1080", "1080p"],
                ["hd720", "720p"],
                ["sd480", "480p"],
              ].map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          <label className="control-row">
            <span>{t("帧率", "Frame rate")}</span>
            <select
              disabled={running}
              value={settings.frameRate}
              onChange={(event) => update({ frameRate: event.target.value })}
            >
              {[
                ["source", t("原始", "Source")],
                ["fps60", "60 fps"],
                ["fps30", "30 fps"],
                ["fps24", "24 fps"],
              ].map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          <label className="control-row">
            <span>{t("质量", "Quality")}</span>
            <select
              disabled={running}
              value={settings.quality}
              onChange={(event) => update({ quality: event.target.value })}
            >
              {[
                ["high", t("高质量", "High")],
                ["balanced", t("均衡", "Balanced")],
                ["compact", t("小体积", "Compact")],
              ].map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          <Toggle
            label={t("包含音频", "Include audio")}
            disabled={running}
            checked={settings.includeAudio}
            onChange={(includeAudio) => update({ includeAudio })}
          />
          <div className="conversion-output">
            <span className="muted">{t("输出文件夹", "Output folder")}</span>
            <p>{directory}</p>
            <button
              disabled={running}
              onClick={() =>
                void open({ directory: true, defaultPath: directory })
                  .then((path) => {
                    if (typeof path === "string") setDirectory(path);
                  })
                  .catch((cause) => setError(String(cause)))
              }
            >
              <Folder />
              {t("选择文件夹", "Choose folder")}
            </button>
          </div>
        </section>
      </div>
      <footer className="dialog-footer">
        <span className="caption muted">
          {running
            ? t("正在处理文件…", "Processing files…")
            : null}
        </span>
        <div className="button-row">
          {running ? (
            <button
              onClick={() => {
                cancelled.current = true;
                void api
                  .cancelConversion()
                  .catch((cause) => setError(String(cause)));
              }}
            >
              {t("取消转换", "Cancel conversion")}
            </button>
          ) : (
            <button onClick={onClose}>{t("关闭", "Close")}</button>
          )}
          <button
            className="primary-button"
            disabled={
              running ||
              !toolchainReady ||
              !directory ||
              !jobs.some((job) => job.status !== "completed")
            }
            onClick={() => void start()}
          >
            {t("开始转换", "Start conversion")}
          </button>
        </div>
      </footer>
    </Dialog>
  );
}
