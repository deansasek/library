import AppKit

// Timings for the changes of the security and performance audit (docs/audit-2026-10.md). Printing only, never
// failing, like the rest of Tests/Bench. The "before" rows run the code the fix replaced, where that code still exists.

/// Holds the result of `blockingRun`, written on another thread before the main thread reads it.
private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

/// Runs async work to completion from synchronous code, for the checks. The work must not need the main actor,
/// since the main thread waits here until it finishes.
func blockingRun<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        box.value = await work()
        done.signal()
    }
    done.wait()
    return box.value!
}

/// Runs `body` `runs` times, awaiting each run, and prints the median time per run in milliseconds.
func timeAsync(_ label: String, runs: Int = 9, _ body: () async -> Void) async {
    var samples: [Double] = []
    for _ in 0..<runs {
        let start = ContinuousClock.now
        await body()
        let elapsed = ContinuousClock.now - start
        samples.append(Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15)
    }
    samples.sort()
    print(String(format: "  %-60@ %9.3f ms", label as NSString, samples[samples.count / 2]))
}

/// A 512 KB body as an async sequence, which is what URLSession's byte stream looks like to the reader.
private func bodyStream(_ count: Int = 512 * 1024) -> AsyncStream<UInt8> {
    AsyncStream(UInt8.self) { continuation in
        for _ in 0..<count { continuation.yield(7) }
        continuation.finish()
    }
}

func runAuditBenchmark() async {
    print("Audit benchmark, median of 9 runs")
    // Before: the favicon reader took each byte from URLSession's byte stream and appended it. The stream here stands in
    // for URLSession's, which needs a network to time.
    await timeAsync("favicon body 512 KB, before (per byte, stand-in stream)") {
        var data = Data()
        for await byte in bodyStream() {
            data.append(byte)
            guard data.count <= 512 * 1024 else { break }
        }
    }
    // After: the download arrives in chunks, each counted against the limit and appended once. This is the work the
    // delegate does per chunk.
    let chunk = Data(repeating: 7, count: 16 * 1024)
    await timeAsync("favicon body 512 KB, after (16 KB chunks, counted)") {
        var limit = WebFetch.BodyLimit(limit: 512 * 1024)
        var data = Data()
        for _ in 0..<32 {
            _ = limit.add(chunk.count)
            data.append(chunk)
        }
    }
    // Quick Open runs the calculator on every keystroke. A pasted line is now refused before it is parsed.
    let longLine = String(repeating: "(", count: 300) + "1"
    await timeAsync("quick answer, 300-character line") {
        for _ in 0..<1_000 { _ = QuickAnswers.answer(for: longLine) }
    }
    // The Quick Open watch runs on the main thread every half second. This is what one window-list query costs.
    await timeAsync("window list query for the Spotlight watch") {
        for _ in 0..<20 { _ = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) }
    }
    // Icon caches stay bounded: 5,000 different paths leave the default capacity in place.
    let paths = (0..<5_000).map { "/Applications/Copied \($0).app" }
    await timeAsync("icon cache, 5,000 distinct copied files") {
        let cache = IconCache(capacity: IconCache.defaultCapacity)
        for path in paths { _ = cache.icon(at: path, modified: nil) { NSImage() } }
    }
}
