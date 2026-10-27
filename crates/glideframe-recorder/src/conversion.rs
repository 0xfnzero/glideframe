use crate::recorder::{RecorderError, RecorderResult};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::{Path, PathBuf},
    sync::atomic::{AtomicBool, Ordering},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConversionSettings {
    pub format: String,
    pub codec: String,
    pub resolution: String,
    pub frame_rate: String,
    pub quality: String,
    pub include_audio: bool,
}
static RUNNING: AtomicBool = AtomicBool::new(false);
#[cfg(not(target_os = "macos"))]
static CANCELLED: AtomicBool = AtomicBool::new(false);
struct ConversionGuard;
impl Drop for ConversionGuard {
    fn drop(&mut self) {
        RUNNING.store(false, Ordering::SeqCst);
    }
}

pub fn status() -> RecorderResult<String> {
    #[cfg(target_os = "macos")]
    {
        crate::platform::macos::call("conversion-status", &())
    }
    #[cfg(not(target_os = "macos"))]
    {
        let output = crate::platform::ffmpeg_command().arg("-version").output()?;
        if !output.status.success() {
            return Err(RecorderError::MissingFfmpeg);
        }
        Ok(String::from_utf8_lossy(&output.stdout)
            .lines()
            .next()
            .unwrap_or("FFmpeg")
            .into())
    }
}
pub fn cancel() -> RecorderResult<()> {
    #[cfg(target_os = "macos")]
    {
        crate::platform::macos::call::<bool>("cancel-conversion", &()).map(|_| ())
    }
    #[cfg(not(target_os = "macos"))]
    {
        CANCELLED.store(true, Ordering::SeqCst);
        Ok(())
    }
}
pub fn convert(
    input: &Path,
    directory: &Path,
    settings: ConversionSettings,
) -> RecorderResult<PathBuf> {
    if RUNNING
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return Err(RecorderError::InvalidOptions(
            "Another conversion is already running.".into(),
        ));
    }
    let _guard = ConversionGuard;
    let arguments = arguments(&settings)?;
    if !input.is_file() {
        return Err(RecorderError::MissingMediaFile(input.display().to_string()));
    }
    fs::create_dir_all(directory)?;
    let extension = if settings.format == "mpegTS" {
        "ts"
    } else {
        &settings.format
    };
    let stem = input.file_stem().unwrap_or_default().to_string_lossy();
    // Reserve the destination so existing files and concurrent writers are never overwritten.
    let mut index = 1;
    let output = loop {
        let suffix = if index == 1 {
            "-converted".into()
        } else {
            format!("-converted-{index}")
        };
        let path = directory.join(format!("{stem}{suffix}.{extension}"));
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
        {
            Ok(_) => break path,
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => index += 1,
            Err(error) => return Err(error.into()),
        }
    };
    #[cfg(target_os = "macos")]
    let result = {
        let _ = arguments;
        crate::platform::macos::call::<String>(
            "convert-media",
            &serde_json::json!({ "input": input, "output": output, "settings": settings }),
        )
        .map(|_| ())
    };
    #[cfg(not(target_os = "macos"))]
    let result = run_conversion(input, &output, &arguments);
    if let Err(error) = result {
        let _ = fs::remove_file(&output);
        return Err(error);
    }
    Ok(output)
}
#[cfg(not(target_os = "macos"))]
fn run_conversion(input: &Path, output: &Path, arguments: &[String]) -> RecorderResult<()> {
    use std::{process::Stdio, time::Duration};
    CANCELLED.store(false, Ordering::SeqCst);
    let log_path = std::env::temp_dir().join(format!(
        "glideframe-conversion-{}.log",
        uuid::Uuid::new_v4()
    ));
    let log = fs::File::create(&log_path)?;
    let mut child = crate::platform::ffmpeg_command()
        .args(["-hide_banner", "-nostdin", "-y", "-i"])
        .arg(input)
        .args(arguments)
        .arg(output)
        .stdout(Stdio::null())
        .stderr(Stdio::from(log))
        .spawn()?;
    let result = loop {
        if CANCELLED.load(Ordering::SeqCst) {
            let _ = child.kill();
            let _ = child.wait();
            break Err(RecorderError::InvalidOptions(
                "Conversion cancelled.".into(),
            ));
        }
        if let Some(status) = child.try_wait()? {
            break if status.success() {
                Ok(())
            } else {
                Err(RecorderError::InvalidOptions(
                    fs::read_to_string(&log_path)
                        .unwrap_or_else(|_| "Conversion failed.".into())
                        .chars()
                        .rev()
                        .take(1600)
                        .collect::<String>()
                        .chars()
                        .rev()
                        .collect(),
                ))
            };
        }
        std::thread::sleep(Duration::from_millis(100));
    };
    let _ = fs::remove_file(log_path);
    result
}

