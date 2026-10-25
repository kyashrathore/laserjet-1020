import AppKit
import SwiftUI

@main
struct Snapshot {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let pdf = URL(fileURLWithPath: CommandLine.arguments[2])
        let windowHeight = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3]) : nil
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = Model.shared

        model.step = .choose
        try render("1-choose", in: folder, height: windowHeight)
        model.open(pdf)
        guard case .confirm(let picked) = model.step else { fatalError("Couldn't open \(pdf.path)") }
        for (name, mode, pages) in [
            ("2-one-side", PrintMode.oneSide, ""), ("3-both-sides", .bothSides, ""),
            ("4-backs-only", .backsOnly, ""), ("5-both-sides-even-start", .bothSides, "2-7"), ("6-bad-pages", .oneSide, "40"),
        ] {
            model.mode = mode
            model.pageText = pages
            try render(name, in: folder, height: windowHeight)
        }
        let pages = Array(1...picked.pageCount)
        model.step = .printing("Printing the front sides…", detail: "Pages \(PageSelection.listed(Sides.fronts(of: pages)))")
        try render("7-printing", in: folder, height: windowHeight)
        model.step = .reload(BackPrint(pdf: picked, pages: pages, file: pdf, frontsJustPrinted: true))
        try render("8-reload", in: folder, height: windowHeight)
        model.step = .reload(BackPrint(pdf: picked, pages: pages, file: pdf, frontsJustPrinted: false))
        try render("9-reload-backs-only", in: folder, height: windowHeight)
        model.step = .finished("All done. Your pages are printed on both sides.")
        try render("10-finished", in: folder, height: windowHeight)
        model.discardWorkFolder()
    }

    @MainActor
    static func render(_ name: String, in folder: URL, height: Double?) throws {
        let host = NSHostingView(rootView: ContentView().environmentObject(Model.shared))
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.wantsLayer = true
        let ideal = host.fittingSize
        window.setContentSize(NSSize(width: ideal.width, height: height ?? ideal.height))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let scale = 2.0
        let size = host.bounds.size
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        window.appearance!.performAsCurrentDrawingAppearance {
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
        window.contentView!.layer!.render(in: context)
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appending(path: "\(name).png"))
        print("\(name): ideal \(Int(ideal.width))×\(Int(ideal.height))")
    }
}
