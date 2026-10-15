import Foundation

/// Rules shared by the downloads Library makes from addresses it did not get from the user directly (favicons,
/// GIFs copied from web pages, page titles). Only web addresses are fetched, redirects stay on web addresses, and a
/// body is cut off once it passes a limit, so an oversized response is never held in memory in full.
enum WebFetch {
    /// True for `http` and `https` addresses. Other schemes (`file`, custom app schemes) are never fetched, since
    /// URLSession would read local files for `file` addresses.
    static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// True when a redirect from `from` to `to` would turn an https address into a plain http one. Such a redirect is
    /// refused, so a download that started as https never ends as http.
    static func isDowngrade(from source: URL?, to target: URL?) -> Bool {
        source?.scheme?.lowercased() == "https" && target?.scheme?.lowercased() == "http"
    }

    /// True when a request may be made to `url`: a web address whose host is not this Mac or a private network. Every
    /// request from a bookmark, a clipboard link, or a Services selection goes through this check. It resolves the
    /// host, so it runs off the main thread.
    static func isAllowed(_ url: URL) async -> Bool {
        guard isWeb(url) else { return false }
        return await Task.detached { !WebFetch.isLocalTarget(url) }.value
    }

    /// True when `url` has no host, names localhost or a `.local` name, or has a host that resolves to a loopback,
    /// private, link-local, or unspecified address. A host that does not resolve is not local: its request fails.
    static func isLocalTarget(_ url: URL) -> Bool {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return true }
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }
        if isPrivateAddress(host) { return true }
        return resolvedAddresses(of: host).contains(where: isPrivateAddress)
    }

    /// True for loopback (127/8, ::1), unspecified (0/8, ::), private (10/8, 172.16/12, 192.168/16, fc00::/7),
    /// link-local (169.254/16, fe80::/10), and IPv4-mapped IPv6 addresses of those. Other addresses are public.
    static func isPrivateAddress(_ address: String) -> Bool {
        let text = address.lowercased().split(separator: "%").first.map(String.init) ?? address.lowercased()
        if text.contains(":") {
            if text.hasPrefix("::ffff:"), text.contains(".") {
                return isPrivateAddress(String(text.dropFirst("::ffff:".count)))
            }
            if text == "::" || text == "::1" { return true }
            let first = text.split(separator: ":", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let group = Int(first.isEmpty ? "0" : first, radix: 16) ?? 0
            return (group & 0xFE00) == 0xFC00 || (group & 0xFFC0) == 0xFE80
        }
        let octets = text.split(separator: ".", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        let (a, b) = (octets[0], octets[1])
        return a == 0 || a == 10 || a == 127
            || (a == 169 && b == 254)
            || (a == 172 && (16...31).contains(b))
            || (a == 192 && b == 168)
    }

    /// The numeric addresses a host name resolves to, or none when it does not resolve.
    static func resolvedAddresses(of host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &list) == 0, let first = list else { return [] }
        defer { freeaddrinfo(list) }
        var addresses: [String] = []
        var node: UnsafeMutablePointer<addrinfo>? = first
        while let entry = node {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(entry.pointee.ai_addr, entry.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0,
                           NI_NUMERICHOST) == 0 {
                addresses.append(String(cString: buffer))
            }
            node = entry.pointee.ai_next
        }
        return addresses
    }

    /// How one download is made. The defaults are the favicon rules: a 10 s limit, any number of redirects, and a
    /// body over `limit` is a failure.
    struct Options {
        var limit: Int
        /// The most seconds the whole download may take, from the request to the last byte.
        var timeout: TimeInterval = 10
        /// The most redirects followed. Nil follows as many as URLSession allows.
        var maxRedirects: Int?
        /// Sent as the User-Agent header. Nil keeps URLSession's own.
        var userAgent: String?
        /// When true, a body over `limit` is cut at the limit and returned as it is, instead of failing.
        var keepsPrefix = false
    }

    /// Counts the bytes of a body against its limit.
    struct BodyLimit {
        let limit: Int
        private(set) var count = 0

        init(limit: Int) {
            self.limit = limit
        }

        /// Counts `bytes` more. False once the body is over the limit.
        mutating func add(_ bytes: Int) -> Bool {
            count += bytes
            return count <= limit
        }
    }

    /// Downloads `url` with a 10 s timeout. Returns the body and response, or nil when the address is not web, the
    /// request fails, a redirect leaves web addresses, or the body is over `limit`. The download stops as soon as the
    /// limit is passed. The session keeps no cookies and no cache, so nothing from the browser is sent.
    static func fetch(_ url: URL, limit: Int) async -> (data: Data, response: HTTPURLResponse)? {
        await fetch(url, options: Options(limit: limit))
    }

    /// Downloads `url` as `options` describe. The session keeps no cookies and no cache, so nothing from the browser
    /// is sent. Only the `keepsPrefix` option changes what a body over the limit gives: the cut-off body.
    static func fetch(_ url: URL, options: Options) async -> (data: Data, response: HTTPURLResponse)? {
        guard await isAllowed(url) else { return nil }
        return await withCheckedContinuation { continuation in
            // A serial queue runs every delegate call and the deadline, so the collector's state is never shared.
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let collector = Collector(options: options) { continuation.resume(returning: $0) }
            let session = URLSession(configuration: .ephemeral, delegate: collector, delegateQueue: queue)
            var request = URLRequest(url: url, timeoutInterval: options.timeout)
            if let agent = options.userAgent {
                request.setValue(agent, forHTTPHeaderField: "User-Agent")
            }
            let task = session.dataTask(with: request)
            collector.task = task
            task.resume()
            // The deadline counts the whole download, not the time between bytes.
            DispatchQueue.global().asyncAfter(deadline: .now() + options.timeout) {
                queue.addOperation { collector.expire() }
            }
        }
    }

    /// Collects one download on the session's delegate queue. It cancels the download when the body is too large
    /// or the deadline passes, and counts redirects against the most allowed.
    private final class Collector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private var limit: BodyLimit
        private let options: WebFetch.Options
        private var body = Data()
        private var response: HTTPURLResponse?
        private var redirects = 0
        /// True once the download failed for a reason that makes its body unusable.
        private var failed = false
        /// True once the body was cut at the limit on purpose, which `keepsPrefix` allows.
        private var truncated = false
        private var finished = false
        var task: URLSessionDataTask?
        private let finish: @Sendable ((data: Data, response: HTTPURLResponse)?) -> Void

        init(options: WebFetch.Options, finish: @escaping @Sendable ((data: Data, response: HTTPURLResponse)?) -> Void) {
            self.options = options
            self.limit = BodyLimit(limit: options.limit)
            self.finish = finish
        }

        /// Called on the delegate queue when the deadline passes. A download that already ended is not changed.
        func expire() {
            guard !finished else { return }
            failed = true
            task?.cancel()
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            let http = response as? HTTPURLResponse
            self.response = http
            if let length = http?.expectedContentLength, length > Int64(limit.limit), !options.keepsPrefix {
                failed = true
                completionHandler(.cancel)
            } else {
                completionHandler(.allow)
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard limit.add(data.count) else {
                if options.keepsPrefix {
                    // Keeps only what fits under the limit, then stops reading.
                    body.append(data.prefix(max(0, limit.limit - body.count)))
                    truncated = true
                } else {
                    failed = true
                }
                dataTask.cancel()
                return
            }
            body.append(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            redirects += 1
            let allowed = request.url.map { WebFetch.isWeb($0) && !WebFetch.isLocalTarget($0) } == true
                && !isDowngrade(from: response.url, to: request.url)
                && (options.maxRedirects.map { redirects <= $0 } ?? true)
            if !allowed { failed = true }
            completionHandler(allowed ? request : nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            finished = true
            session.finishTasksAndInvalidate()
            guard !failed, let response, error == nil || truncated else {
                finish(nil)
                return
            }
            finish((body, response))
        }
    }
}
