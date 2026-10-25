import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: Model

    var body: some View {
        VStack(spacing: 0) {
            PrinterHeader().padding(16)
            Divider()
            StepView()
                .padding(20)
                .frame(maxWidth: .infinity, minHeight: 330, alignment: .top)
            Divider()
            QueuePanel().padding(16)
            Divider()
            AutoLoadFooter().padding(16)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .alert("LaserJet 1020", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct PrinterHeader: View {
    @EnvironmentObject private var model: Model

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("HP LaserJet 1020").font(.headline)
                HStack(spacing: 6) {
                    if model.printer == .loadingFirmware {
                        ProgressView().controlSize(.small)
                    } else {
                        Circle().fill(statusColor).frame(width: 8, height: 8)
                    }
                    Text(statusText)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if model.printer == .needsFirmware, !model.busy {
                Button("Load Firmware") { model.loadFirmwareNow() }
            }
        }
    }

    private var statusText: String {
        if model.isPrinting { return "Printing" }
        switch model.printer {
        case .unknown: return "Checking…"
        case .off: return "Off or not connected"
        case .needsFirmware: return "Switched on, needs its firmware"
        case .loadingFirmware: return "Loading the printer's firmware…"
        case .ready: return "Ready"
        }
    }

    private var statusColor: Color {
        if model.isPrinting { return .blue }
        switch model.printer {
        case .unknown, .off: return .gray
        case .needsFirmware, .loadingFirmware: return .orange
        case .ready: return .green
        }
    }
}

struct StepView: View {
    @EnvironmentObject private var model: Model

    var body: some View {
        switch model.step {
        case .choose:
            DropZone()
        case .confirm(let pdf):
            ConfirmView(pdf: pdf)
        case .printing(let message, let detail):
            PrintingView(message: message, detail: detail)
        case .reload(let back):
            ReloadView(back: back)
        case .finished(let message):
            FinishedView(message: message)
        }
    }
}

struct DropZone: View {
    @EnvironmentObject private var model: Model

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("Drop a PDF here").font(.title3)
                Button("Choose PDF…") { model.choosePDF() }
                    .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    .foregroundStyle(model.dropTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            )
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.open(url)
                return true
            } isTargeted: { model.dropTargeted = $0 }
            Text("From any app: press ⌘P, open the PDF menu at the bottom of the Print window and choose Open in LaserJet 1020.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct ConfirmView: View {
    @EnvironmentObject private var model: Model
    let pdf: PickedPDF

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pdf.name).font(.headline).lineLimit(1).truncationMode(.middle)
                    Text(pageWord(pdf.pageCount)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Change…") { model.choosePDF() }
            }
            if pdf.pageCount > 1 {
                HStack(spacing: 8) {
                    Text("Pages")
                    TextField("All \(pageWord(pdf.pageCount))", text: $model.pageText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                    Text("e.g. 5-12 or 1, 3, 7-9")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 8) {
                    ModeCard(
                        mode: .oneSide,
                        title: "One side",
                        detail: "Normal printing on \(count == 1 ? "1 sheet" : "\(count) sheets")."
                    )
                    ModeCard(
                        mode: .bothSides,
                        title: "Both sides – manual",
                        detail: "This printer can't flip paper. Fronts print first, then you put the stack back in for the backs. \(sheets == 1 ? "1 sheet" : "\(sheets) sheets")."
                    )
                    ModeCard(
                        mode: .backsOnly,
                        title: "Back sides only",
                        detail: "Fronts are already printed, for example before a paper jam. Only the backs print."
                    )
                }
                PlanLine()
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Button { model.start() } label: {
                    Text(buttonTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canPrint)
                if !model.queue.jobs.isEmpty {
                    Text("One job at a time: this waits until the print queue below is empty.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if model.printer == .off {
                    Text("Switch the printer on to print.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var count: Int {
        if case .success(let pages)? = model.selectedPages { return pages.count }
        return pdf.pageCount
    }

    private var sheets: Int { (count + 1) / 2 }

    private var buttonTitle: String {
        switch model.effectiveMode {
        case .oneSide: return "Print"
        case .bothSides: return "Print on Both Sides"
        case .backsOnly: return "Continue"
        }
    }
}

struct PlanLine: View {
    @EnvironmentObject private var model: Model

    var body: some View {
        if let problem = model.selectionProblem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        } else if case .success(let pages)? = model.selectedPages {
            VStack(alignment: .leading, spacing: 3) {
                Text(plan(pages)).font(.callout)
                if model.effectiveMode != .oneSide, let sheet = PageSelection.firstSheetUnlikeDocument(pages) {
                    Text("Pages \(sheet.front) and \(sheet.back) share a sheet. To keep the document's sheets, start each range on an odd page.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func plan(_ pages: [Int]) -> String {
        let fronts = PageSelection.listed(Sides.fronts(of: pages))
        let backs = PageSelection.listed(Sides.backs(of: pages).compactMap { $0 }.sorted())
        switch model.effectiveMode {
        case .oneSide: return "Prints pages \(PageSelection.listed(pages))."
        case .bothSides: return "Fronts \(fronts)  ·  Backs \(backs)"
        case .backsOnly: return "Prints pages \(backs) on the backs of pages \(fronts)."
        }
    }
}

struct ModeCard: View {
    @EnvironmentObject private var model: Model
    let mode: PrintMode
    let title: String
    let detail: String

    var body: some View {
        let selected = model.mode == mode
        Button { model.mode = mode } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold))
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PrintingView: View {
    @EnvironmentObject private var model: Model
    let message: String
    let detail: String?

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(message).font(.title3)
            if let detail { Text(detail).foregroundStyle(.secondary) }
            if let problem = model.queueProblem {
                Label("\(problem.title). See the print queue below.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button("Cancel") { model.cancelPrinting() }
        }
        .frame(maxWidth: .infinity)
    }
}

struct ReloadView: View {
    @EnvironmentObject private var model: Model
    let back: BackPrint

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(back.frontsJustPrinted ? "Now put the paper back" : "Put the printed sheets in", systemImage: "arrow.uturn.down.circle.fill")
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(instructions.enumerated()), id: \.offset) { index, text in
                    NumberedStep(number: index + 1, text: text)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button("Start Over") { model.reset() }
                Spacer()
                Button("Print Back Sides") { model.printBacks() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy || !model.queue.jobs.isEmpty)
            }
            .controlSize(.large)
        }
    }

    private var instructions: [String] {
        let fronts = Sides.fronts(of: back.pages)
        var steps: [String]
        if back.frontsJustPrinted {
            steps = [
                "Wait until all \(back.sheets) sheets are out of the printer.",
                "Take the stack out of the output tray as it is. Don't flip it, turn it or re-sort it.",
            ]
        } else {
            steps = [
                "Take the \(back.sheets) sheets with pages \(PageSelection.listed(fronts)) on them.",
                "Keep them as they came out of the printer: printed side down, page \(fronts.last ?? 0) on top. If they got mixed up, sort them that way, all the same way round.",
            ]
        }
        steps.append("Put the whole stack, the same way round, in the tray above the blank-paper tray.")
        if back.pages.count % 2 == 1, let last = back.pages.last {
            steps.append("The first sheet goes through without printing: page \(last) is the last page, so its back stays blank.")
        }
        return steps
    }
}

struct NumberedStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FinishedView: View {
    @EnvironmentObject private var model: Model
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text(message)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Print Another PDF") { model.reset() }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AutoLoadFooter: View {
    @EnvironmentObject private var model: Model

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Load firmware automatically")
                Text("As soon as you switch the printer on, so printing from any app just works.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Load firmware automatically", isOn: Binding(
                get: { model.autoLoadOn },
                set: { model.setAutoLoad($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }
}
