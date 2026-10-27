//! FFmpeg composition used by Windows; kept platform-neutral for media regression checks.
use crate::{
    models::{AspectRatio, CanvasBackground, ExportCodec, MediaSourceKind, ProjectManifest},
    recorder::{screen_source_path, ExportRequest, ExportSize, RecorderError, RecorderResult},
};
use std::{path::Path, process::Stdio};

pub(crate) fn export(
    project: &Path,
    manifest: &ProjectManifest,
    preset: &ExportRequest,
    destination: &Path,
) -> RecorderResult<()> {
    let mut command = crate::platform::ffmpeg_command();
    command
        .args(["-hide_banner", "-nostdin", "-y", "-i"])
        .arg(screen_source_path(project, manifest));
    let mut audio = Vec::new();
    for source in manifest.sources.iter().filter(|source| {
        matches!(
            source.kind,
            MediaSourceKind::SystemAudio | MediaSourceKind::Microphone
        )
    }) {
        let track = manifest
            .tracks
            .iter()
            .find(|track| track.source_id == source.id);
        if track.is_some_and(|track| !track.is_enabled || track.volume <= 0.0) {
            continue;
        }
        let path = project.join(&source.relative_path);
        if !path.is_file() {
            continue;
        }
        let screen_path = screen_source_path(project, manifest);
        let index = if path == screen_path {
            0
        } else {
            command.arg("-i").arg(&path);
            audio.iter().filter(|(index, _)| *index != 0).count() + 1
        };
        audio.push((index, track.map(|track| track.volume).unwrap_or(1.0)));
    }
    if !manifest
        .sources
        .iter()
        .any(|source| matches!(source.kind, MediaSourceKind::SystemAudio))
    {
        let track = manifest
            .tracks
            .iter()
            .find(|track| matches!(track.kind, MediaSourceKind::Screen));
        let probe = crate::platform::ffprobe_command()
            .args([
                "-v",
                "error",
                "-select_streams",
                "a:0",
                "-show_entries",
                "stream=index",
                "-of",
                "csv=p=0",
            ])
            .arg(screen_source_path(project, manifest))
            .output()?;
        if !probe.stdout.is_empty() && track.is_none_or(|track| track.is_enabled) {
            audio.push((0, track.map(|track| track.volume).unwrap_or(1.0)));
        }
    }
    let filter = composition_filter(manifest, preset, &audio)?;
    command.args(["-filter_complex", &filter, "-map", "[video]"]);
    if audio.is_empty() {
        command.arg("-an");
    } else {
        command.args(["-map", "[audio]", "-c:a", "aac"]);
    }
    let output = command
        .args([
            "-c:v",
            if matches!(manifest.export_preset.codec, ExportCodec::Hevc) {
                "libx265"
            } else {
                "libx264"
            },
            "-crf",
            "20",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
        ])
        .arg(destination)
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .output()?;
    if !output.status.success() {
        let _ = std::fs::remove_file(destination);
        return Err(RecorderError::InvalidOptions(
            String::from_utf8_lossy(&output.stderr)
                .chars()
                .rev()
                .take(2400)
                .collect::<String>()
                .chars()
                .rev()
                .collect(),
        ));
    }
    Ok(())
}

