import Foundation
import PDFKit

@main
struct SplitCheck {
    static func main() throws {
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let original = PDFDocument(url: source), original.pageCount >= 4 else {
            fatalError("Pass a PDF with at least 4 pages that look different from each other.")
        }
        let count = original.pageCount
        let folder = FileManager.default.temporaryDirectory.appending(path: "split-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sourcePictures = (0..<count).map { pixels(of: original.page(at: $0)!) }

        let blank = count % 2 == 1 ? [0] : []
        let cases: [(text: String, turn: Bool, fronts: [Int], backs: [Int])] = [
            ("", false, Array(stride(from: 1, through: count, by: 2)), blank + Array(stride(from: count - count % 2, through: 2, by: -2))),
            ("", true, Array(stride(from: 1, through: count, by: 2)), blank + Array(stride(from: count - count % 2, through: 2, by: -2))),
            ("1-3", true, [1, 3], [0, 2]),
            ("1-3", false, [1, 3], [0, 2]),
            ("\(count - 1) - \(count)", true, [count - 1], [count]),
            ("4, 1-2 3", false, [1, 3], [4, 2]),
            ("3-", true, Array(stride(from: 3, through: count, by: 2)), blank + Array(stride(from: count - count % 2, through: 4, by: -2))),
        ]
        for c in cases {
            let pages = try PageSelection.parse(c.text, pageCount: count)
            let frontsURL = folder.appending(path: "fronts.pdf")
            let backsURL = folder.appending(path: "backs.pdf")
            try Sides.write(Sides.fronts(of: pages), of: source, to: frontsURL)
            try Sides.write(Sides.backs(of: pages), of: source, to: backsURL, turned: c.turn)
            let fronts = PDFDocument(url: frontsURL)!
            let backs = PDFDocument(url: backsURL)!
            let frontNumbers = matches(in: fronts, against: sourcePictures, turned: false)
            let backNumbers = matches(in: backs, against: sourcePictures, turned: c.turn)
            let flags = (0..<backs.pageCount).map { backs.page(at: $0)!.rotation }
            let blanksEmpty = c.backs.indices.filter { c.backs[$0] == 0 }.allSatisfy { pixels(of: backs.page(at: $0)!).allSatisfy { $0 == 255 } }
            check(frontNumbers == c.fronts && backNumbers == c.backs && flags.allSatisfy { $0 == 0 } && blanksEmpty,
                  "pages “\(c.text)”\(c.turn ? ", backs drawn turned" : ""): fronts \(frontNumbers), backs \(backNumbers), page flags \(Set(flags).sorted())")
        }

        for text in ["0", "\(count + 1)", "2-\(count + 5)", "abc", "-", "1-2-3"] {
            let refused = (try? PageSelection.parse(text, pageCount: count)) == nil
            check(refused, "pages “\(text)” refused")
        }
        check(PageSelection.listed([1, 2, 3, 5, 7, 8]) == "1–3, 5, 7, 8", "listing joins runs of 3 or more")
        check(PageSelection.firstSheetUnlikeDocument([1, 2, 3, 4, 5]) == nil, "odd-started selection keeps the document's sheets")
        check(PageSelection.firstSheetUnlikeDocument([6, 7, 8]).map { [$0.front, $0.back] } == [6, 7], "even start is flagged")
        check(PageSelection.firstSheetUnlikeDocument([1, 2, 3, 5]).map { [$0.front, $0.back] } == [3, 5], "a skipped page is flagged")
        exit(failures == 0 ? 0 : 1)
    }

    static var failures = 0

    static func check(_ ok: Bool, _ label: String) {
        print("\(ok ? "PASS" : "FAIL") \(label)")
        if !ok { failures += 1 }
    }

    // Each output page is identified as the source page whose picture it matches, upright or turned 180°.
    // 0 means it matched no source page clearly, or matched one only the other way round.
    static func matches(in document: PDFDocument, against sources: [[UInt8]], turned: Bool) -> [Int] {
        (0..<document.pageCount).map { index in
            let picture = pixels(of: document.page(at: index)!)
            let scores = sources.map { source in
                (upright: difference(picture, source, turned: false), turned: difference(picture, source, turned: true))
            }
            let wanted = scores.map { turned ? $0.turned : $0.upright }
            guard let best = wanted.indices.min(by: { wanted[$0] < wanted[$1] }) else { return 0 }
            let other = turned ? scores[best].upright : scores[best].turned
            let runnerUp = wanted.enumerated().filter { $0.offset != best }.map(\.element).min() ?? Int.max
            return wanted[best] * 2 < runnerUp && wanted[best] * 2 < other ? best + 1 : 0
        }
    }

    static func difference(_ a: [UInt8], _ b: [UInt8], turned: Bool) -> Int {
        var total = 0
        for index in a.indices {
            total += abs(Int(a[index]) - Int(b[turned ? b.count - 1 - index : index]))
        }
        return total
    }

    static func pixels(of page: PDFPage) -> [UInt8] {
        let width = 120, height = 170
        var buffer = [UInt8](repeating: 255, count: width * height)
        buffer.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            )!
            let box = page.bounds(for: .mediaBox)
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: CGFloat(width) / box.width, y: CGFloat(height) / box.height)
            page.draw(with: .mediaBox, to: context)
        }
        return buffer
    }
}
