import Foundation

/// Asks one address whether its page loads: a single HEAD request, following up to `LinkCheck.maxRedirects` redirects
/// to web addresses. The session keeps no cookies and no cache, and gives up after `LinkCheck.timeout`. Foundation
/// only, so a harness outside the app can run it.
enum LinkProbe {
    static func check(_ url: URL, version: String) async -> LinkStatus.Kind {
        guard WebFetch.isWeb(url) else { return .unreachable }
        var request = URLRequest(url: url, timeoutInterval: LinkCheck.timeout)
        request.httpMethod = "HEAD"
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
        defer { session.finishTasksAndInvalidate() }
        let redirects = RedirectGate()
        do {
            let (_, response) = try await session.data(for: request, delegate: redirects)
            return LinkCheck.outcome(statusCode: (response as? HTTPURLResponse)?.statusCode,
                                     redirectRefused: redirects.refused)
        } catch {
            return .unreachable
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