fn composition_filter(
    manifest: &ProjectManifest,
    preset: &ExportRequest,
    audio: &[(usize, f64)],
) -> RecorderResult<String> {
    let ranges = if manifest.edit_graph.clips.is_empty() {
        vec![(0.0, manifest.duration)]
    } else {
        manifest
            .edit_graph
            .clips
            .iter()
            .filter(|clip| !clip.is_removed)
            .map(|clip| (clip.source_range.start, clip.source_range.duration))
            .collect()
    };
    if ranges.is_empty() || ranges.iter().any(|(_, duration)| *duration <= 0.0) {
        return Err(RecorderError::InvalidOptions(
            "The export timeline is empty.".into(),
        ));
    }
    let duration: f64 = ranges.iter().map(|(_, duration)| duration).sum();
    let (mut width, mut height) = match preset.size {
        ExportSize::Project => (manifest.export_preset.width, manifest.export_preset.height),
        ExportSize::Hd => (1920, 1080),
        ExportSize::UltraHd => (3840, 2160),
        ExportSize::Source => manifest
            .sources
            .iter()
            .find(|source| matches!(source.kind, MediaSourceKind::Screen))
            .map(|source| (source.width.unwrap_or(1920), source.height.unwrap_or(1080)))
            .unwrap_or((1920, 1080)),
    };
    if !matches!(preset.size, ExportSize::Source) {
        match manifest.canvas.aspect_ratio {
            AspectRatio::Portrait => {
                let long = width.max(height);
                let short = width.min(height);
                width = short;
                height = long;
            }
            AspectRatio::Square => {
                height = width.min(height);
                width = height;
            }
            _ => {}
        }
    }
    width = width / 2 * 2;
    height = height / 2 * 2;
    let padding = if matches!(preset.size, ExportSize::Source) {
        0.0
    } else {
        manifest.canvas.padding.min(width.min(height) as f64 / 3.0)
    };
    let inner_w = ((width as f64 - 2.0 * padding) as u32 / 2 * 2).max(2);
    let inner_h = ((height as f64 - 2.0 * padding) as u32 / 2 * 2).max(2);
    let background = match manifest.canvas.background {
        CanvasBackground::Graphite => "0x0e1013",
        CanvasBackground::Daylight => "0xebf0f5",
        CanvasBackground::Mint => "0x296b5c",
        CanvasBackground::Coral => "0xc73d38",
    };
    let fps = manifest.export_preset.frame_rate;
    let mut parts = Vec::new();
    for (clip, (start, length)) in ranges.iter().enumerate() {
        parts.push(format!(
            "[0:v]trim=start={start}:duration={length},setpts=PTS-STARTPTS[v{clip}]"
        ));
        for (track, (input, volume)) in audio.iter().enumerate() {
            parts.push(format!("[{input}:a]atrim=start={start}:duration={length},asetpts=PTS-STARTPTS,volume={volume},apad,atrim=duration={length}[a{track}c{clip}]"));
        }
    }
    parts.push(format!("{}concat=n={}:v=1:a=0,scale={inner_w}:{inner_h}:force_original_aspect_ratio=decrease:force_divisible_by=2,fps={fps},format=rgba[scaledRaw]", (0..ranges.len()).map(|index| format!("[v{index}]")).collect::<String>(), ranges.len()));
    // Keyframes use source time; map each surviving clip to its output position.
    let mut frames = Vec::new();
    let mut cursor = 0.0;
    for (start, length) in &ranges {
        let mut initial = (1.0, 0.5, 0.5);
        for frame in &manifest.edit_graph.zoom_keyframes {
            if frame.time <= *start {
                initial = (frame.scale, frame.focus_x, frame.focus_y);
            }
        }
        frames.push((cursor, initial.0, initial.1, initial.2));
        frames.extend(
            manifest
                .edit_graph
                .zoom_keyframes
                .iter()
                .filter(|frame| frame.time > *start && frame.time < start + length)
                .map(|frame| {
                    (
                        cursor + frame.time - start,
                        frame.scale,
                        frame.focus_x,
                        frame.focus_y,
                    )
                }),
        );
        cursor += length;
    }
    let expression = |field: usize, fallback: f64| {
        frames.iter().fold(fallback.to_string(), |previous, frame| {
            let value = match field {
                0 => frame.1,
                1 => frame.2,
                _ => frame.3,
            };
            format!("if(gte(in_time,{}),{value},{previous})", frame.0)
        })
    };
    let source = manifest
        .sources
        .iter()
        .find(|source| matches!(source.kind, MediaSourceKind::Screen));
    let source_w = source.and_then(|source| source.width).unwrap_or(1920) as f64;
    let source_h = source.and_then(|source| source.height).unwrap_or(1080) as f64;
    let fit = (inner_w as f64 / source_w).min(inner_h as f64 / source_h);
    let fitted_w = ((source_w * fit) as u32 / 2 * 2).max(2);
    let fitted_h = ((source_h * fit) as u32 / 2 * 2).max(2);
    if manifest.edit_graph.zoom_keyframes.is_empty() {
        parts.push("[scaledRaw]null[scaled]".into());
    } else {
        parts.push(format!("[scaledRaw]zoompan=z='{}':x='iw*({})*(1-1/zoom)':y='ih*({})*(1-1/zoom)':d=1:s={fitted_w}x{fitted_h}:fps={fps},format=rgba[scaled]", expression(0,1.0), expression(1,0.5), expression(2,0.5)));
    }
    let radius = manifest.canvas.corner_radius;
    parts.push(format!("[scaled]geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lte(pow(max(abs(X-W/2)-(W/2-{radius}),0),2)+pow(max(abs(Y-H/2)-(H/2-{radius}),0),2),{radius}*{radius}),255,0)'[rounded]"));
    parts.push(format!(
        "color=c={background}:s={width}x{height}:r={fps}:d={duration}[background]"
    ));
    parts.push("[rounded]split[foreground][shadowInput]".into());
    parts.push(format!("[shadowInput]pad=iw+80:ih+80:40:40:color=black@0,colorchannelmixer=rr=0:gg=0:bb=0:aa={},gblur=sigma=20[shadow]", manifest.canvas.shadow));
    parts.push("[background][shadow]overlay=(W-w)/2:(H-h)/2+8:shortest=1[withShadow]".into());
    parts.push("[withShadow][foreground]overlay=(W-w)/2:(H-h)/2:shortest=1[video]".into());
    for (track, _) in audio.iter().enumerate() {
        parts.push(format!(
            "{}concat=n={}:v=0:a=1[a{track}]",
            (0..ranges.len())
                .map(|clip| format!("[a{track}c{clip}]"))
                .collect::<String>(),
            ranges.len()
        ));
    }
    if !audio.is_empty() {
        parts.push(format!(
            "{}amix=inputs={}:normalize=0:duration=longest[audio]",
            (0..audio.len())
                .map(|track| format!("[a{track}]"))
                .collect::<String>(),
            audio.len()
        ));
    }
    Ok(parts.join(";"))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ffmpeg_composition_exports_trimmed_styled_media() {
        if !crate::platform::ffmpeg_command()
            .arg("-version")
            .output()
            .is_ok_and(|output| output.status.success())
        {
            return;
        }
        let root = std::env::temp_dir().join(format!("glideframe-export-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(root.join("media")).unwrap();
        assert!(crate::platform::ffmpeg_command()
            .args([
                "-hide_banner",
                "-loglevel",
                "error",
                "-f",
                "lavfi",
                "-i",
                "testsrc2=size=320x180:rate=30:duration=2",
                "-f",
                "lavfi",
                "-i",
                "sine=frequency=440:duration=2",
                "-c:v",
                "libx264",
                "-c:a",
                "aac",
                "-shortest"
            ])
            .arg(root.join("media/screen.mp4"))
            .status()
            .unwrap()
            .success());
        let mut manifest = ProjectManifest::new("Media regression");
        manifest.duration = 2.0;
        manifest.export_preset.width = 320;
        manifest.export_preset.height = 180;
        manifest.canvas.aspect_ratio = AspectRatio::Square;
        manifest.canvas.padding = 20.0;
        manifest.sources.push(crate::models::MediaSource {
            id: uuid::Uuid::new_v4(),
            kind: MediaSourceKind::Screen,
            relative_path: "media/screen.mp4".into(),
            duration: 2.0,
            width: Some(320),
            height: Some(180),
            frame_rate: Some(30.0),
        });
        manifest.sources.push(crate::models::MediaSource {
            id: uuid::Uuid::new_v4(),
            kind: MediaSourceKind::SystemAudio,
            relative_path: "media/screen.mp4".into(),
            duration: 2.0,
            width: None,
            height: None,
            frame_rate: None,
        });
        manifest.edit_graph.clips.push(crate::models::ClipEdit {
            id: uuid::Uuid::new_v4(),
            source_range: crate::models::MediaTimeRange {
                start: 0.5,
                duration: 1.0,
            },
            is_removed: false,
        });
        manifest
            .edit_graph
            .zoom_keyframes
            .push(crate::models::ZoomKeyframe {
                id: uuid::Uuid::new_v4(),
                time: 0.8,
                scale: 1.2,
                focus_x: 0.4,
                focus_y: 0.6,
            });
        let output = root.join("export.mp4");
        export(
            &root,
            &manifest,
            &ExportRequest {
                name: "project".into(),
                size: ExportSize::Project,
            },
            &output,
        )
        .unwrap();
        assert!(crate::platform::ffmpeg_command()
            .args(["-v", "error", "-i"])
            .arg(&output)
            .args(["-f", "null", "-"])
            .output()
            .unwrap()
            .status
            .success());
        let probe = std::process::Command::new("ffprobe")
            .args([
                "-v",
                "error",
                "-show_streams",
                "-show_format",
                "-of",
                "json",
            ])
            .arg(&output)
            .output()
            .unwrap();
        let metadata: serde_json::Value = serde_json::from_slice(&probe.stdout).unwrap();
        assert_eq!(metadata["streams"][0]["width"], 180);
        assert_eq!(metadata["streams"][0]["height"], 180);
        let duration = metadata["format"]["duration"]
            .as_str()
            .unwrap()
            .parse::<f64>()
            .unwrap();
        assert!((duration - 1.0).abs() < 0.1);
        std::fs::remove_dir_all(root).unwrap();
    }
}
