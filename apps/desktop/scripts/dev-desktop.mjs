import { join } from "node:path";
import { appDir, prepareDesktop, run } from "./prepare-desktop.mjs";
const config = prepareDesktop();
run(process.execPath, [join(appDir, "../../node_modules/@tauri-apps/cli/tauri.js"), "dev", "--config", config, ...process.argv.slice(2)]);
