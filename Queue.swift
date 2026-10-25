import Foundation

enum JobState: Int {
    case pending = 3, held, processing, stopped, canceled, aborted, completed
}

struct QueuedJob: Identifiable, Equatable {
    let number: Int
    let name: String
    let state: JobState
    let reasons: [String]
    let message: String
    let kilobytes: Int
    let startedAt: Date?
    var id: Int { number }
}

struct QueueStatus: Equatable {
    var stopped = false
    var accepting = true
    var reasons: [String] = []
    var message = ""

    var needsResume: Bool { stopped || !accepting }
}

struct QueueSnapshot: Equatable {
    var status = QueueStatus()
    var jobs: [QueuedJob] = []
    var lastFinished: QueuedJob?
}

enum PrintQueue {
    static func hasJobs() -> Bool {
        !((try? Printer.run("/usr/bin/lpstat", ["-o", Printer.queue])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isQueued(_ job: Int) throws -> Bool {
        let id = "\(Printer.queue)-\(job)"
        return try Printer.run("/usr/bin/lpstat", ["-o", Printer.queue])
            .split(separator: "\n")
            .contains { $0.split(separator: " ").first.map(String.init) == id }
    }

    static func snapshot() -> QueueSnapshot? {
        guard let tests = ipp(queueTests, variables: [:]), tests.count == 3 else { return nil }
        let printer = groups(of: tests[0]).first ?? [:]
        let status = QueueStatus(
            stopped: printer["printer-state"] as? Int == 5,
            accepting: printer["printer-is-accepting-jobs"] as? Bool ?? true,
            reasons: strings(printer["printer-state-reasons"]).filter { !ignoredReasons.contains($0) },
            message: strings(printer["printer-state-message"]).first ?? ""
        )
        let jobs = groups(of: tests[1]).compactMap(job).sorted { $0.number < $1.number }
        return QueueSnapshot(status: status, jobs: jobs, lastFinished: groups(of: tests[2]).compactMap(job).first)
    }

    static func finishedJob(_ number: Int) -> QueuedJob? {
        guard let tests = ipp(jobTest, variables: ["job": String(number)]) else { return nil }
        return tests.first.flatMap { groups(of: $0).compactMap(job).first }
    }

    static func cancel(_ job: Int) {
        _ = try? Printer.run("/usr/bin/cancel", ["\(Printer.queue)-\(job)"])
    }

    static func cancelAll() {
        _ = try? Printer.run("/usr/bin/cancel", ["-a", Printer.queue])
    }

    static func release(_ job: Int) {
        _ = try? Printer.run("/usr/bin/lp", ["-i", "\(Printer.queue)-\(job)", "-H", "resume"])
    }

    static func resume() {
        _ = try? Printer.run("/usr/sbin/cupsenable", [Printer.queue])
        _ = try? Printer.run("/usr/sbin/cupsaccept", [Printer.queue])
    }

    static func describe(_ reason: String) -> String {
        var base = reason
        for suffix in ["-error", "-warning", "-report"] where base.hasSuffix(suffix) {
            base.removeLast(suffix.count)
        }
        switch base {
        case "media-empty", "media-needed": return "Out of paper. Load paper in the tray."
        case "media-jam": return "Paper jam. Open the printer and pull out the stuck paper."
        case "door-open", "cover-open": return "A cover is open. Close it."
        case "toner-empty", "marker-supply-empty": return "The toner cartridge is empty."
        case "toner-low", "marker-supply-low": return "Toner is low."
        case "offline", "shutdown": return "The printer is offline. Check that it's on and the USB cable is plugged in."
        case "connecting-to-device": return "Connecting to the printer…"
        case "timed-out": return "The printer stopped responding."
        case "cups-missing-filter": return "The driver is missing a part it needs to print this file."
        case "job-canceled-by-user": return "Cancelled."
        case "job-canceled-at-device": return "Cancelled at the printer."
        case "aborted-by-system": return "The print system gave up on it."
        case "document-format", "document-unprintable", "document-format-not-supported": return "The file couldn't be turned into something the printer understands."
        case "job-data-insufficient": return "The print system didn't get the whole file."
        default:
            let words = base.replacingOccurrences(of: "-", with: " ")
            return words.prefix(1).uppercased() + words.dropFirst() + "."
        }
    }

    private static let ignoredReasons: Set<String> = [
        "none", "paused", "cups-waiting-for-job-completed", "processing-to-stop-point",
        "job-incoming", "job-printing", "job-queued", "job-hold-until-specified", "job-completed-successfully",
    ]

    private static func job(_ group: [String: Any]) -> QueuedJob? {
        guard let number = group["job-id"] as? Int,
              let state = (group["job-state"] as? Int).flatMap(JobState.init) else { return nil }
        return QueuedJob(
            number: number,
            name: strings(group["job-name"]).first ?? "Job \(number)",
            state: state,
            reasons: strings(group["job-state-reasons"]).filter { !ignoredReasons.contains($0) },
            message: strings(group["job-printer-state-message"]).first ?? "",
            kilobytes: group["job-k-octets"] as? Int ?? 0,
            startedAt: (group["time-at-processing"] as? Int).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private static func groups(of test: [String: Any]) -> [[String: Any]] {
        Array((test["ResponseAttributes"] as? [[String: Any]] ?? []).dropFirst())
    }

    private static func strings(_ value: Any?) -> [String] {
        if let values = value as? [Any] { return values.compactMap { $0 as? String } }
        if let text = value as? String, text != "<<no-value>>", !text.isEmpty { return [text] }
        return []
    }

    private static func ipp(_ tests: String, variables: [String: String]) -> [[String: Any]]? {
        let file = FileManager.default.temporaryDirectory.appending(path: "laserjet-1020-\(UUID().uuidString).test")
        guard (try? tests.write(to: file, atomically: true, encoding: .utf8)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        let arguments = ["-X"] + variables.flatMap { ["-d", "\($0.key)=\($0.value)"] }
            + ["ipp://localhost/printers/\(Printer.queue)", file.path]
        guard let output = try? Printer.run("/usr/bin/ipptool", arguments),
              let plist = try? PropertyListSerialization.propertyList(from: Data(output.utf8), format: nil) as? [String: Any] else { return nil }
        return plist["Tests"] as? [[String: Any]]
    }

    private static let jobAttributes = "job-id,job-name,job-state,job-state-reasons,job-printer-state-message,job-k-octets,time-at-processing"

    private static let queueTests = """
    {
    NAME "Printer"
    OPERATION Get-Printer-Attributes
    GROUP operation-attributes-tag
    ATTR charset attributes-charset utf-8
    ATTR naturalLanguage attributes-natural-language en
    ATTR uri printer-uri $uri
    ATTR keyword requested-attributes printer-state,printer-state-reasons,printer-state-message,printer-is-accepting-jobs
    STATUS successful-ok
    }
    {
    NAME "Waiting"
    OPERATION Get-Jobs
    GROUP operation-attributes-tag
    ATTR charset attributes-charset utf-8
    ATTR naturalLanguage attributes-natural-language en
    ATTR uri printer-uri $uri
    ATTR name requesting-user-name $user
    ATTR keyword which-jobs not-completed
    ATTR keyword requested-attributes \(jobAttributes)
    STATUS successful-ok
    }
    {
    NAME "Finished"
    OPERATION Get-Jobs
    GROUP operation-attributes-tag
    ATTR charset attributes-charset utf-8
    ATTR naturalLanguage attributes-natural-language en
    ATTR uri printer-uri $uri
    ATTR name requesting-user-name $user
    ATTR keyword which-jobs completed
    ATTR integer limit 1
    ATTR keyword requested-attributes \(jobAttributes)
    STATUS successful-ok
    }
    """

    private static let jobTest = """
    {
    NAME "Job"
    OPERATION Get-Job-Attributes
    GROUP operation-attributes-tag
    ATTR charset attributes-charset utf-8
    ATTR naturalLanguage attributes-natural-language en
    ATTR uri printer-uri $uri
    ATTR integer job-id $job
    ATTR name requesting-user-name $user
    ATTR keyword requested-attributes \(jobAttributes)
    STATUS successful-ok
    }
    """
}
