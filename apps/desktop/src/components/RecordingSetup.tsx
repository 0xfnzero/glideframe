import { useRef } from "react";
import type { PointerEvent, ReactNode } from "react";
import {
  Camera,
  Check,
  Circle,
  Maximize,
  Mic,
  Monitor,
  RefreshCw,
  Volume2,
} from "lucide-react";
import { convertFileSrc } from "@tauri-apps/api/core";
import type {
  AudioDevice,
  CameraDevice,
  CaptureSource,
  RecordingOptions,
  Translate,
} from "../types";
import { Dialog } from "./Dialog";

export function RecordingSetup({
  sources,
  cameras,
  audio,
  options,
  onOptions,
  onRefresh,
  onStart,
  onClose,
  busy,
  countdown,
  sourceError,
  deviceError,
  actionError,
  onPermission,
  onSettings,
  t,
}: {
  sources: CaptureSource[];
  cameras: CameraDevice[];
  audio: AudioDevice[];
  options: RecordingOptions;
  onOptions: (options: RecordingOptions) => void;
  onRefresh: () => void;
  onStart: () => void;
  onClose: () => void;
  busy: boolean;
  countdown: number | null;
  sourceError: string | null;
  deviceError: string | null;
  actionError: string | null;
  onPermission: () => void;
  onSettings: () => void;
  t: Translate;
}) {
  const selected =
    sources.find((source) => source.id === options.targetId) ?? sources[0];
  const origin = useRef<{ x: number; y: number } | null>(null);
  const update = (patch: Partial<RecordingOptions>) =>
    onOptions({ ...options, ...patch });
  function point(event: PointerEvent<HTMLDivElement>) {
    const bounds = event.currentTarget.getBoundingClientRect();
    return {
      x: Math.max(0, Math.min(1, (event.clientX - bounds.left) / bounds.width)),
      y: Math.max(0, Math.min(1, (event.clientY - bounds.top) / bounds.height)),
    };
  }
  function move(event: PointerEvent<HTMLDivElement>) {
    if (!origin.current || !selected || !options.region) return;
    const current = point(event),
      first = origin.current,
      frame = selected.frame;
    update({
      region: {
        x: Math.round(frame.x + Math.min(first.x, current.x) * frame.width),
        y: Math.round(frame.y + Math.min(first.y, current.y) * frame.height),
        width: Math.max(
          64,
          Math.round(Math.abs(current.x - first.x) * frame.width),
        ),
        height: Math.max(
          64,
          Math.round(Math.abs(current.y - first.y) * frame.height),
        ),
      },
    });
  }
  const region = options.region;
  return (
    <Dialog
      title={t("新建录制", "New Recording")}
      onClose={onClose}
      closeLabel={t("关闭", "Close")}
      locked={busy}
      className="recording-dialog"
    >
      {actionError && (
        <div className="notice error" role="alert">
          <span>{actionError}</span>
        </div>
      )}
      <div className="setup-columns">
        <section className="source-panel">
          <header>
            <h2>{t("录制来源", "Recording source")}</h2>
            <button
              className="icon-button"
              disabled={busy}
              onClick={onRefresh}
              title={t("刷新来源", "Refresh sources")}
            >
              <RefreshCw />
            </button>
          </header>
          <div className="source-list">
            {sources.map((source) => (
              <button
                className={`source-row ${source.id === selected?.id ? "selected" : ""}`}
                key={source.id}
                disabled={busy}
                aria-pressed={source.id === selected?.id}
                onClick={() =>
                  update({ targetId: source.id, region: undefined })
                }
              >
                {source.appIconPath ? (
                  <img src={convertFileSrc(source.appIconPath)} alt="" />
                ) : source.type === "display" ? (
                  <Monitor />
                ) : (
                  <Maximize />
                )}
                <span>
                  <span>{source.title}</span>
                  <small>{source.subtitle}</small>
                </span>
                {source.id === selected?.id && (
                  <Check className="source-check" />
                )}
              </button>
            ))}
          </div>
          {sourceError ? (
            <div className="permission-message">
              <p>
                {t(
                  "无法读取录制来源，请检查屏幕录制权限。",
                  "Recording sources are unavailable. Check screen recording access.",
                )}
              </p>
              <details>
                <summary>{t("查看详情", "Details")}</summary>
                {sourceError}
              </details>
              <div className="button-row">
                <button onClick={onPermission} disabled={busy}>
                  {t("允许录屏", "Allow recording")}
                </button>
                <button onClick={onSettings}>
                  {t("系统设置", "System Settings")}
                </button>
              </div>
            </div>
          ) : (
            !sources.length && (
              <p className="muted">
                {t("正在查找屏幕与窗口…", "Looking for screens and windows…")}
              </p>
            )
          )}
          {selected && (
            <div
              className="source-preview"
              style={{
                aspectRatio: selected.frame.width / selected.frame.height,
              }}
              onPointerDown={(event) => {
                if (!region || busy) return;
                event.currentTarget.setPointerCapture(event.pointerId);
                origin.current = point(event);
              }}
              onPointerMove={move}
              onPointerUp={(event) => {
                move(event);
                origin.current = null;
              }}
              onPointerCancel={() => {
                origin.current = null;
              }}
            >
              {selected.previewImagePath ? (
                <img
                  alt={t("来源预览", "Source preview")}
                  src={convertFileSrc(selected.previewImagePath)}
                />
              ) : (
                <Monitor />
              )}
              {region && (
                <div
                  className="region-selection"
                  style={{
                    left: `${((region.x - selected.frame.x) / selected.frame.width) * 100}%`,
                    top: `${((region.y - selected.frame.y) / selected.frame.height) * 100}%`,
                    width: `${(region.width / selected.frame.width) * 100}%`,
                    height: `${(region.height / selected.frame.height) * 100}%`,
                  }}
                />
              )}
            </div>
          )}
          {region && (
            <p className="caption muted">
              {t(
                "在预览中拖动选择录制区域。",
                "Drag on the preview to select a recording region.",
              )}
            </p>
          )}
        </section>
        <section className="capture-settings">
          <h2>{t("录制设置", "Recording settings")}</h2>
          <div className="segmented">
            <button
              disabled={busy}
              aria-pressed={!region}
              onClick={() => update({ region: undefined })}
            >
              {t("完整来源", "Full source")}
            </button>
            <button
              disabled={busy || !selected}
              aria-pressed={!!region}
              onClick={() =>
                selected &&
                update({
                  region: {
                    ...selected.frame,
                    width: Math.min(1280, selected.frame.width),
                    height: Math.min(720, selected.frame.height),
                  },
                })
              }
            >
              {t("选定区域", "Region")}
            </button>
          </div>
          {region && (
            <div className="region-inputs">
              {(["x", "y", "width", "height"] as const).map((key) => (
                <label key={key}>
                  <span>
                    {
                      {
                        x: "X",
                        y: "Y",
                        width: t("宽度", "Width"),
                        height: t("高度", "Height"),
                      }[key]
                    }
                  </span>
                  <input
                    type="number"
                    disabled={busy}
                    min={key === "width" || key === "height" ? 64 : undefined}
                    value={region[key]}
                    onChange={(event) =>
                      update({
                        region: {
                          ...region,
                          [key]: Number(event.target.value),
                        },
                      })
                    }
                  />
                </label>
              ))}
            </div>
          )}
          <label className="control-row">
            <span>{t("帧率", "Frame rate")}</span>
            <select
              disabled={busy}
              value={options.frameRate}
              onChange={(event) =>
                update({ frameRate: Number(event.target.value) })
              }
            >
              <option value={30}>30 fps</option>
              <option value={60}>60 fps</option>
            </select>
          </label>
          <div className="settings-divider" />
          <Toggle
            icon={<Volume2 />}
            label={t("系统音频", "System audio")}
            checked={options.recordSystemAudio}
            disabled={busy}
            onChange={(recordSystemAudio) => update({ recordSystemAudio })}
          />
          <Toggle
            icon={<Mic />}
            label={t("麦克风", "Microphone")}
            checked={options.recordMicrophone}
            disabled={busy}
            onChange={(recordMicrophone) => update({ recordMicrophone })}
          />
          <Toggle
            icon={<Camera />}
            label={t("摄像头", "Camera")}
            checked={options.recordCamera}
            disabled={busy || !cameras.length}
            onChange={(recordCamera) => update({ recordCamera })}
          />
          <p className="caption muted device-note">
            {cameras.length
              ? cameras[0].name
              : t("未检测到可用摄像头", "No camera available")}
            {audio.find((device) => device.kind === "microphone")
              ? ` · ${audio.find((device) => device.kind === "microphone")?.name}`
              : ""}
          </p>
          {deviceError && <p className="caption error-text">{deviceError}</p>}
          <div className="settings-divider" />
          <label className="control-row">
            <span>{t("倒计时", "Countdown")}</span>
            <select
              disabled={busy}
              value={options.countdown}
              onChange={(event) =>
                update({ countdown: Number(event.target.value) })
              }
            >
              {[0, 1, 2, 3, 4, 5].map((value) => (
                <option key={value} value={value}>
                  {value === 0 ? t("关闭", "Off") : `${value} ${t("秒", "s")}`}
                </option>
              ))}
            </select>
          </label>
        </section>
      </div>
      <footer className="dialog-footer">
        <span className="caption muted">
          {countdown
            ? t(`${countdown} 秒后开始录制`, `Starting in ${countdown}`)
            : selected
              ? `${region?.width ?? selected.frame.width} × ${region?.height ?? selected.frame.height} · ${options.frameRate} fps`
              : ""}
        </span>
        <div className="button-row">
          <button onClick={onClose} disabled={busy}>
            {t("取消", "Cancel")}
          </button>
          <button
            className="record-button"
            onClick={onStart}
            disabled={busy || !selected}
          >
            <Circle />
            {busy
              ? t("准备中…", "Preparing…")
              : t("开始录制", "Start Recording")}
          </button>
        </div>
      </footer>
    </Dialog>
  );
}

export function Toggle({
  icon,
  label,
  checked,
  disabled,
  onChange,
}: {
  icon?: ReactNode;
  label: string;
  checked: boolean;
  disabled?: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <label className={`toggle-row ${disabled ? "disabled" : ""}`}>
      <span>
        {icon}
        {label}
      </span>
      <input
        type="checkbox"
        role="switch"
        checked={checked}
        disabled={disabled}
        onChange={(event) => onChange(event.target.checked)}
      />
      <span className="toggle-track" aria-hidden="true" />
    </label>
  );
}
