import SwiftUI

struct QueuePanel: View {
    @EnvironmentObject private var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Print queue").font(.headline)
                if !model.queue.jobs.isEmpty {
                    Text("\(model.queue.jobs.count)")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                }
                Spacer()
                Button("Clear All") { model.clearQueue() }
                    .disabled(model.queue.jobs.isEmpty)
            }
            if let problem = model.queueProblem {
                Banner(icon: "exclamationmark.triangle.fill", tint: .orange, title: problem.title, detail: problem.detail) {
                    if problem.canResume {
                        Button("Resume") { model.resumeQueue() }
                            .buttonStyle(.borderedProminent)
                    }
                    if let stuck = model.queue.jobs.first {
                        Button("Cancel “\(stuck.name)”") { model.cancelJob(stuck) }
                    }
                }
            }
            if let failed = model.failedJobToShow {
                Banner(
                    icon: "xmark.octagon.fill",
                    tint: .red,
                    title: "“\(failed.name)” didn't print",
                    detail: failed.reasons.first.map(PrintQueue.describe) ?? "The print system gave up on it."
                ) {
                    Button("OK") { model.dismissFailure() }
                }
            }
            if model.queue.jobs.isEmpty {
                Text("Nothing waiting to print.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.queue.jobs) { job in JobRow(job: job) }
                    }
                }
                .frame(height: min(CGFloat(model.queue.jobs.count) * 40, 130))
            }
        }
    }
}

struct Banner<Actions: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) { actions() }
                .controlSize(.small)
                .padding(.leading, 24)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1)))
    }
}

struct JobRow: View {
    @EnvironmentObject private var model: Model
    let job: QueuedJob

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(job.name).lineLimit(1).truncationMode(.middle)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if job.state == .held {
                Button("Release") { model.releaseJob(job) }
                    .controlSize(.small)
                    .help("Let this job print")
            }
            Button { model.cancelJob(job) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Cancel this job")
        }
        .frame(height: 34)
    }

    private var summary: String {
        var parts: [String]
        switch job.state {
        case .processing:
            parts = ["Printing"]
            if let started = job.startedAt { parts.append("for \(elapsed(since: started))") }
        case .held: parts = ["On hold"]
        case .stopped: parts = ["Stopped"]
        default: parts = ["Waiting"]
        }
        if let reason = job.reasons.first { parts.append(PrintQueue.describe(reason)) }
        if !job.message.isEmpty { parts.append(job.message) }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(job.kilobytes) * 1024, countStyle: .file))
        return parts.joined(separator: " · ")
    }

    private var icon: String {
        switch job.state {
        case .processing: return "printer.fill"
        case .held: return "pause.circle"
        case .stopped: return "exclamationmark.triangle.fill"
        default: return "clock"
        }
    }

    private var tint: Color {
        switch job.state {
        case .processing: return .accentColor
        case .stopped: return .orange
        default: return .secondary
        }
    }

    private func elapsed(since start: Date) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(0, Date().timeIntervalSince(start))) ?? ""
    }
}
