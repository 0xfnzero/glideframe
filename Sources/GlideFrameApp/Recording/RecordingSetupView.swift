import SwiftUI

struct RecordingSetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

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
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(model.recordingEngine.targets) { target in
                                TargetRow(target: target, selected: target.id == model.recordingOptions.targetID) {
                                    model.recordingOptions.targetID = target.id
                                }
                            }
                        }
                    }
                    .frame(height: 310)
                    Button { Task { await model.reloadTargets() } } label: {
                        Label(tr("refresh"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
                .frame(width: 340)

                Form {
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
                Spacer()
                Button(tr("cancel")) { dismiss() }
                Button {
                    Task { await model.startRecording() }
                } label: {
                    Label(tr("start_recording"), systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.recordingOptions.targetID == nil || model.recordingEngine.state.isActive)
            }
            .padding(16)
        }
        .frame(width: 700, height: 530)
    }
}

private struct TargetRow: View {
    let target: CaptureTargetDescriptor
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: target.kind == .window ? "macwindow" : "display")
                    .frame(width: 24)
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
