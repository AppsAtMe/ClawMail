import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct DAVAuthenticationProbeResult {
    let url: URL
    let data: Data?
    let response: URLResponse?

    static func direct(_ url: URL) -> Self {
        DAVAuthenticationProbeResult(url: url, data: nil, response: nil)
    }
}

final class DAVRedirectPreservingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let serviceName: String
    private let templateRequest: URLRequest

    init(serviceName: String, templateRequest: URLRequest) {
        self.serviceName = serviceName
        self.templateRequest = templateRequest
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let redirectedURL = request.url,
              (try? DAVURLValidator.validateConfiguredURL(redirectedURL, serviceName: serviceName)) != nil else {
            let source = response.url?.absoluteString ?? "<unknown>"
            let blocked = request.url?.absoluteString ?? "<unknown>"
            fputs("ClawMail \(serviceName): blocked redirect \(source) -> \(blocked)\n", stderr)
            completionHandler(nil)
            return
        }

        let source = response.url?.absoluteString ?? "<unknown>"
        fputs("ClawMail \(serviceName): redirect HTTP \(response.statusCode) \(source) -> \(redirectedURL.absoluteString)\n", stderr)

        var redirectedRequest = request
        redirectedRequest.httpMethod = templateRequest.httpMethod
        redirectedRequest.httpBody = templateRequest.httpBody
        redirectedRequest.httpBodyStream = nil
        for (field, value) in templateRequest.allHTTPHeaderFields ?? [:] {
            redirectedRequest.setValue(value, forHTTPHeaderField: field)
        }

        completionHandler(redirectedRequest)
    }
}