fn arguments(settings: &ConversionSettings) -> RecorderResult<Vec<String>> {
    let allowed: &[&str] = match settings.format.as_str() {
        "mp4" | "mpegTS" => &["h264", "hevc"],
        "m4v" => &["h264"],
        "mov" => &["h264", "hevc", "proRes"],
        "mkv" => &["h264", "hevc", "vp9", "av1", "proRes"],
        "webm" => &["vp9", "av1"],
        "avi" => &["mpeg4"],
        "wmv" => &["wmv2"],
        "flv" => &["flv"],
        "gif" => &["gif"],
        "mp3" => &["mp3"],
        "m4a" => &["aac"],
        "wav" => &["pcm"],
        "flac" => &["flac"],
        "ogg" | "opus" => &["opus"],
        _ => {
            return Err(RecorderError::InvalidOptions(
                "Unsupported output format.".into(),
            ))
        }
    };
    if !allowed.contains(&settings.codec.as_str()) {
        return Err(RecorderError::InvalidOptions(
            "The codec is incompatible with this container.".into(),
        ));
    }
    let quality = match settings.quality.as_str() {
        "high" => 0,
        "balanced" => 1,
        "compact" => 2,
        _ => {
            return Err(RecorderError::InvalidOptions(
                "Unsupported conversion quality.".into(),
            ))
        }
    };
    let resolution = match settings.resolution.as_str() {
        "source" => None,
        "uhd2160" => Some((3840, 2160)),
        "fullHD1080" => Some((1920, 1080)),
        "hd720" => Some((1280, 720)),
        "sd480" => Some((854, 480)),
        _ => {
            return Err(RecorderError::InvalidOptions(
                "Unsupported resolution.".into(),
            ))
        }
    };
    let fps = match settings.frame_rate.as_str() {
        "source" => None,
        "fps60" => Some(60),
        "fps30" => Some(30),
        "fps24" => Some(24),
        _ => {
            return Err(RecorderError::InvalidOptions(
                "Unsupported frame rate.".into(),
            ))
        }
    };
    let scale = resolution.map(|(w, h)| {
        format!("scale={w}:{h}:force_original_aspect_ratio=decrease:force_divisible_by=2")
    });
    let audio = matches!(
        settings.format.as_str(),
        "mp3" | "m4a" | "wav" | "flac" | "ogg" | "opus"
    );
    let mut args: Vec<String> = vec!["-map_metadata".into(), "0".into()];
    let mut add = |values: &[&str]| args.extend(values.iter().map(|value| value.to_string()));
    if audio {
        add(&[
            "-vn",
            "-map",
            "0:a:0",
            "-c:a",
            match settings.codec.as_str() {
                "mp3" => "libmp3lame",
                "aac" => "aac",
                "pcm" => "pcm_s16le",
                "flac" => "flac",
                _ => "libopus",
            },
        ]);
        if !matches!(settings.codec.as_str(), "pcm" | "flac") {
            add(&["-b:a", ["256k", "192k", "96k"][quality]]);
        }
    } else if settings.format == "gif" {
        add(&["-filter_complex", &format!("[0:v]fps={},{} ,split[s0][s1];[s0]palettegen=max_colors={}[p];[s1][p]paletteuse=dither=sierra2_4a[v]", fps.unwrap_or(15).min(30), scale.unwrap_or_else(|| "scale=iw:ih".into()), [256,192,128][quality]), "-map", "[v]", "-an", "-loop", "0"]);
    } else {
        add(&[
            "-map",
            "0:v:0",
            "-c:v",
            match settings.codec.as_str() {
                "h264" => "libx264",
                "hevc" => "libx265",
                "proRes" => "prores_ks",
                "vp9" => "libvpx-vp9",
                "av1" => "libsvtav1",
                "mpeg4" => "mpeg4",
                "wmv2" => "wmv2",
                _ => "flv",
            },
        ]);
        match settings.codec.as_str() {
            "h264" | "hevc" => add(&["-crf", ["18", "23", "29"][quality], "-pix_fmt", "yuv420p"]),
            "proRes" => add(&["-profile:v", "3", "-pix_fmt", "yuv422p10le"]),
            "vp9" | "av1" => add(&["-crf", ["24", "31", "38"][quality], "-b:v", "0"]),
            _ => add(&["-q:v", ["2", "5", "9"][quality]]),
        }
        if let Some(scale) = scale {
            add(&["-vf", &scale]);
        }
        if let Some(fps) = fps {
            add(&["-r", &fps.to_string()]);
        }
        if settings.include_audio {
            add(&[
                "-map",
                "0:a:0?",
                "-c:a",
                match settings.format.as_str() {
                    "webm" => "libopus",
                    "avi" => "libmp3lame",
                    "wmv" => "wmav1",
                    _ => "aac",
                },
                "-b:a",
                ["256k", "192k", "96k"][quality],
            ]);
        } else {
            add(&["-an"]);
        }
        if ["mp4", "mov", "m4v"].contains(&settings.format.as_str()) {
            add(&["-movflags", "+faststart"]);
        }
    }
    Ok(args)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn conversion_rejects_incompatible_codecs_and_preserves_paths_as_arguments() {
        let mut settings = ConversionSettings {
            format: "webm".into(),
            codec: "h264".into(),
            resolution: "source".into(),
            frame_rate: "source".into(),
            quality: "balanced".into(),
            include_audio: true,
        };
        assert!(arguments(&settings).is_err());
        settings.codec = "vp9".into();
        let args = arguments(&settings).unwrap();
        assert!(args.windows(2).any(|pair| pair == ["-c:v", "libvpx-vp9"]));
        assert!(args.windows(2).any(|pair| pair == ["-c:a", "libopus"]));
    }
}
