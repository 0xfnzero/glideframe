use crate::{
    models::{
        AudioDevice, CameraDevice, CaptureSource, CaptureSourceType, FrameRect, ProjectManifest,
        RecordingOptions,
    },
    platform::{self, RecorderBackend},
    recorder::{RecorderError, RecorderResult},
};
use cpal::{
    traits::{DeviceTrait, HostTrait, StreamTrait},
    FromSample, SampleFormat, SizedSample,
};
use std::os::windows::process::CommandExt;
use std::{
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};
use windows::Win32::{
    Foundation::{HWND, RECT},
    UI::WindowsAndMessaging::{GetSystemMetrics, GetWindowRect, SM_CXSCREEN, SM_CYSCREEN},
};

pub struct WindowsBackend;
impl RecorderBackend for WindowsBackend {
    fn list_capture_sources() -> RecorderResult<Vec<CaptureSource>> {
        let (width, height) =
            unsafe { (GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)) };
        let mut sources = vec![CaptureSource {
            id: "display:primary".into(),
            source_type: CaptureSourceType::Display,
            title: "Primary display".into(),
            subtitle: format!("{width} x {height}"),
            native_id: Some(0),
            display_id: Some(0),
            frame: FrameRect {
                x: 0.0,
                y: 0.0,
                width: width as f64,
                height: height as f64,
            },
            app_icon_path: None,
            preview_image_path: None,
        }];
        let output = hidden_command("powershell.exe").args(["-NoProfile", "-Command", "Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } | Select-Object ProcessName,MainWindowHandle,MainWindowTitle | ConvertTo-Json -Compress"]).output()?;
        if output.status.success() && !output.stdout.is_empty() {
            let json: serde_json::Value =
                serde_json::from_slice(&output.stdout).map_err(RecorderError::Json)?;
            let entries = json.as_array().cloned().unwrap_or_else(|| vec![json]);
            for entry in entries {
                let Some(handle) = entry["MainWindowHandle"].as_u64() else {
                    continue;
                };
                let mut rect = RECT::default();
                if unsafe { GetWindowRect(HWND(handle as *mut _), &mut rect) }.is_err() {
                    continue;
                }
                let (width, height) = (rect.right - rect.left, rect.bottom - rect.top);
                if width < 64 || height < 64 {
                    continue;
                }
                sources.push(CaptureSource {
                    id: format!("window:{handle}"),
                    source_type: CaptureSourceType::Window,
                    title: entry["MainWindowTitle"].as_str().unwrap_or("Window").into(),
                    subtitle: entry["ProcessName"].as_str().unwrap_or("").into(),
                    native_id: Some(handle),
                    display_id: None,
                    frame: FrameRect {
                        x: rect.left as f64,
                        y: rect.top as f64,
                        width: width as f64,
                        height: height as f64,
                    },
                    app_icon_path: None,
                    preview_image_path: None,
                });
            }
        }
        Ok(sources)
    }
    fn list_audio_devices() -> RecorderResult<Vec<AudioDevice>> {
        let host = cpal::default_host();
        let mut devices = Vec::new();
        if let Some(device) = host.default_output_device() {
            devices.push(AudioDevice {
                id: "system:default".into(),
                name: device.name().map_err(native_error)?,
                is_default: true,
                kind: crate::models::AudioDeviceKind::SystemAudio,
            });
        }
        if let Some(device) = host.default_input_device() {
            devices.push(AudioDevice {
                id: "microphone:default".into(),
                name: device.name().map_err(native_error)?,
                is_default: true,
                kind: crate::models::AudioDeviceKind::Microphone,
            });
        }
        Ok(devices)
    }
    fn list_camera_devices() -> RecorderResult<Vec<CameraDevice>> {
        Ok(Vec::new())
    }
    fn ensure_capture_available() -> RecorderResult<()> {
        platform::ensure_ffmpeg_available()
    }
    fn start_capture(
        options: &RecordingOptions,
        target: &CaptureSource,
        _: &ProjectManifest,
        project_path: &Path,
    ) -> RecorderResult<Vec<Child>> {
        if options.record_camera {
            return Err(RecorderError::CameraCaptureUnsupported);
        }
        let child = hidden_command(std::env::current_exe()?)
            .arg("--record-worker")
            .arg(project_path)
            .arg(serde_json::to_string(options)?)
            .arg(serde_json::to_string(target)?)
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .spawn()?;
        platform::wait_for_recording_ready(child, project_path)
    }
}

pub fn hidden_command(program: impl AsRef<std::ffi::OsStr>) -> Command {
    let mut command = Command::new(program);
    command.creation_flags(0x08000000); // CREATE_NO_WINDOW
    command
}
fn native_error(error: impl std::fmt::Display) -> RecorderError {
    RecorderError::Io(std::io::Error::other(error.to_string()))
}

