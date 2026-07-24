import SwiftUI

@main
struct GlideFrameApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("app.language") private var language = "system"

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
        language == "system" ? .current : Locale(identifier: language)
    }
}
