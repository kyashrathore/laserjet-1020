import Foundation
import PDFKit

enum PageSelection {
    static func parse(_ text: String, pageCount: Int) throws -> [Int] {
        let normalized = text
            .replacingOccurrences(of: "[–—]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "\\s*-\\s*", with: "-", options: .regularExpression)
        let parts = normalized.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        guard !parts.isEmpty else { return Array(1...pageCount) }
        var pages = Set<Int>()
        for part in parts {
            let ends = part.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let first = ends[0].isEmpty ? 1 : Int(ends[0])
            let last = ends.count == 1 ? first : ends[1].isEmpty ? pageCount : Int(ends[1])
            guard let first, let last, ends.count == 1 || !(ends[0].isEmpty && ends[1].isEmpty) else {
                throw PrintError("“\(part)” isn't a page or a range like 5-12.")
            }
            for page in [first, last] where !(1...pageCount).contains(page) {
                throw PrintError("There's no page \(page). This PDF has \(pageWord(pageCount)).")
            }
            pages.formUnion(min(first, last)...max(first, last))
        }
        return pages.sorted()
    }

    static func listed(_ pages: [Int]) -> String {
        var runs: [ClosedRange<Int>] = []
        for page in pages {
            if let last = runs.last, last.upperBound + 1 == page {
                runs[runs.count - 1] = last.lowerBound...page
            } else {
                runs.append(page...page)
            }
        }
        let words = runs.flatMap { run in
            run.count >= 3 ? ["\(run.lowerBound)–\(run.upperBound)"] : run.map(String.init)
        }
        guard words.count > 7 else { return words.joined(separator: ", ") }
        return words.prefix(3).joined(separator: ", ") + " … " + words.suffix(2).joined(separator: ", ")
    }

    // The document's own sheets are 1|2, 3|4 …; a selection starting on an even page or skipping one pairs other pages.
    static func firstSheetUnlikeDocument(_ pages: [Int]) -> (front: Int, back: Int)? {
        stride(from: 0, to: pages.count - 1, by: 2)
            .map { (front: pages[$0], back: pages[$0 + 1]) }
            .first { $0.front % 2 == 0 || $0.back != $0.front + 1 }
    }
}

func pageWord(_ count: Int) -> String {
    count == 1 ? "1 page" : "\(count) pages"
}

enum Sides {
    static func fronts(of pages: [Int]) -> [Int] {
        pages.indices.filter { $0 % 2 == 0 }.map { pages[$0] }
    }

    // The printer feeds the top sheet of the reloaded stack first, and that sheet holds the last front printed, so backs go in reverse.
    // With an odd page count that top sheet has no back; a blank page (nil) carries it through, so the whole stack goes back in as it is.
    static func backs(of pages: [Int]) -> [Int?] {
        let backs = pages.indices.filter { $0 % 2 == 1 }.map { pages[$0] }.reversed()
        return (pages.count % 2 == 1 ? [nil] : []) + backs.map { Optional($0) }
    }

    static func write(_ pageNumbers: [Int?], of source: URL, to url: URL, turned: Bool = false) throws {
        guard let document = PDFDocument(url: source) else { throw PrintError("This file can't be opened as a PDF.") }
        let blankSize = document.page(at: (pageNumbers.compactMap { $0 }.first ?? 1) - 1)?.bounds(for: .mediaBox)
        let selected = PDFDocument()
        for pageNumber in pageNumbers {
            guard let pageNumber else {
                let blank = PDFPage()
                blank.setBounds(blankSize ?? CGRect(x: 0, y: 0, width: 595, height: 842), for: .mediaBox)
                selected.insert(blank, at: selected.pageCount)
                continue
            }
            guard let page = document.page(at: pageNumber - 1)?.copy() as? PDFPage else {
                throw PrintError("Page \(pageNumber) of this PDF can't be read.")
            }
            selected.insert(page, at: selected.pageCount)
        }
        guard turned ? writeTurned(selected, to: url) : selected.write(to: url) else {
            throw PrintError("Couldn't prepare the pages to print.")
        }
    }

    // A /Rotate 180 page flag is undone by macOS printing, which turns pages back upright to fit the paper,
    // so each page's content is drawn upside down onto an unflagged page instead.
    private static func writeTurned(_ document: PDFDocument, to url: URL) -> Bool {
        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else { return false }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { return false }
            let bounds = page.bounds(for: .mediaBox)
            let quarterTurned = page.rotation % 180 != 0
            var box = CGRect(
                x: 0, y: 0,
                width: quarterTurned ? bounds.height : bounds.width,
                height: quarterTurned ? bounds.width : bounds.height
            )
            context.beginPage(mediaBox: &box)
            context.translateBy(x: box.width, y: box.height)
            context.rotate(by: .pi)
            page.draw(with: .mediaBox, to: context)
            context.endPage()
        }
        context.closePDF()
        return true
    }
}
