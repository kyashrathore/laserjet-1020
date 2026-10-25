import AppKit
import PDFKit
import SwiftUI

struct PickedPDF: Equatable {
    let url: URL
    let name: String
    let pageCount: Int
}

enum PrintMode: String {
    case oneSide, bothSides, backsOnly

    static var saved: PrintMode {
        PrintMode(rawValue: UserDefaults.standard.string(forKey: "printMode") ?? "") ?? .oneSide
    }
}

struct BackPrint: Equatable {
    let pdf: PickedPDF
    let pages: [Int]
    let file: URL
    let frontsJustPrinted: Bool
    var sheets: Int { (pages.count + 1) / 2 }
}

enum Step: Equatable {
    case choose
    case confirm(PickedPDF)
    case printing(String, detail: String?)
    case reload(BackPrint)
    case finished(String)
}

@MainActor
final class Model: ObservableObject {
    static let shared = Model()

    @Published var step: Step = .choose
    @Published var printer: PrinterState = .unknown
    @Published private(set) var busy = false
    @Published private(set) var queue = QueueSnapshot()
    @Published private(set) var dismissedFailure = UserDefaults.standard.integer(forKey: "dismissedFailedJob")
    @Published var autoLoadOn = AutoLoad.isOn
    @Published var errorMessage: String?
    @Published var dropTargeted = false
    @Published var pageText = ""
    @Published var mode: PrintMode {
        // Back sides only is a one-off recovery, so the next PDF opens in the last normal mode.
        didSet { if mode != .backsOnly { UserDefaults.standard.set(mode.rawValue, forKey: "printMode") } }
    }

    private(set) var activeJob: Int?
    private var cancelled = false
    private var refreshing = false
    private var workFolder: URL?
    private var timer: Timer?

