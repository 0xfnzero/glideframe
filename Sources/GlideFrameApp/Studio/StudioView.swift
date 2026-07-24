import AVKit
import GlideFrameKit
import SwiftUI

struct StudioView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                StudioPreview(url: model.sourceURL(), canvas: model.selectedManifest?.canvas ?? .default)
                Divider()
                TimelineEditor()
                    .frame(height: 184)
            }
            InspectorView()
                .frame(minWidth: 260, idealWidth: 292, maxWidth: 330)
        }
    }
}

private struct StudioPreview: View {
    let url: URL?
    let canvas: CanvasStyle

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = fittedCanvas(in: proxy.size, ratio: canvas.aspectRatio)
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                ZStack {
                    CanvasBackground(background: canvas.background)
                    if let url {
                        PlayerSurface(url: url)
                            .clipShape(RoundedRectangle(cornerRadius: canvas.cornerRadius))
                            .shadow(color: .black.opacity(canvas.shadow), radius: 20, y: 8)
                            .padding(canvas.padding / 3)
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .frame(minHeight: 360)
    }

    private func fittedCanvas(in size: CGSize, ratio: CanvasStyle.AspectRatio) -> CGSize {
        let aspect: CGFloat = switch ratio { case .landscape: 16/9; case .portrait: 9/16; case .square: 1 }
        let available = CGSize(width: max(100, size.width - 64), height: max(100, size.height - 48))
        if available.width / available.height > aspect {
            return .init(width: available.height * aspect, height: available.height)
        }
        return .init(width: available.width, height: available.width / aspect)
    }
}

private struct PlayerSurface: View {
    let url: URL
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .onChange(of: url) { _, newURL in player.replaceCurrentItem(with: AVPlayerItem(url: newURL)) }
    }
}

private struct CanvasBackground: View {
    let background: CanvasStyle.Background

    var body: some View {
        Rectangle().fill(color)
    }

    private var color: Color {
        switch background {
        case .graphite: Color(red: 0.055, green: 0.063, blue: 0.075)
        case .daylight: Color(red: 0.92, green: 0.94, blue: 0.96)
        case .mint: Color(red: 0.16, green: 0.42, blue: 0.36)
        case .coral: Color(red: 0.78, green: 0.24, blue: 0.22)
        }
    }
}

private struct TimelineEditor: View {
    @EnvironmentObject private var model: AppModel
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(tr("timeline")).font(.headline)
                Spacer()
                Text((model.selectedManifest?.duration ?? 0).durationLabel).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)

            ForEach(model.selectedManifest?.tracks ?? []) { track in
                HStack(spacing: 10) {
                    Image(systemName: icon(for: track.kind)).frame(width: 18)
                    Text(track.kind.rawValue.capitalized).frame(width: 86, alignment: .leading)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(track.kind == .screen ? Color.accentColor.opacity(0.72) : Color.green.opacity(0.55))
                        .frame(height: 24)
                        .overlay(alignment: .leading) {
                            if track.kind == .microphone {
                                HStack(spacing: 3) {
                                    ForEach(0..<36, id: \.self) { index in
                                        Capsule().fill(.white.opacity(0.62)).frame(width: 2, height: CGFloat(4 + (index * 7) % 15))
                                    }
                                }.padding(.horizontal, 8)
                            }
                        }
                }
                .padding(.horizontal, 14)
            }

            HStack {
                Text(tr("trim")).frame(width: 86, alignment: .leading)
                Slider(value: $trimStart, in: 0...max(0.1, trimEnd), onEditingChanged: saveTrim)
                Text(trimStart.durationLabel).monospacedDigit().frame(width: 46)
                Slider(value: $trimEnd, in: min(trimStart, duration)...max(duration, 0.1), onEditingChanged: saveTrim)
                Text(trimEnd.durationLabel).monospacedDigit().frame(width: 46)
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 12)
        .onAppear { syncTrim() }
        .onChange(of: model.selectedManifest?.id) { _, _ in syncTrim() }
    }

    private var duration: Double { model.selectedManifest?.duration ?? 0 }

    private func syncTrim() {
        guard let manifest = model.selectedManifest else { return }
        let range = manifest.editGraph.clips.first?.sourceRange ?? .init(start: 0, duration: manifest.duration)
        trimStart = range.start
        trimEnd = range.end
    }

    private func saveTrim(_ editing: Bool) {
        guard !editing else { return }
        model.updateManifest { manifest in
            manifest.editGraph.clips = [.init(sourceRange: .init(start: trimStart, duration: max(0, trimEnd - trimStart)))]
        }
    }

    private func icon(for kind: MediaSource.Kind) -> String {
        switch kind { case .screen: "display"; case .systemAudio: "speaker.wave.2"; case .microphone: "waveform"; case .camera: "video" }
    }
}

