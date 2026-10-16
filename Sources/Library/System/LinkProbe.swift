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
    /// returned as soon as the headers arrive, and ending the session cancels the rest of the download.
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
        let session = URLSession(configuration: configuration)
        // Cancels any body still downloading when the request ends.
        defer { session.invalidateAndCancel() }
        let redirects = RedirectGate()
        do {
            let (_, response) = try await session.bytes(for: request, delegate: redirects)
            return ((response as? HTTPURLResponse)?.statusCode, redirects.refused)
        } catch {
            return (nil, redirects.refused)
        }
    }
}

/// Counts the redirects one request follows. It stops at the limit, or at an address that is not web, and records
/// that it refused, so the request is not taken for a working page.
final class RedirectGate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var followed = 0
    private(set) var refused = false

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
