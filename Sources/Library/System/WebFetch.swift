import Foundation

/// Rules shared by the downloads Library makes from addresses it did not get from the user directly (favicons,
/// GIFs copied from web pages). Only web addresses are fetched, redirects stay on web addresses, and a body is
/// cut off once it passes a limit, so an oversized response is never held in memory in full.
enum WebFetch {
    /// True for `http` and `https` addresses. Other schemes (`file`, custom app schemes) are never fetched, since
    /// URLSession would read local files for `file` addresses.
    static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
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
        guard isWeb(url) else { return nil }
        return await withCheckedContinuation { continuation in
            let collector = Collector(limit: limit) { continuation.resume(returning: $0) }
            let session = URLSession(configuration: .ephemeral, delegate: collector, delegateQueue: nil)
            session.dataTask(with: URLRequest(url: url, timeoutInterval: 10)).resume()
        }
    }

    /// Collects one download on the session's delegate queue. It cancels the download when the body is too large.
    private final class Collector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private var limit: BodyLimit
        private var body = Data()
        private var response: HTTPURLResponse?
        private var tooLarge = false
        private let finish: @Sendable ((data: Data, response: HTTPURLResponse)?) -> Void

        init(limit: Int, finish: @escaping @Sendable ((data: Data, response: HTTPURLResponse)?) -> Void) {
            self.limit = BodyLimit(limit: limit)
            self.finish = finish
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            let http = response as? HTTPURLResponse
            self.response = http
            if let length = http?.expectedContentLength, length > Int64(limit.limit) {
                tooLarge = true
                completionHandler(.cancel)
            } else {
                completionHandler(.allow)
            }
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard limit.add(data.count) else {
                tooLarge = true
                dataTask.cancel()
                return
            }
            body.append(data)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(request.url.map(isWeb) == true ? request : nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            session.finishTasksAndInvalidate()
            guard error == nil, !tooLarge, let response else {
                finish(nil)
                return
            }
            finish((body, response))
        }
    }
}
