import Foundation
import XPC

enum AutoLoad {
    static let connectedFlag = "--printer-connected"
    static let label = "local.laserjet-1020.firmware"
    static let plistURL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/LaunchAgents/\(label).plist")
    static let logURL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Logs/LaserJet 1020.log")

    static var isOn: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    private static var domain: String { "gui/\(getuid())" }

    static func turnOn() throws {
        guard let executable = Bundle.main.executablePath else { throw PrintError("Can't find this app's own program file.") }
        let agent: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, connectedFlag],
            "LaunchEvents": [
                "com.apple.iokit.matching": [
                    "hp-laserjet-1020": [
                        "IOProviderClass": "IOUSBHostDevice",
                        "idVendor": 0x03f0,
                        "idProduct": 0x2b17,
                        "IOMatchLaunchStream": true,
                    ],
                ],
            ],
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path,
        ]
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0).write(to: plistURL)
        _ = try? Printer.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        try Printer.run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
    }

    static func turnOff() throws {
        _ = try? Printer.run("/bin/launchctl", ["bootout", "\(domain)/\(label)"])
        if isOn { try FileManager.default.removeItem(at: plistURL) }
    }

    // launchd relaunches the job until the IOKit event is taken through this stream handler.
    static func handlePrinterConnected() -> Never {
        xpc_set_event_stream_handler("com.apple.iokit.matching", DispatchQueue.main) { _ in }
        DispatchQueue.global().async {
            log("Printer connected")
            for _ in 0..<20 {
                let downloading = FileManager.default.fileExists(atPath: FirmwareLock.url.path)
                switch downloading ? .loadingFirmware : Printer.state() {
                case .ready:
                    log("Firmware already loaded")
                    exit(0)
                case .needsFirmware, .loadingFirmware:
                    do {
                        try Printer.loadFirmware()
                        log("Firmware loaded")
                    } catch {
                        log("Firmware didn't load: \(error.localizedDescription)")
                    }
                    exit(0)
                case .off, .unknown:
                    sleep(1)
                }
            }
            log("The printer never answered")
            exit(0)
        }
        dispatchMain()
    }

    private static func log(_ message: String) {
        print("\(Date().formatted(date: .numeric, time: .standard))  \(message)")
        fflush(stdout)
    }
}
