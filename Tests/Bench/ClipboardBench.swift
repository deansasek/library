import AppKit
import CryptoKit

// Clipboard benchmark. It prints timings and never fails. Run it with ./test.sh, or compile it with the app's
// sources as test.sh does. It uses private pasteboards and temporary files, so it never touches your clipboard
// or your library. It uses only the public surface of ClipboardHistory, so it also runs against older code.
//
// Measures, over 5 runs (median reported):
//   - pinned load: a clipboard.json of 200 items of 20 KB text. "init blocks main" is the time the initializer
//     takes on the main actor. "all 200 ready" is the time until every item is in `items`.
//   - one copy of a 10 MB PNG: "poll, main thread" is the synchronous part of poll(), the only work on the main
//     actor before the copy returns. "until item added" runs the rest until the item is in the history.

@MainActor
enum ClipboardBench {
    static let runs = 5
    static let itemCount = 200
    static let textBytes = 20_000

    static func ms(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// Runs the main loop until `done` is true or the timeout passes, so main-actor work can finish.
    static func pump(timeout: TimeInterval, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
    }

    /// Distinct text per item, so no two items share a digest.
    static func pinnedText(_ index: Int) -> String {
        let unit = "Pinned item \(index). The quick brown fox jumps over the lazy dog, again and again.\n"
        let repeated = String(repeating: unit, count: textBytes / unit.utf8.count + 1)
        return String(repeated.prefix(textBytes))
    }

    /// A PNG of random pixels, about 10 MB (2600 x 1300 RGB). Random data barely compresses, so the PNG is close to the raw size.
    static func noisyPNG() -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2600, pixelsHigh: 1300, bitsPerSample: 8,
                                         samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let bytes = rep.bitmapData else { return nil }
        for index in 0..<(rep.bytesPerRow * rep.pixelsHigh) {
            bytes[index] = UInt8.random(in: 0...255)
        }
        return rep.representation(using: .png, properties: [:])
    }

    static func main() {
        let key = SymmetricKey(size: .bits256)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-clipboard-bench-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // ---- pinned load ----
        let file = directory.appendingPathComponent("clipboard.json")
        let clips = (0..<itemCount).map { index in
            PinnedFile.Clip(source: "Bench", date: Date(timeIntervalSinceNow: -Double(index) * 60),
                            representations: [["public.utf8-plain-text": Data(pinnedText(index).utf8)]])
        }
        if let sealed = try? PinnedFile.encode(clips, key: key), (try? sealed.write(to: file)) != nil {
            var blocked: [Double] = [], ready: [Double] = []
            for _ in 0..<runs {
                let board = NSPasteboard(name: NSPasteboard.Name("library-bench-load-\(UUID().uuidString)"))
                let start = ContinuousClock.now
                let history = ClipboardHistory(pasteboard: board, file: file, key: { key })
                let initialized = ContinuousClock.now
                pump(timeout: 60) { history.items.count >= itemCount }
                let done = ContinuousClock.now
                if history.items.count != itemCount { print("  warning: \(history.items.count) of \(itemCount) items loaded") }
                blocked.append(ms(initialized - start))
                ready.append(ms(done - start))
            }
            print("Clipboard benchmark, pinned file of \(itemCount) items x \(textBytes / 1_000) KB text, median of \(runs) runs")
            print(String(format: "  init blocks main:                     %9.3f ms", median(blocked)))
            print(String(format: "  all \(itemCount) ready:                       %9.3f ms", median(ready)))
        } else {
            print("Clipboard benchmark: could not write the pinned file")
        }

        // ---- one copy of a 10 MB image ----
        guard let png = noisyPNG() else {
            print("Clipboard benchmark: could not make the image")
            return
        }
        let board = NSPasteboard(name: NSPasteboard.Name("library-bench-copy-\(UUID().uuidString)"))
        let history = ClipboardHistory(pasteboard: board, file: nil, key: { key })
        var synchronous: [Double] = [], untilAdded: [Double] = []
        for _ in 0..<runs {
            board.clearContents()
            let item = NSPasteboardItem()
            item.setData(png, forType: .png)
            board.writeObjects([item])
            let before = history.items.count
            let start = ContinuousClock.now
            history.poll()
            let returned = ContinuousClock.now
            pump(timeout: 60) { history.pendingCaptures == 0 }
            let added = ContinuousClock.now
            if history.items.count != before + 1 { print("  warning: the copy was not added") }
            synchronous.append(ms(returned - start))
            untilAdded.append(ms(added - start))
            history.clear()
        }
        print("Clipboard benchmark, one copy of a \(png.count / 1_000_000) MB PNG, median of \(runs) runs")
        print(String(format: "  poll, main thread (synchronous part): %9.3f ms", median(synchronous)))
        print(String(format: "  until item added:                     %9.3f ms", median(untilAdded)))
    }
}
