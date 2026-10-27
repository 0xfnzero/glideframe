import { useRef, useState } from "react";
import type { CSSProperties } from "react";
import {
  Camera,
  Check,
  Mic,
  Monitor,
  Play,
  Volume2,
  Wand2,
} from "lucide-react";
import { convertFileSrc } from "@tauri-apps/api/core";
import type { CanvasStyle, ProjectManifest, Translate } from "../types";

export const backgrounds = {
  graphite: "#0e1013",
  daylight: "#ebf0f5",
  mint: "#296b5c",
  coral: "#c73d38",
};
export const formatTime = (seconds: number) =>
  `${Math.floor(Math.max(0, seconds) / 60)
    .toString()
    .padStart(2, "0")}:${Math.floor(Math.max(0, seconds) % 60)
    .toString()
    .padStart(2, "0")}`;

export function Studio({
  manifest,
  path,
  onChange,
  t,
  disabled,
}: {
  manifest: ProjectManifest;
  path: string;
  onChange: (manifest: ProjectManifest) => void;
  t: Translate;
  disabled?: boolean;
}) {
  const video = useRef<HTMLVideoElement>(null);
  const [position, setPosition] = useState(0);
  const [playing, setPlaying] = useState(false);
  const screen = manifest.sources.find((source) => source.kind === "screen");
  const range = manifest.editGraph.clips.find(
    (clip) => !clip.isRemoved,
  )?.sourceRange;
  const start = range?.start ?? 0;
  const end = range ? range.start + range.duration : manifest.duration;
  const duration = Math.max(0.1, manifest.duration);
  const canvas = manifest.canvas;
  const ratio =
    canvas.aspectRatio === "landscape"
      ? 16 / 9
      : canvas.aspectRatio === "portrait"
        ? 9 / 16
        : 1;
  const outputWidth =
    canvas.aspectRatio === "landscape"
      ? Math.max(manifest.exportPreset.width, manifest.exportPreset.height)
      : Math.min(manifest.exportPreset.width, manifest.exportPreset.height);
  function updateCanvas(patch: Partial<CanvasStyle>) {
    onChange({ ...manifest, canvas: { ...canvas, ...patch } });
  }
  function trim(nextStart: number, nextEnd: number) {
    onChange({
      ...manifest,
      editGraph: {
        ...manifest.editGraph,
        clips: [
          {
            id: manifest.editGraph.clips[0]?.id ?? crypto.randomUUID(),
            sourceRange: { start: nextStart, duration: nextEnd - nextStart },
            isRemoved: false,
          },
        ],
      },
    });
    if (video.current) video.current.currentTime = nextStart;
  }
  function autoPolish() {
    let last = -Infinity;
    const zoomKeyframes = manifest.pointerEvents
      .filter((event) => event.kind === "click")
      .sort((a, b) => a.time - b.time)
      .filter((event) => {
        if (event.time - last < 1.25) return false;
        last = event.time;
        return true;
      })
      .flatMap((event) =>
        [
          [Math.max(0, event.time - 0.22), 1],
          [event.time, 1.45],
          [event.time + 0.72, 1.45],
          [event.time + 1.05, 1],
        ].map(([time, scale]) => ({
          id: crypto.randomUUID(),
          time,
          scale,
          focusX: event.x,
          focusY: event.y,
        })),
      );
    onChange({
      ...manifest,
      editGraph: { ...manifest.editGraph, zoomKeyframes },
    });
  }
  const trackName = (kind: string) =>
    ({
      screen: t("屏幕", "Screen"),
      systemAudio: t("系统音频", "System audio"),
      microphone: t("麦克风", "Microphone"),
      camera: t("摄像头", "Camera"),
    })[kind] ?? kind;
  return (
    <div className="studio" inert={disabled}>
      <div className="studio-main">
        <div className="preview-area">
          <div
            className="canvas-wrap"
            style={{ "--ratio": ratio } as CSSProperties}
          >
            <div
              className="preview-canvas"
              style={{
                containerType: "size",
                background: backgrounds[canvas.background],
                padding: `calc(min(100cqw, 100cqh * var(--ratio)) * ${canvas.padding / outputWidth})`,
                aspectRatio: ratio,
              }}
            >
              {screen && (
                <video
                  key={path}
                  ref={video}
                  src={convertFileSrc(`${path}/${screen.relativePath}`)}
                  playsInline
                  style={{
                    width: `min(100cqw, 100cqh * ${(screen.width ?? 1920) / (screen.height ?? 1080)})`,
                    height: `min(100cqh, 100cqw / ${(screen.width ?? 1920) / (screen.height ?? 1080)})`,
                    borderRadius: `calc(100cqw * ${canvas.cornerRadius / outputWidth})`,
                    boxShadow: `0 calc(100cqw * ${8 / outputWidth}) calc(100cqw * ${20 / outputWidth}) rgba(0,0,0,${canvas.shadow})`,
                  }}
                  onTimeUpdate={() => {
                    const player = video.current;
                    if (!player) return;
                    setPosition(player.currentTime);
                    if (player.currentTime >= end && !player.paused) {
                      player.pause();
                      player.currentTime = start;
                    }
                  }}
                  onPlay={() => setPlaying(true)}
                  onPause={() => setPlaying(false)}
                  onLoadedMetadata={() => {
                    if (video.current) video.current.currentTime = start;
                  }}
                />
              )}
            </div>
          </div>
          <div className="playback-bar">
            <button
              className="icon-button"
              title={
                playing ? t("暂停播放", "Pause playback") : t("播放", "Play")
              }
              onClick={() => {
                const player = video.current;
                if (!player) return;
                if (playing) player.pause();
                else {
                  if (player.currentTime < start || player.currentTime >= end)
                    player.currentTime = start;
                  void player.play();
                }
              }}
            >
              {playing ? (
                <span className="pause-glyph">Ⅱ</span>
              ) : (
                <Play size={15} fill="currentColor" />
              )}
            </button>
            <span className="timecode">{formatTime(position)}</span>
            <input
              aria-label={t("播放进度", "Playback position")}
              type="range"
              min={start}
              max={Math.max(start + 0.01, end)}
              step="0.01"
              value={Math.max(start, Math.min(end, position))}
              onChange={(event) => {
                if (video.current)
                  video.current.currentTime = Number(event.target.value);
                setPosition(Number(event.target.value));
              }}
            />
            <span className="timecode muted">{formatTime(end - start)}</span>
          </div>
        </div>
        <section className="timeline">
          <header>
            <h2>{t("时间线", "Timeline")}</h2>
            <span className="timecode muted">{formatTime(end - start)}</span>
          </header>
          <div className="track-list">
            {manifest.tracks.map((track) => (
              <div className="track-row" key={track.id}>
                {track.kind === "screen" ? (
                  <Monitor />
                ) : track.kind === "camera" ? (
                  <Camera />
                ) : track.kind === "microphone" ? (
                  <Mic />
                ) : (
                  <Volume2 />
                )}
                <span>{trackName(track.kind)}</span>
                <div
                  className={`track-rail ${track.kind === "screen" ? "screen" : "audio"}`}
                >
                  <div
                    style={{
                      left: `${(start / duration) * 100}%`,
                      width: `${((end - start) / duration) * 100}%`,
                    }}
                  />
                </div>
              </div>
            ))}
          </div>
          <div className="trim-row">
            <span>{t("裁剪", "Trim")}</span>
            <label>
              <span className="sr-only">{t("裁剪起点", "Trim start")}</span>
              <input
                type="range"
                min="0"
                max={Math.max(0, end - 0.1)}
                step="0.1"
                value={start}
                onChange={(event) => trim(Number(event.target.value), end)}
              />
            </label>
            <output>{formatTime(start)}</output>
            <label>
              <span className="sr-only">{t("裁剪终点", "Trim end")}</span>
              <input
                type="range"
                min={Math.min(duration, start + 0.1)}
                max={duration}
                step="0.1"
                value={end}
                onChange={(event) => trim(start, Number(event.target.value))}
              />
            </label>
            <output>{formatTime(end)}</output>
          </div>
        </section>
      </div>
      <aside className="inspector">
        <header>
          <h2>{t("样式", "Style")}</h2>
        </header>
        <section>
          <h3>{t("背景", "Background")}</h3>
          <div className="swatches">
            {(Object.keys(backgrounds) as Array<keyof typeof backgrounds>).map(
              (background) => (
                <button
                  key={background}
                  className={`swatch ${canvas.background === background ? "selected" : ""}`}
                  style={{ background: backgrounds[background] }}
                  aria-label={
                    {
                      graphite: t("石墨", "Graphite"),
                      daylight: t("日光", "Daylight"),
                      mint: t("薄荷", "Mint"),
                      coral: t("珊瑚", "Coral"),
                    }[background]
                  }
                  aria-pressed={canvas.background === background}
                  onClick={() => updateCanvas({ background })}
                >
                  {canvas.background === background && (
                    <Check
                      size={14}
                      color={background === "daylight" ? "#333" : "white"}
                    />
                  )}
                </button>
              ),
            )}
          </div>
        </section>
        <section>
          <h3>{t("画面比例", "Aspect ratio")}</h3>
          <div className="segmented">
            {(
              [
                ["landscape", "16:9"],
                ["portrait", "9:16"],
                ["square", "1:1"],
              ] as const
            ).map(([aspectRatio, label]) => (
              <button
                key={aspectRatio}
                aria-pressed={canvas.aspectRatio === aspectRatio}
                onClick={() => updateCanvas({ aspectRatio })}
              >
                {label}
              </button>
            ))}
          </div>
        </section>
        <section>
          <h3>{t("画框", "Frame")}</h3>
          <label className="slider-row">
            <span>{t("留白", "Padding")}</span>
            <input
              type="range"
              min="0"
              max="140"
              value={canvas.padding}
              onChange={(event) =>
                updateCanvas({ padding: Number(event.target.value) })
              }
            />
            <output>{Math.round(canvas.padding)}</output>
          </label>
          <label className="slider-row">
            <span>{t("圆角", "Corners")}</span>
            <input
              type="range"
              min="0"
              max="40"
              value={canvas.cornerRadius}
              onChange={(event) =>
                updateCanvas({ cornerRadius: Number(event.target.value) })
              }
            />
            <output>{Math.round(canvas.cornerRadius)}</output>
          </label>
        </section>
        <section className="polish-section">
          <button className="wide-button primary-button" onClick={autoPolish}>
            <Wand2 />
            {t("自动运镜", "Auto Polish")}
          </button>
        </section>
      </aside>
    </div>
  );
}
