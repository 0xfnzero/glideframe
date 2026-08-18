import AppKit
import SwiftUI

struct RecordingSetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var regionSelector: ScreenRegionSelector?
    @State private var isSelectingRegion = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(tr("recording_setup")).font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help(tr("close"))
            }
            .padding(20)
            Divider()

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("source")).font(.headline)
                    ZStack {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(model.recordingEngine.targets) { target in
                                    TargetRow(target: target, selected: target.id == model.recordingOptions.targetID) {
                                        if model.recordingOptions.targetID != target.id {
                                            model.recordingOptions.region = nil
                                        }
                                        model.recordingOptions.targetID = target.id
                                    }
                                }
                            }
                        }

                        if model.isLoadingCaptureTargets {
                            ProgressView(tr("loading_sources"))
                        } else if model.recordingEngine.targets.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "rectangle.on.rectangle.slash")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundStyle(.secondary)
                                Text(tr("no_sources"))
                                    .font(.subheadline.weight(.medium))
                                if let captureTargetError = model.captureTargetError {
                                    Text(captureTargetError)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: 250)
                                }
                                if model.screenCaptureAccessUnavailable {
                                    HStack(spacing: 8) {
                                        Button(tr("request_access")) {
                                            Task { await model.requestScreenCaptureAccess() }
                                        }
                                        Button(tr("relaunch")) {
                                            model.relaunch()
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                    .frame(height: 310)
                    Button { Task { await model.reloadTargets() } } label: {
                        Label(tr("refresh"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isLoadingCaptureTargets)
                }
                .frame(width: 340)

                Form {
                    if selectedTarget != nil {
                        Picker(tr("capture_area"), selection: captureAreaMode) {
                            Text(tr("full_source")).tag(CaptureAreaMode.fullScreen)
                            Text(tr("selected_area")).tag(CaptureAreaMode.selectedArea)
                        }
                        .pickerStyle(.segmented)

                        if let region = model.recordingOptions.region {
                            LabeledContent(
                                tr("area_size"),
                                value: "\(Int(region.width)) x \(Int(region.height))"
                            )
                            Button {
                                beginRegionSelection()
                            } label: {
                                Label(tr("reselect_area"), systemImage: "viewfinder")
                            }
                            .disabled(isSelectingRegion)
                        }
                    }
                    Picker(tr("frame_rate"), selection: $model.recordingOptions.frameRate) {
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                    Toggle(tr("system_audio"), isOn: $model.recordingOptions.recordSystemAudio)
                    Toggle(tr("microphone"), isOn: $model.recordingOptions.recordMicrophone)
                    Toggle(tr("camera"), isOn: $model.recordingOptions.recordCamera)
                    Stepper(value: $model.recordingOptions.countdown, in: 0...5) {
                        LabeledContent(tr("countdown"), value: "\(model.recordingOptions.countdown)s")
                    }
                }
                .formStyle(.grouped)
                .frame(width: 280)
            }
            .padding(20)

            Divider()
            HStack {
                if let message = startStatusMessage {
                    Label(message, systemImage: startStatusIcon)
                        .font(.callout)
                        .foregroundStyle(startStatusColor)
                        .lineLimit(2)
                }
                Spacer()
                Button(tr("cancel")) { dismiss() }
                Button {
                    Task { await model.startRecording() }
                } label: {
                    Label(startButtonTitle, systemImage: startButtonIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(
                    model.isLoadingCaptureTargets
                        || model.recordingOptions.targetID == nil
                        || model.recordingEngine.state.isActive
                        || isSelectingRegion
                )
            }
            .padding(16)
        }
        .frame(width: 700, height: 530)
        .task { await model.reloadTargets() }
        .onDisappear { regionSelector?.cancel() }
    }

    private var startButtonTitle: String {
        switch model.recordingEngine.state {
        case .preparing:
            tr("preparing_recording")
        case .countdown(let remaining):
            String(format: tr("recording_countdown"), remaining)
        case .recording, .paused:
            tr("recording_in_progress")
        case .finalizing:
            tr("finalizing_recording")
        case .idle, .failed:
            tr("start_recording")
        }
    }

    private var startButtonIcon: String {
        model.recordingEngine.state.isActive ? "hourglass" : "record.circle"
    }

    private var startStatusMessage: String? {
        switch model.recordingEngine.state {
        case .preparing:
            tr("preparing_recording")
        case .countdown(let remaining):
            String(format: tr("recording_countdown"), remaining)
        case .recording, .paused:
            tr("recording_in_progress")
        case .finalizing:
            tr("finalizing_recording")
        case .failed(let message):
            message
        case .idle:
            model.recordingStartError
        }
    }

    private var startStatusIcon: String {
        switch model.recordingEngine.state {
        case .failed:
            "exclamationmark.triangle"
        default:
            model.recordingStartError == nil ? "hourglass" : "exclamationmark.triangle"
        }
    }

    private var startStatusColor: Color {
        switch model.recordingEngine.state {
        case .failed:
            .red
        default:
            model.recordingStartError == nil ? .secondary : .red
        }
    }

    private var selectedTarget: CaptureTargetDescriptor? {
        model.recordingEngine.targets.first { $0.id == model.recordingOptions.targetID }
    }

    private var captureAreaMode: Binding<CaptureAreaMode> {
        Binding(
            get: { model.recordingOptions.region == nil ? .fullScreen : .selectedArea },
            set: { mode in
                switch mode {
                case .fullScreen:
                    model.recordingOptions.region = nil
                case .selectedArea:
                    beginRegionSelection()
                }
            }
        )
    }

    private func beginRegionSelection() {
        guard !isSelectingRegion,
              let target = selectedTarget
        else { return }

        isSelectingRegion = true
        let selector = ScreenRegionSelector()
        regionSelector = selector
        Task { @MainActor in
            let region = await selector.selectRegion(
                on: target.selectionDisplayID,
                constrainedTo: target.selectionFrame
            )
            if let region, model.recordingOptions.targetID == target.id {
                model.recordingOptions.region = region
            }
            if regionSelector === selector {
                regionSelector = nil
                isSelectingRegion = false
            }
        }
    }
}

private enum CaptureAreaMode: Hashable {
    case fullScreen
    case selectedArea
}

private struct TargetRow: View {
    let target: CaptureTargetDescriptor
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                TargetIcon(target: target)
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.title).lineLimit(1)
                    Text(target.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
            .contentShape(Rectangle())
            .padding(10)
            .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct TargetIcon: View {
    let target: CaptureTargetDescriptor

    var body: some View {
        ZStack {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: target.kind == .window ? "macwindow" : "display")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 36, height: 36)
    }

    private var appIcon: NSImage? {
        guard target.kind == .window else { return nil }

        if let bundleIdentifier = target.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == target.subtitle || $0.localizedName == target.title
        }), let bundleURL = runningApp.bundleURL {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        return nil
    }
}
