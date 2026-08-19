import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        bringAppToFront()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.setActivationPolicy(.regular)
        bringAppToFront()
        return true
    }

    private func bringAppToFront() {
        DispatchQueue.main.async {
            NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct GlideFrameApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @AppStorage("app.language") private var language = AppLanguage.english.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environment(\.locale, selectedLocale)
                .frame(minWidth: 1040, minHeight: 680)
                .task { await model.bootstrap() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(tr("new_recording")) { model.showsRecordingSetup = true }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandMenu(tr("recording")) {
                if model.recordingEngine.state == .paused {
                    Button(tr("resume")) { model.recordingEngine.resume() }
                } else {
                    Button(tr("pause")) { model.recordingEngine.pause() }
                }
                Button(tr("stop")) { Task { await model.stopRecording() } }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!model.recordingEngine.state.isActive)
            }
        }
    }

    private var selectedLocale: Locale {
        AppLanguage.normalized(language).locale
    }
}