type WaveFile = hound::WavWriter<std::io::BufWriter<File>>;
struct AudioCapture {
    stream: cpal::Stream,
    writer: Arc<Mutex<Option<WaveFile>>>,
    failure: Arc<Mutex<Option<String>>>,
}
impl AudioCapture {
    fn start(path: &Path, loopback: bool, paused: Arc<AtomicBool>) -> RecorderResult<Self> {
        let host = cpal::default_host();
        let device = if loopback {
            host.default_output_device()
        } else {
            host.default_input_device()
        }
        .ok_or_else(|| {
            native_error(if loopback {
                "No system audio output device is available."
            } else {
                "No microphone is available. Disable Microphone to record without it."
            })
        })?;
        let config = if loopback {
            device.default_output_config()
        } else {
            device.default_input_config()
        }
        .map_err(native_error)?;
        let spec = hound::WavSpec {
            channels: config.channels(),
            sample_rate: config.sample_rate().0,
            bits_per_sample: 32,
            sample_format: hound::SampleFormat::Float,
        };
        let writer = Arc::new(Mutex::new(Some(
            hound::WavWriter::create(path, spec).map_err(native_error)?,
        )));
        let failure = Arc::new(Mutex::new(None));
        let stream = match config.sample_format() {
            SampleFormat::F32 => audio_stream::<f32>(
                &device,
                &config.into(),
                writer.clone(),
                failure.clone(),
                paused,
            ),
            SampleFormat::I16 => audio_stream::<i16>(
                &device,
                &config.into(),
                writer.clone(),
                failure.clone(),
                paused,
            ),
            SampleFormat::I32 => audio_stream::<i32>(
                &device,
                &config.into(),
                writer.clone(),
                failure.clone(),
                paused,
            ),
            SampleFormat::U16 => audio_stream::<u16>(
                &device,
                &config.into(),
                writer.clone(),
                failure.clone(),
                paused,
            ),
            other => return Err(native_error(format!("Unsupported audio format: {other:?}"))),
        }?;
        stream.play().map_err(native_error)?;
        Ok(Self {
            stream,
            writer,
            failure,
        })
    }
    fn finish(self) -> RecorderResult<()> {
        drop(self.stream);
        if let Some(writer) = self.writer.lock().map_err(native_error)?.take() {
            writer.finalize().map_err(native_error)?;
        }
        if let Some(error) = self.failure.lock().map_err(native_error)?.take() {
            return Err(native_error(error));
        }
        Ok(())
    }
}
fn audio_stream<T: SizedSample>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    writer: Arc<Mutex<Option<WaveFile>>>,
    failure: Arc<Mutex<Option<String>>>,
    paused: Arc<AtomicBool>,
) -> RecorderResult<cpal::Stream>
where
    f32: FromSample<T>,
{
    let write_failure = failure.clone();
    device
        .build_input_stream(
            config,
            move |samples: &[T], _| {
                if paused.load(Ordering::Relaxed) {
                    return;
                }
                if let Ok(mut writer) = writer.lock() {
                    if let Some(writer) = writer.as_mut() {
                        for sample in samples {
                            if let Err(error) = writer.write_sample(sample.to_sample::<f32>()) {
                                if let Ok(mut failure) = write_failure.lock() {
                                    *failure = Some(error.to_string());
                                }
                                break;
                            }
                        }
                    }
                }
            },
            move |error| {
                if let Ok(mut failure) = failure.lock() {
                    *failure = Some(error.to_string());
                }
            },
            None,
        )
        .map_err(native_error)
}

