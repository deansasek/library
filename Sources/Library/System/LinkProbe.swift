import Foundation

/// Asks one address whether its page loads. The first request is a HEAD, which reads no page content. A server that
/// refuses HEAD (403, 405, or 501) gets one GET instead, and its status is the answer. Each request follows up to
/// `LinkCheck.maxRedirects` redirects to web addresses. The session keeps no cookies and no cache, and gives up after
/// `LinkCheck.timeout`. Foundation only, so a harness outside the app can run it.
enum LinkProbe {
    static func check(_ url: URL, version: String) async -> LinkStatus.Kind {
        guard WebFetch.isWeb(url) else { return .unreachable }
        let head = await fetch(url, method: "HEAD", version: version)
        guard LinkCheck.retriesWithGET(afterHEAD: head.statusCode) else {
            return LinkCheck.outcome(statusCode: head.statusCode, redirectRefused: head.refused)
        }
        let get = await fetch(url, method: "GET", version: version)
        return LinkCheck.outcome(statusCode: get.statusCode, redirectRefused: get.refused)
    }

    /// One request with `method`. It reads the body only up to `LinkCheck.getBodyLimit` bytes, which a HEAD does not
    /// have, and then ends the request, so the rest of a large page is never downloaded. The status is taken before
    /// the body is read, so an error in the body does not change it.
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
            let (body, response) = try await session.bytes(for: request, delegate: redirects)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            var read = 0
            do {
                for try await _ in body {
                    read += 1
                    if read == LinkCheck.getBodyLimit { break }
                }
            } catch {}
            return (statusCode, redirects.refused)
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
        if LinkCheck.followsRedirect(after: followed, to: request.url) {
            followed += 1
            completionHandler(request)
        } else {
            refused = true
            completionHandler(nil)
        }
    }
}
