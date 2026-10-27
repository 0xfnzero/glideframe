import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const appDir = dirname(dirname(fileURLToPath(import.meta.url)));
export function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: appDir, stdio: "inherit", ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
function findFfmpeg(directory, depth = 0) {
  if (depth > 5 || !existsSync(directory)) return undefined;
  if (existsSync(join(directory, "ffmpeg.exe")) && existsSync(join(directory, "ffprobe.exe"))) {
    return join(directory, "ffmpeg.exe");
  }
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      const found = findFfmpeg(join(directory, entry.name), depth + 1);
      if (found) return found;
    }
  }
}
export function prepareDesktop() {
  if (process.platform === "darwin") {
    run("bash", ["scripts/build-macos-helper.sh"]);
    return "src-tauri/tauri.macos.conf.json";
  }
  if (process.platform !== "win32") throw new Error("GlideFrame Desktop supports macOS and Windows.");
  const found = spawnSync("where.exe", ["ffmpeg.exe"], { encoding: "utf8" });
  let ffmpeg = process.env.GLIDEFRAME_FFMPEG_PATH ?? found.stdout?.trim().split(/\r?\n/)[0];
  // Chocolatey shims cannot be copied into a self-contained installer.
  if (!ffmpeg || !existsSync(join(dirname(ffmpeg), "ffprobe.exe")) || /chocolatey[\\/]bin[\\/]/i.test(ffmpeg)) {
    if (!process.env.GLIDEFRAME_FFMPEG_PATH) {
      ffmpeg = findFfmpeg(join(process.env.ChocolateyInstall ?? "C:\\ProgramData\\chocolatey", "lib", "ffmpeg", "tools"));
    }
  }
  if (!ffmpeg || !existsSync(join(dirname(ffmpeg), "ffprobe.exe")) || /chocolatey[\\/]bin[\\/]/i.test(ffmpeg)) {
    throw new Error("Install FFmpeg (winget install Gyan.FFmpeg), or set GLIDEFRAME_FFMPEG_PATH to the real ffmpeg.exe beside ffprobe.exe, not a package-manager shim.");
  }
  run(ffmpeg, ["-version"], { stdio: "ignore" });
  run(join(dirname(ffmpeg), "ffprobe.exe"), ["-version"], { stdio: "ignore" });
  const target = process.env.CARGO_BUILD_TARGET ?? "x86_64-pc-windows-msvc";
  mkdirSync(join(appDir, "src-tauri/binaries"), { recursive: true });
  copyFileSync(ffmpeg, join(appDir, `src-tauri/binaries/glideframe-ffmpeg-${target}.exe`));
  copyFileSync(join(dirname(ffmpeg), "ffprobe.exe"), join(appDir, `src-tauri/binaries/glideframe-ffprobe-${target}.exe`));
  return "src-tauri/tauri.windows.conf.json";
}
