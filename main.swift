import AppKit
import SwiftUI

if CommandLine.arguments.contains(AutoLoad.connectedFlag) {
    AutoLoad.handlePrinterConnected()
}
LaserJetApp.main()

struct LaserJetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = Model.shared

    var body: some Scene {
        Window("LaserJet 1020", id: "main") {
            ContentView().environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { Model.shared.open(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        Model.shared.discardWorkFolder()
    }
}
