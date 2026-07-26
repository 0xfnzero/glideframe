import GlideFrameKit
import SwiftUI

struct FormatConverterView: View {
    @ObservedObject var converter: FormatConverterModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            settingsBar
            Divider()
            outputBar
            Divider()
            queueHeader
            queue
            Divider()
            footer
        }
        .frame(minWidth: 780, idealWidth: 820, minHeight: 620, idealHeight: 680)
        .task {
            if case .checking = converter.toolchainState {
                await converter.refreshToolchain()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.title2)
                .foregroundStyle(.tint)
            Text(tr("format_converter"))
                .font(.title2.weight(.semibold))
            toolchainStatus
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(tr("close"))
            .disabled(converter.isConverting)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    @ViewBuilder
    private var toolchainStatus: some View {
        switch converter.toolchainState {
        case .checking:
            ProgressView().controlSize(.small)
        case .available(let version):
            Label(String(format: tr("ffmpeg_ready"), version), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .unavailable:
            Label(tr("ffmpeg_missing"), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var settingsBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 18) {
                settingPicker(title: tr("output_format"), selection: Binding(
                    get: { converter.settings.format },
                    set: { converter.updateFormat($0) }
                )) {
                    ForEach(MediaOutputFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                settingPicker(title: tr("codec"), selection: $converter.settings.codec) {
                    ForEach(converter.settings.format.compatibleCodecs) { codec in
                        Text(codec.displayName).tag(codec)
                    }
                }

                settingPicker(title: tr("resolution"), selection: $converter.settings.resolution) {
                    ForEach(ConversionResolution.allCases) { resolution in
                        Text(resolution == .source ? tr("keep_original") : resolution.displayName).tag(resolution)
                    }
                }
                .disabled(converter.settings.format.kind == .audio)

                settingPicker(title: tr("frame_rate"), selection: $converter.settings.frameRate) {
                    ForEach(ConversionFrameRate.allCases) { frameRate in
                        Text(frameRate == .source ? tr("keep_original") : frameRate.displayName).tag(frameRate)
                    }
                }
                .disabled(converter.settings.format.kind == .audio)
            }

            HStack(spacing: 16) {
                Text(tr("quality"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(tr("quality"), selection: $converter.settings.quality) {
                    Text(tr("quality_high")).tag(ConversionQuality.high)
                    Text(tr("quality_balanced")).tag(ConversionQuality.balanced)
                    Text(tr("quality_compact")).tag(ConversionQuality.compact)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 310)
                Toggle(tr("include_audio"), isOn: $converter.settings.includeAudio)
                    .disabled(converter.settings.format.kind != .video)
                Spacer()
            }
        }
        .padding(18)
        .disabled(converter.isConverting)
    }

    private func settingPicker<Selection: Hashable, Content: View>(
        title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 130, alignment: .leading)
        }
    }

    private var outputBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(tr("output_folder"))
                .font(.subheadline.weight(.medium))
            Text(converter.outputDirectory.path(percentEncoded: false))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button { converter.chooseOutputDirectory() } label: {
                Image(systemName: "folder.badge.gearshape")
            }
            .help(tr("choose_output_folder"))
            .disabled(converter.isConverting)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    private var queueHeader: some View {
        HStack {
            Text(tr("conversion_queue"))
                .font(.headline)
            Text("\(converter.jobs.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            if converter.completedCount > 0, !converter.isConverting {
                Button(tr("clear_completed")) { converter.clearCompleted() }
                    .buttonStyle(.borderless)
            }
            Button { converter.chooseInputs() } label: {
                Label(tr("add_files"), systemImage: "plus")
            }
            .disabled(converter.isConverting)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
    }

    @ViewBuilder
    private var queue: some View {
        if converter.jobs.isEmpty {
            ContentUnavailableView(
                tr("no_media_files"),
                systemImage: "film.stack"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(converter.jobs) { job in
                    ConversionJobRow(
                        job: job,
                        reveal: { converter.reveal(job) },
                        remove: { converter.remove(job.id) }
                    )
                }
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if case .unavailable(let message) = converter.toolchainState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Button { Task { await converter.refreshToolchain(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(tr("refresh"))
            }
            Spacer()
            if converter.isConverting {
                Button(role: .cancel) { converter.cancel() } label: {
                    Label(tr("cancel_conversion"), systemImage: "stop.fill")
                }
            } else {
                Button { converter.start() } label: {
                    Label(tr("convert"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!converter.canStart)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }
}

private struct ConversionJobRow: View {
    let job: FormatConverterModel.Job
    let reveal: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.inputURL.lastPathComponent)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            status
                .frame(width: 210, alignment: .trailing)
            if job.status != .converting {
                Button(action: remove) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(tr("remove"))
            } else {
                Color.clear.frame(width: 16, height: 16)
            }
        }
        .padding(.vertical, 5)
    }

    private var detail: String {
        let ext = job.inputURL.pathExtension.uppercased()
        let size = ByteCountFormatter.string(fromByteCount: job.inputBytes, countStyle: .file)
        return "\(ext)  ·  \(size)"
    }

    @ViewBuilder
    private var status: some View {
        switch job.status {
        case .ready:
            Label(tr("ready"), systemImage: "circle")
                .foregroundStyle(.secondary)
        case .converting:
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(Int(job.progress * 100))%")
                    .font(.caption.monospacedDigit())
                ProgressView(value: job.progress)
            }
        case .completed:
            Button(action: reveal) {
                Label(tr("completed"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.borderless)
            .help(tr("reveal_output"))
        case .failed(let message):
            Label {
                Text(message).lineLimit(2)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(.red)
        case .cancelled:
            Label(tr("cancelled"), systemImage: "stop.circle")
                .foregroundStyle(.secondary)
        }
    }
}