private struct InspectorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(tr("style")).font(.headline)
                    Spacer()
                    Button { model.revealProject() } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless)
                        .help(tr("reveal_project"))
                }
                InspectorSection(title: "background") {
                    HStack(spacing: 10) {
                        ForEach(CanvasStyle.Background.allCases, id: \.self) { background in
                            BackgroundSwatch(
                                background: background,
                                selected: model.selectedManifest?.canvas.background == background
                            ) {
                                model.updateManifest { $0.canvas.background = background }
                            }
                        }
                    }
                }
                InspectorSection(title: "aspect_ratio") {
                    Picker("aspect_ratio", selection: Binding(
                        get: { model.selectedManifest?.canvas.aspectRatio ?? .landscape },
                        set: { value in model.updateManifest { $0.canvas.aspectRatio = value } }
                    )) {
                        Image(systemName: "rectangle").tag(CanvasStyle.AspectRatio.landscape)
                        Image(systemName: "rectangle.portrait").tag(CanvasStyle.AspectRatio.portrait)
                        Image(systemName: "square").tag(CanvasStyle.AspectRatio.square)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                InspectorSection(title: "frame") {
                    LabeledContent(tr("padding")) {
                        Slider(value: Binding(
                            get: { model.selectedManifest?.canvas.padding ?? 64 },
                            set: { value in model.updateManifest { $0.canvas.padding = value } }
                        ), in: 0...140)
                    }
                    LabeledContent(tr("corners")) {
                        Slider(value: Binding(
                            get: { model.selectedManifest?.canvas.cornerRadius ?? 18 },
                            set: { value in model.updateManifest { $0.canvas.cornerRadius = value } }
                        ), in: 0...40)
                    }
                }
                Divider()
                Button { model.applyAutoPolish() } label: {
                    Label(tr("auto_polish"), systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                LabeledContent(tr("zoom_events"), value: "\(model.selectedManifest?.editGraph.zoomKeyframes.count ?? 0)")
                    .foregroundStyle(.secondary)
                Toggle(tr("remove_silence"), isOn: Binding(
                    get: { model.selectedManifest?.editGraph.removeSilence ?? false },
                    set: { value in model.updateManifest { $0.editGraph.removeSilence = value } }
                ))
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct InspectorSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

private struct BackgroundSwatch: View {
    let background: CanvasStyle.Background
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay { Circle().stroke(.white, lineWidth: selected ? 3 : 0).padding(3) }
                .overlay { Circle().stroke(.primary.opacity(selected ? 0.8 : 0.18), lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .help(background.rawValue.capitalized)
    }

    private var color: Color {
        switch background {
        case .graphite: Color(red: 0.055, green: 0.063, blue: 0.075)
        case .daylight: Color(red: 0.92, green: 0.94, blue: 0.96)
        case .mint: Color(red: 0.16, green: 0.42, blue: 0.36)
        case .coral: Color(red: 0.78, green: 0.24, blue: 0.22)
        }
    }
}

private extension TimeInterval {
    var durationLabel: String {
        let total = max(0, Int(self))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