// The worker has one control protocol on every platform: p toggles pause, q stops.
// FFmpeg has no recording pause command. Finalizing separate screen segments
// removes the paused interval instead of leaving a gap or a frozen frame.
pub fn run_recording_worker() -> RecorderResult<()> {
    let args: Vec<_> = std::env::args().skip(2).collect();
    if args.len() != 3 {
        return Err(native_error("Invalid recorder worker arguments."));
    }
    let project_path = PathBuf::from(&args[0]);
    let options: RecordingOptions = serde_json::from_str(&args[1])?;
    let target: CaptureSource = serde_json::from_str(&args[2])?;
    let media = project_path.join("media");
    fs::create_dir_all(&media)?;
    let paused = Arc::new(AtomicBool::new(false));
    let mut audio = Vec::new();
    if options.record_system_audio {
        audio.push(AudioCapture::start(
            &media.join("system-audio.wav"),
            true,
            paused.clone(),
        )?);
    }
    if options.record_microphone {
        audio.push(AudioCapture::start(
            &media.join("microphone.wav"),
            false,
            paused.clone(),
        )?);
    }
    let mut segments = vec![media.join("segment-0.mp4")];
    let mut screen = Some(spawn_screen(&options, &target, &segments[0], &media)?);
    fs::write(project_path.join("recording-ready.json"), "true")?;
    let mut control = [0u8; 1];
    while std::io::stdin().read(&mut control)? != 0 {
        match control[0] {
            b'q' => break,
            b'p' if !paused.load(Ordering::Relaxed) => {
                paused.store(true, Ordering::Relaxed);
                if let Some(child) = screen.take() {
                    stop_screen(child, &media)?;
                }
            }
            b'p' => {
                segments.push(media.join(format!("segment-{}.mp4", segments.len())));
                screen = Some(spawn_screen(
                    &options,
                    &target,
                    segments.last().unwrap(),
                    &media,
                )?);
                paused.store(false, Ordering::Relaxed);
            }
            _ => {}
        }
    }
    paused.store(true, Ordering::Relaxed);
    if let Some(child) = screen.take() {
        stop_screen(child, &media)?;
    }
    for capture in audio {
        capture.finish()?;
    }
    let output = media.join("screen.mp4");
    if segments.len() == 1 {
        fs::rename(&segments[0], &output)?;
    } else {
        let list = media.join("segments.txt");
        // Only generated basenames are passed to the concat demuxer.
        fs::write(
            &list,
            (0..segments.len())
                .map(|i| format!("file 'segment-{i}.mp4'\n"))
                .collect::<String>(),
        )?;
        let result = platform::ffmpeg_command()
            .args(["-y", "-f", "concat", "-safe", "0", "-i"])
            .arg(&list)
            .args(["-c", "copy", "-movflags", "+faststart"])
            .arg(&output)
            .output()?;
        if !result.status.success() {
            return Err(native_error(String::from_utf8_lossy(&result.stderr)));
        }
        for segment in segments {
            let _ = fs::remove_file(segment);
        }
        let _ = fs::remove_file(list);
    }
    let probe = platform::ffprobe_command()
        .args([
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height:format=duration",
            "-of",
            "json",
        ])
        .arg(&output)
        .output()?;
    if !probe.status.success() {
        return Err(native_error(String::from_utf8_lossy(&probe.stderr)));
    }
    let value: serde_json::Value = serde_json::from_slice(&probe.stdout)?;
    let duration = value["format"]["duration"]
        .as_str()
        .and_then(|value| value.parse::<f64>().ok())
        .ok_or_else(|| native_error("The recording has no duration."))?;
    fs::write(
        project_path.join("recording-result.json"),
        serde_json::to_vec(
            &serde_json::json!({"duration": duration, "width": value["streams"][0]["width"], "height": value["streams"][0]["height"]}),
        )?,
    )?;
    Ok(())
}
fn spawn_screen(
    options: &RecordingOptions,
    target: &CaptureSource,
    destination: &Path,
    media: &Path,
) -> RecorderResult<Child> {
    let mut command = platform::ffmpeg_command();
    command
        .args(["-y", "-f", "gdigrab", "-framerate"])
        .arg(options.frame_rate.to_string());
    if let Some(region) = &options.region {
        let (x, y) = if target.source_type == CaptureSourceType::Window {
            (region.x - target.frame.x, region.y - target.frame.y)
        } else {
            (region.x, region.y)
        };
        if x < 0.0
            || y < 0.0
            || x + region.width > target.frame.width
            || y + region.height > target.frame.height
        {
            return Err(native_error(
                "The selected region is outside the recording source.",
            ));
        }
        command
            .arg("-offset_x")
            .arg(x.round().to_string())
            .arg("-offset_y")
            .arg(y.round().to_string())
            .arg("-video_size")
            .arg(format!(
                "{}x{}",
                (region.width as u32) & !1,
                (region.height as u32) & !1
            ));
    }
    command
        .arg("-i")
        .arg(if target.source_type == CaptureSourceType::Window {
            format!("hwnd=0x{:x}", target.native_id.unwrap_or_default())
        } else {
            "desktop".into()
        })
        .args([
            "-vf",
            "scale=trunc(iw/2)*2:trunc(ih/2)*2",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
        ])
        .arg(destination)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::from(
            OpenOptions::new()
                .create(true)
                .append(true)
                .open(media.join("capture.log"))?,
        ));
    let mut child = command.spawn()?;
    let deadline = Instant::now() + Duration::from_secs(10);
    loop {
        if let Some(status) = child.try_wait()? {
            return Err(native_error(format!(
                "Screen recorder exited ({status}): {}",
                fs::read_to_string(media.join("capture.log")).unwrap_or_default()
            )));
        }
        if fs::metadata(destination).is_ok_and(|metadata| metadata.len() > 0) {
            return Ok(child);
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            let _ = child.wait();
            return Err(native_error("No screen frames were received."));
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}
fn stop_screen(mut child: Child, media: &Path) -> RecorderResult<()> {
    if let Some(stdin) = child.stdin.as_mut() {
        let _ = stdin.write_all(b"q");
    }
    let deadline = Instant::now() + Duration::from_secs(15);
    loop {
        if let Some(status) = child.try_wait()? {
            if status.success() {
                return Ok(());
            }
            return Err(native_error(
                fs::read_to_string(media.join("capture.log")).unwrap_or_default(),
            ));
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            let _ = child.wait();
            return Err(native_error(
                "The screen recorder could not finalize the video.",
            ));
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}
