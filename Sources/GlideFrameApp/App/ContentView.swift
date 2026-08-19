import AppKit
import GlideFrameKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            ProjectSidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 290)
        } detail: {
            Group {
                if model.recordingEngine.state.isActive {
                    RecordingLiveView(engine: model.recordingEngine)
                } else if model.selectedManifest != nil {
                    StudioView()
                } else {
                    EmptyStudioView()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { StudioToolbar() }
        }
        .sheet(isPresented: $model.showsRecordingSetup) { RecordingSetupView() }
        .sheet(isPresented: $model.showsFormatConverter) {
            FormatConverterView(converter: model.formatConverter)
        }
        .alert(item: $model.notice) { notice in
            if let revealURL = notice.revealURL {
                return Alert(
                    title: Text(tr(notice.kind == .success ? "done" : "error")),
                    message: Text(notice.message),
                    primaryButton: .default(Text(tr("reveal_project"))) {
                        NSWorkspace.shared.activateFileViewerSelecting([revealURL])
                    },
                    secondaryButton: .cancel(Text(tr("ok")))
                )
            }
            return Alert(
                title: Text(tr(notice.kind == .success ? "done" : "error")),
                message: Text(notice.message),
                dismissButton: .default(Text(tr("ok")))
            )
        }
    }
}

private struct RecordingLiveView: View {
    @ObservedObject var engine: RecordingEngine

    var body: some View {
        ZStack {
            Color.black
            if let previewImage = engine.previewImage {
                Image(decorative: previewImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 8, height: 8)
                Text(tr("live_preview"))
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 6))
            .padding(16)
        }
    }
}

private struct ProjectSidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                Text(tr("app_name"))
                    .font(.headline)
                Spacer()
            }
            .padding(16)

            List(selection: Binding(
                get: { model.selectedManifest?.id },
                set: { id in
                    guard let summary = model.projects.first(where: { $0.id == id }) else { return }
                    Task { await model.select(summary) }
                }
            )) {
                Section(tr("projects")) {
                    ForEach(model.projects) { project in
                        ProjectRow(project: project).tag(project.id)
                    }
                }
            }
            .listStyle(.sidebar)

            if model.recoveredProjectCount > 0 {
                Label(String(format: tr("recovered_projects"), model.recoveredProjectCount), systemImage: "lifepreserver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
    }
}

private struct ProjectRow: View {
    let project: ProjectSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title).lineLimit(1)
            HStack(spacing: 6) {
                Text(project.duration.durationLabel)
                Text("·")
                Text(project.updatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct StudioToolbar: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("app.language") private var language = AppLanguage.english.rawValue

    var body: some View {
        HStack(spacing: 10) {
            if let manifest = model.selectedManifest {
                Text(manifest.title).font(.headline).lineLimit(1)
            }
            Spacer()
            RecordingControlBar(engine: model.recordingEngine)
            Spacer()
            Button { model.revealProjectsFolder() } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.bordered)
            .help(tr("open_recordings_folder"))

            Button {
                model.showsRecordingSetup = true
            } label: {
                Label(tr("new_recording"), systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(model.recordingEngine.state.isActive)

            Button { Task { await model.export() } } label: {
                Label(tr("export"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(model.selectedManifest == nil || model.isExporting)

            Button { model.showsFormatConverter = true } label: {
                Label(tr("convert"), systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)

            Menu {
                ForEach(AppLanguage.allCases) { appLanguage in
                    Button {
                        language = appLanguage.rawValue
                    } label: {
                        Label(
                            tr(appLanguage.displayNameKey),
                            systemImage: currentLanguage == appLanguage ? "checkmark" : "circle"
                        )
                    }
                }
            } label: {
                Image(systemName: "globe")
            }
            .menuStyle(.borderlessButton)
            .help(tr("language"))
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var currentLanguage: AppLanguage {
        AppLanguage.normalized(language)
    }
}

private struct RecordingControlBar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var engine: RecordingEngine

    init(engine: RecordingEngine) { _engine = ObservedObject(wrappedValue: engine) }

    var body: some View {
        if engine.state.isActive {
            HStack(spacing: 8) {
                Circle().fill(.red).frame(width: 8, height: 8)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(elapsed).monospacedDigit().frame(width: 52)
                }
                Button {
                    engine.state == .paused ? engine.resume() : engine.pause()
                } label: {
                    Image(systemName: engine.state == .paused ? "play.fill" : "pause.fill")
                }
                .help(engine.state == .paused ? tr("resume") : tr("pause"))
                Button { Task { await model.stopRecording() } } label: {
                    Image(systemName: "stop.fill")
                }
                .help(tr("stop"))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var elapsed: String {
        guard case .recording(let startedAt) = engine.state else { return "00:00" }
        return Date().timeIntervalSince(startedAt).durationLabel
    }
}

private struct EmptyStudioView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text(tr("empty_title")).font(.title2.weight(.semibold))
            Text(tr("empty_subtitle"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button { model.showsRecordingSetup = true } label: {
                Label(tr("new_recording"), systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension TimeInterval {
    var durationLabel: String {
        guard isFinite else { return "00:00" }
        let total = max(0, Int(self))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
