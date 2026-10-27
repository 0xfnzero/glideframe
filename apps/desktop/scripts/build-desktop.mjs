import { execFileSync, spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { appDir, prepareDesktop, run } from "./prepare-desktop.mjs";

let config = prepareDesktop();
let signingIdentity;
const buildArgs = process.argv.slice(2);
let packageDmg = false;
if (process.platform === "darwin") {
  const identities = spawnSync("security", ["find-identity", "-v", "-p", "codesigning"], { encoding: "utf8" });
  signingIdentity = process.env.APPLE_SIGNING_IDENTITY ?? identities.stdout?.match(/"(Apple Development:[^"]+)"/)?.[1] ?? "-";
  const settings = JSON.parse(readFileSync(join(appDir, config), "utf8"));
  settings.bundle.macOS = { ...settings.bundle.macOS, signingIdentity, hardenedRuntime: signingIdentity !== "-" };
  config = "src-tauri/binaries/tauri.signing.conf.json";
  writeFileSync(join(appDir, config), JSON.stringify(settings));
  run("codesign", ["--force", "--sign", signingIdentity, join(appDir, "src-tauri/binaries/libGlideFrameCaptureBridge.dylib")]);
  // Package the signed app with hdiutil. Tauri's Finder layout script can wait
  // indefinitely for Automation access on an otherwise fully built application.
  const bundlesIndex = buildArgs.findIndex((arg) => arg === "--bundles" || arg === "-b" || arg.startsWith("--bundles="));
  if (bundlesIndex < 0) {
    packageDmg = true;
    buildArgs.push("--bundles", "app");
  } else {
    const inline = buildArgs[bundlesIndex].startsWith("--bundles=");
    const value = inline ? buildArgs[bundlesIndex].slice("--bundles=".length) : buildArgs[bundlesIndex + 1];
    const bundles = (value ?? "").split(",");
    packageDmg = bundles.includes("dmg") || bundles.includes("all");
    if (packageDmg) buildArgs.splice(bundlesIndex, inline ? 1 : 2, "--bundles", "app");
  }
}
// Invoke the installed CLI using Node so paths with spaces work on Windows as well.
run(process.execPath, [join(appDir, "../../node_modules/@tauri-apps/cli/tauri.js"), "build", "--config", config, ...buildArgs]);
if (process.platform === "darwin") {
  const profile = buildArgs.includes("--debug") ? "debug" : "release";
  const bundle = join(appDir, `src-tauri/target/${profile}/bundle/macos/GlideFrame Desktop.app`);
  run("codesign", ["--verify", "--deep", "--strict", bundle]);
  if (packageDmg) {
    const { productName, version } = JSON.parse(readFileSync(join(appDir, "src-tauri/tauri.conf.json"), "utf8"));
    const outputDir = join(dirname(bundle), "../dmg");
    const arch = process.arch === "arm64" ? "aarch64" : "x64";
    const output = join(outputDir, `${productName}_${version}_${arch}.dmg`);
    const staging = mkdtempSync(join(tmpdir(), "glideframe-dmg-"));
    try {
      mkdirSync(outputDir, { recursive: true });
      execFileSync("ditto", [bundle, join(staging, `${productName}.app`)]);
      symlinkSync("/Applications", join(staging, "Applications"));
      execFileSync("hdiutil", ["create", "-ov", "-volname", productName, "-srcfolder", staging, "-fs", "HFS+", "-format", "UDZO", output], { stdio: "inherit" });
      execFileSync("hdiutil", ["verify", output], { stdio: "inherit" });
      console.log(`Created ${output}`);
    } finally {
      rmSync(staging, { recursive: true, force: true });
    }
  }
}
