import Foundation

/// Asks one address whether its page loads. The first request is a HEAD, which reads no page content. A server that
/// refuses HEAD (405 or 501) gets one GET instead, and its status is the answer. Each request follows up to
/// `LinkCheck.maxRedirects` redirects to web addresses. The session keeps no cookies and no cache, and gives up after
/// `LinkCheck.timeout`. Foundation only, so a harness outside the app can run it.
enum LinkProbe {
    static func check(_ url: URL, version: String) async -> LinkStatus.Kind {
        guard await WebFetch.isAllowed(url) else { return .unreachable }
        let head = await fetch(url, method: "HEAD", version: version)
        guard LinkCheck.retriesWithGET(afterHEAD: head.statusCode) else {
            return LinkCheck.outcome(statusCode: head.statusCode, redirectRefused: head.refused)
        }
        let get = await fetch(url, method: "GET", version: version)
        return LinkCheck.outcome(statusCode: get.statusCode, redirectRefused: get.refused)
    }

    /// One request with `method`. Only the status is needed, so the body is never read: the response's status is
    /// captured as soon as the headers arrive, and ending the session cancels the rest of the download.
    private static func fetch(_ url: URL, method: String, version: String) async -> (statusCode: Int?, refused: Bool) {
        var request = URLRequest(url: url, timeoutInterval: LinkCheck.timeout)
        request.httpMethod = method
        request.setValue("Library/\(version)", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = LinkCheck.timeout
        configuration.timeoutIntervalForResource = LinkCheck.timeout
        return await withCheckedContinuation { continuation in
            // A serial queue runs every delegate call, so the gate's state is never shared.
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let gate = RedirectGate { continuation.resume(returning: $0) }
            let session = URLSession(configuration: configuration, delegate: gate, delegateQueue: queue)
            let task = session.dataTask(with: request)
            gate.task = task
            task.resume()
        }
    }
}

/// Runs one link-check request. It follows up to the limit of redirects, stops at an address that is not web, and
/// records that it refused one, so the request is not taken for a working page. It captures the final status as soon
/// as the headers arrive, and checks every connection the request made, so a host that resolves to a private address
/// only when the request is made is refused too.
final class RedirectGate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var followed = 0
    private(set) var refused = false
    private var statusCode: Int?
    private var finished = false
    var task: URLSessionDataTask?
    private let finish: @Sendable ((statusCode: Int?, refused: Bool)) -> Void

    init(finish: @escaping @Sendable ((statusCode: Int?, refused: Bool)) -> Void) {
        self.finish = finish
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        statusCode = (response as? HTTPURLResponse)?.statusCode
        // Only the status is needed, so the rest of the download is cancelled.
        completionHandler(.cancel)
    }

    /// Called after every connection the request made, but before it completes. See `WebFetch.isPrivateConnection`.
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        if WebFetch.isPrivateConnection(metrics.transactionMetrics.map(\.remoteAddress)) {
            refused = true
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        finished = true
        session.finishTasksAndInvalidate()
        finish((statusCode, refused))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if LinkCheck.followsRedirect(after: followed, from: response.url, to: request.url),
           request.url.map({ !WebFetch.isLocalTarget($0) }) == true {
            followed += 1
            completionHandler(request)
        } else {
            refused = true
            completionHandler(nil)
        }
    }
}
