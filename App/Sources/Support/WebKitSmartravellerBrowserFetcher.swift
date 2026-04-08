import Foundation
import NomadCore
import WebKit

actor WebKitSmartravellerBrowserFetcher: SmartravellerBrowserFetcher {
    func destinationsHTML() async throws -> String {
        let loader = await MainActor.run { SmartravellerWebViewLoader() }
        return try await loader.load()
    }
}

@MainActor
private final class SmartravellerWebViewLoader: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
    }

    func load() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                self?.finish(
                    .failure(
                        BrowserFetchError(
                            diagnosticSummary: "Smartraveller browser fallback timed out.",
                            description: "Timed out while loading Smartraveller in hidden WKWebView fallback."
                        )
                    )
                )
            }

            let request = URLRequest(
                url: Self.destinationsURL,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 20
            )
            webView.load(request)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] value, error in
            guard let self else {
                return
            }

            if let error {
                Task { self.finish(.failure(error)) }
                return
            }

            guard let html = value as? String, html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                Task {
                    self.finish(
                        .failure(
                            BrowserFetchError(
                                diagnosticSummary: "Smartraveller browser fallback returned empty HTML.",
                                description: "Hidden WKWebView fallback produced no HTML content."
                            )
                        )
                    )
                }
                return
            }

            Task { self.finish(.success(html)) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { finish(.failure(error)) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { finish(.failure(error)) }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else {
            return
        }

        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        switch result {
        case let .success(html):
            continuation.resume(returning: html)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }

    private static let destinationsURL = URL(string: "https://www.smartraveller.gov.au/destinations")!
}

private struct BrowserFetchError: Error {
    let diagnosticSummary: String
    let description: String
}