    init() {
        mode = PrintMode.saved
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                Model.shared.refreshPrinter()
                Model.shared.refreshQueue()
            }
        }
        refreshPrinter()
        refreshQueue()
    }

    var isPrinting: Bool {
        if case .printing = step { return true }
        return false
    }

    var isMidJob: Bool {
        switch step {
        case .printing, .reload: return true
        default: return false
        }
    }

    var canPrint: Bool {
        !busy && queue.jobs.isEmpty && [.ready, .needsFirmware, .loadingFirmware].contains(printer) && selectionProblem == nil
    }

    var selectedPages: Result<[Int], Error>? {
        guard case .confirm(let pdf) = step else { return nil }
        return Result { try PageSelection.parse(pageText, pageCount: pdf.pageCount) }
    }

    var effectiveMode: PrintMode {
        if case .success(let pages)? = selectedPages, pages.count == 1, mode == .bothSides { return .oneSide }
        return mode
    }

    var selectionProblem: String? {
        switch selectedPages {
        case .failure(let error)?: return error.localizedDescription
        case .success(let pages)? where mode == .backsOnly && pages.count < 2: return "One page has no back side. Choose at least 2 pages."
        default: return nil
        }
    }

    var queueProblem: QueueProblem? {
        let status = queue.status
        let reasons = status.reasons.map(PrintQueue.describe)
        if status.needsResume {
            let detail = ([status.message] + reasons).filter { !$0.isEmpty }.joined(separator: " ")
            return QueueProblem(
                title: "Printing is paused",
                detail: detail.isEmpty ? "The print system stopped sending to the printer." : detail,
                canResume: true
            )
        }
        if !reasons.isEmpty {
            return QueueProblem(title: "The printer reports a problem", detail: reasons.joined(separator: " "), canResume: false)
        }
        if let active = queue.jobs.first(where: { $0.state == .processing }),
           let started = active.startedAt, Date().timeIntervalSince(started) > 120 {
            return QueueProblem(
                title: "This job is taking a long time",
                detail: "If nothing is coming out, cancel it, switch the printer off and on, then print again.",
                canResume: false
            )
        }
        return nil
    }

    var failedJobToShow: QueuedJob? {
        guard let last = queue.lastFinished, last.state == .aborted, last.number != dismissedFailure else { return nil }
        return last
    }

    func refreshPrinter() {
        guard !refreshing, !busy else { return }
        refreshing = true
        Task {
            let state = await Task.detached { () -> PrinterState? in
                if FirmwareLock.isHeld { return .loadingFirmware }
                if PrintQueue.hasJobs() { return nil }
                return Printer.state()
            }.value
            refreshing = false
            if !busy, let state { printer = state }
        }
    }

    func refreshQueue() {
        Task {
            if let snapshot = await Task.detached(operation: { PrintQueue.snapshot() }).value {
                queue = snapshot
            }
        }
    }

    func cancelJob(_ job: QueuedJob) {
        if job.number == activeJob { cancelled = true }
        afterQueueChange { PrintQueue.cancel(job.number) }
    }

    func releaseJob(_ job: QueuedJob) {
        afterQueueChange { PrintQueue.release(job.number) }
    }

    func clearQueue() {
        if activeJob != nil { cancelled = true }
        afterQueueChange { PrintQueue.cancelAll() }
    }

    func resumeQueue() {
        afterQueueChange { PrintQueue.resume() }
    }

    func dismissFailure() {
        guard let failed = failedJobToShow else { return }
        dismissedFailure = failed.number
        UserDefaults.standard.set(failed.number, forKey: "dismissedFailedJob")
    }

    private func afterQueueChange(_ change: @escaping @Sendable () -> Void) {
        Task {
            await Task.detached(operation: change).value
            refreshQueue()
        }
    }

    func choosePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.message = "Choose a PDF to print"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard !isMidJob else {
            errorMessage = "Finish the print that's running first."
            return
        }
        do {
            discardWorkFolder()
            let folder = FileManager.default.temporaryDirectory.appending(path: "LaserJet 1020/\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            workFolder = folder
            let copy = folder.appending(path: url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: copy)
            guard let document = PDFDocument(url: copy), document.pageCount > 0 else {
                throw PrintError("“\(url.lastPathComponent)” can't be opened as a PDF.")
            }
            guard !document.isLocked else {
                throw PrintError("“\(url.lastPathComponent)” is password-protected. Unlock it in Preview first.")
            }
            pageText = ""
            if mode == .backsOnly { mode = PrintMode.saved }
            step = .confirm(PickedPDF(url: copy, name: url.lastPathComponent, pageCount: document.pageCount))
        } catch {
            discardWorkFolder()
            step = .choose
            errorMessage = error.localizedDescription
        }
    }

    func start() {
        guard case .confirm(let pdf) = step, case .success(let pages)? = selectedPages, selectionProblem == nil else { return }
        let previous = step
        let mode = effectiveMode
        perform(restoring: previous) {
            guard let folder = self.workFolder else { throw PrintError("The PDF's working copy is gone. Open it again.") }
            if mode == .oneSide {
                try await self.ensureFirmware()
                let file = pages.count == pdf.pageCount ? pdf.url : folder.appending(path: "selected.pdf")
                if file != pdf.url { try await Task.detached { try Sides.write(pages, of: pdf.url, to: file) }.value }
                try await self.printAndWait(file, title: pdf.name, message: "Printing \(pdf.name)…", detail: pageWord(pages.count))
                self.step = .finished("Sent \(pageWord(pages.count)) to the printer.")
                return
            }
            let backs = folder.appending(path: "backs.pdf")
            // Measured on this printer: with the stack moved to the upper tray as it comes out, unturned backs print upside down.
            try await Task.detached { try Sides.write(Sides.backs(of: pages), of: pdf.url, to: backs, turned: true) }.value
            let back = BackPrint(pdf: pdf, pages: pages, file: backs, frontsJustPrinted: mode == .bothSides)
            if mode == .bothSides {
                try await self.ensureFirmware()
                let fronts = folder.appending(path: "fronts.pdf")
                let frontPages = Sides.fronts(of: pages)
                try await Task.detached { try Sides.write(frontPages, of: pdf.url, to: fronts) }.value
                try await self.printAndWait(
                    fronts, title: "\(pdf.name) – front sides", message: "Printing the front sides…",
                    detail: "Pages \(PageSelection.listed(frontPages)) on \(back.sheets) sheets"
                )
            }
            self.step = .reload(back)
        }
    }

    func printBacks() {
        guard case .reload(let back) = step else { return }
        let previous = step
        perform(restoring: previous) {
            try await self.ensureFirmware()
            try await self.printAndWait(
                back.file, title: "\(back.pdf.name) – back sides", message: "Printing the back sides…",
                detail: "Pages \(PageSelection.listed(Sides.backs(of: back.pages).compactMap { $0 }.sorted()))"
            )
            self.step = .finished("All done. Your pages are printed on both sides.")
        }
    }

    func cancelPrinting() {
        guard let job = activeJob else { return }
        cancelled = true
        afterQueueChange { PrintQueue.cancel(job) }
    }

    func loadFirmwareNow() {
        let previous = step
        perform(restoring: previous) { try await self.ensureFirmware() }
    }

    func reset() {
        discardWorkFolder()
        step = .choose
    }

    func setAutoLoad(_ on: Bool) {
        do {
            if on { try AutoLoad.turnOn() } else { try AutoLoad.turnOff() }
        } catch {
            errorMessage = error.localizedDescription
        }
        autoLoadOn = AutoLoad.isOn
    }

    func discardWorkFolder() {
        if let workFolder { try? FileManager.default.removeItem(at: workFolder) }
        workFolder = nil
    }

    private func perform(restoring previous: Step, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await work()
            } catch {
                step = previous
                if !(error is CancellationError) { errorMessage = error.localizedDescription }
            }
        }
    }

    private func ensureFirmware() async throws {
        let state = await Task.detached { () -> PrinterState in
            FirmwareLock.isHeld ? .loadingFirmware : Printer.state()
        }.value
        printer = state
        switch state {
        case .ready:
            return
        case .off, .unknown:
            throw PrintError("The printer is off or not connected. Switch it on, check the USB cable and try again.")
        case .needsFirmware, .loadingFirmware:
            printer = .loadingFirmware
            do {
                try await Task.detached { try Printer.loadFirmware() }.value
                printer = .ready
            } catch {
                printer = .needsFirmware
                throw error
            }
        }
    }

    private func printAndWait(_ file: URL, title: String, message: String, detail: String?) async throws {
        cancelled = false
        let job = try await Task.detached { try Printer.submit(file, title: title) }.value
        activeJob = job
        defer { activeJob = nil }
        step = .printing(message, detail: detail)
        refreshQueue()
        while try await Task.detached(operation: { try PrintQueue.isQueued(job) }).value {
            try await Task.sleep(for: .seconds(1))
        }
        if cancelled { throw CancellationError() }
        let finished = await Task.detached { PrintQueue.finishedJob(job) }.value
        switch finished?.state {
        case .canceled:
            throw CancellationError()
        case .aborted:
            let reason = finished?.reasons.first.map(PrintQueue.describe) ?? "The print system gave up on it."
            throw PrintError("“\(title)” didn't print. \(reason)")
        default:
            return
        }
    }
}

struct QueueProblem {
    let title: String
    let detail: String
    let canResume: Bool
}
