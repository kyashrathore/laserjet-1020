import Foundation

struct PrintError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum PrinterState {
    case unknown, off, needsFirmware, loadingFirmware, ready
}

enum Printer {
    static let queue = "HP_LaserJet_1020"
    static let firmwareURL = URL(fileURLWithPath: NSHomeDirectory())
        .appending(path: "Library/Printers/HP LaserJet 1020/sihp1020.dl")

    static func state() -> PrinterState {
        guard let devices = try? run("/usr/sbin/lpinfo", ["--include-schemes", "usb", "-l", "-v"]) else { return .unknown }
        guard let deviceId = devices.split(separator: "\n").first(where: {
            $0.contains("device-id =") && $0.contains("MDL:HP LaserJet 1020;")
        }) else { return .off }
        // FWVER appears in the 1020's device ID only once its firmware is loaded.
        return deviceId.contains("FWVER:") ? .ready : .needsFirmware
    }

    static let switchOffAndOn = PrintError("The printer didn't take its firmware. Switch it off, wait 5 seconds, switch it on, then try again.")

    // While one firmware download was still going in, a second download plus device ID reads left the printer
    // refusing all data until it was switched off. So the app and the auto-load job share one download through
    // a lock file, and nothing reads the device ID until that download has left the queue.
    static func loadFirmware() throws {
        guard FileManager.default.fileExists(atPath: firmwareURL.path) else {
            throw PrintError("The printer's firmware file is missing from \(firmwareURL.path).")
        }
        let job = try FirmwareLock.currentOrNewDownload {
            PrintQueue.resume()
            return try submit(firmwareURL, title: "LaserJet 1020 firmware", raw: true)
        }
        defer { FirmwareLock.release() }
        let deadline = Date().addingTimeInterval(30)
        while try PrintQueue.isQueued(job) {
            guard Date() < deadline else {
                PrintQueue.cancel(job)
                throw switchOffAndOn
            }
            sleep(1)
        }
        for _ in 0..<10 {
            if state() == .ready { return }
            sleep(2)
        }
        throw switchOffAndOn
    }

    static func submit(_ file: URL, title: String, raw: Bool = false) throws -> Int {
        guard !PrintQueue.hasJobs() else {
            throw PrintError("A job is still in the print queue. Wait for it to finish, or cancel it in the print queue, then try again.")
        }
        var arguments = ["-d", queue, "-t", title]
        if raw { arguments += ["-o", "raw"] }
        let reply = try run("/usr/bin/lp", arguments + [file.path])
        guard let id = reply.split(separator: " ").first(where: { $0.hasPrefix(queue + "-") }),
              let number = Int(id.dropFirst(queue.count + 1)) else {
            throw PrintError("The print system didn't accept the job: \(reply)")
        }
        return number
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let reason = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PrintError(reason.isEmpty ? "\(tool) failed." : reason)
        }
        return output
    }
}

enum FirmwareLock {
    static let url = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Printers/HP LaserJet 1020/.firmware-download")
    private static let staleAfter: TimeInterval = 90

    static var isHeld: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func currentOrNewDownload(_ send: () throws -> Int) throws -> Int {
        for _ in 0..<2 {
            let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
            if descriptor >= 0 {
                close(descriptor)
                do {
                    let job = try send()
                    try String(job).write(to: url, atomically: true, encoding: .utf8)
                    return job
                } catch {
                    release()
                    throw error
                }
            }
            if let job = jobOfFreshLock() { return job }
            release()
        }
        throw PrintError("Another firmware download is stuck. Switch the printer off and on, then try again.")
    }

    static func release() {
        try? FileManager.default.removeItem(at: url)
    }

    private static func jobOfFreshLock() -> Int? {
        for _ in 0..<10 {
            guard let created = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.creationDate] as? Date,
                  Date().timeIntervalSince(created) < staleAfter else { return nil }
            let text = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let job = Int(text) { return job }
            sleep(1)
        }
        return nil
    }
}
