import Foundation

@main
struct QueueCheck {
    static var failures = 0

    static func check(_ ok: Bool, _ label: String) {
        print("\(ok ? "PASS" : "FAIL") \(label)")
        if !ok { failures += 1 }
    }

    static func main() throws {
        guard !PrintQueue.hasJobs() else { fatalError("Empty the print queue before running this check.") }
        let note = FileManager.default.temporaryDirectory.appending(path: "queue-check.txt")
        try "queue check".write(to: note, atomically: true, encoding: .utf8)
        try Printer.run("/usr/bin/lp", ["-d", Printer.queue, "-H", "hold", "-t", "Queue check – held", note.path])
        defer {
            PrintQueue.cancelAll()
            PrintQueue.resume()
        }

        let jobs = PrintQueue.snapshot()?.jobs ?? []
        check(jobs.count == 1 && jobs[0].name == "Queue check – held" && jobs[0].state == .held, "held job is listed as held: \(jobs)")

        do {
            _ = try Printer.submit(note, title: "Second job")
            check(false, "a second job was accepted while one was queued")
        } catch {
            check(true, "a second job is refused: \(error.localizedDescription)")
        }

        try Printer.run("/usr/sbin/cupsdisable", ["-r", "Queue check pause", Printer.queue])
        let paused = PrintQueue.snapshot()?.status
        check(paused?.needsResume == true && paused?.message == "Queue check pause", "a paused queue is reported with its reason: \(String(describing: paused))")
        PrintQueue.resume()
        check(PrintQueue.snapshot()?.status.needsResume == false, "Resume turns the queue back on")

        let number = jobs.first?.number ?? 0
        PrintQueue.cancel(number)
        check(PrintQueue.finishedJob(number)?.state == .canceled, "a cancelled job reads back as cancelled")
        check(!PrintQueue.hasJobs() && PrintQueue.snapshot()?.jobs.isEmpty == true, "the queue is empty afterwards")
        exit(failures == 0 ? 0 : 1)
    }
}
