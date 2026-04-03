import AppKit
import AuthenticationServices
import ChooseBrowserCore
import Foundation
import WebKit

@MainActor
final class AuthenticationSessionService: NSObject {
    private let logStore = AppLogStore.shared
    private let onRequestUserInterface: () -> Void
    private var activeRequest: ASWebAuthenticationSessionRequest?
    private var authenticationWindow: NSWindow?
    private var webView: WKWebView?
    private var isClosingWindowProgrammatically = false

    init(onRequestUserInterface: @escaping () -> Void) {
        self.onRequestUserInterface = onRequestUserInterface
    }

    func installSessionHandler() {
        ASWebAuthenticationSessionWebBrowserSessionManager.shared.sessionHandler = self
        logStore.append("Installed AuthenticationServices session handler.")
    }

    var wasLaunchedByAuthenticationServices: Bool {
        ASWebAuthenticationSessionWebBrowserSessionManager.shared.wasLaunchedByAuthenticationServices
    }

    private func start(request: ASWebAuthenticationSessionRequest) {
        cancelActiveRequestIfNeeded()

        activeRequest = request
        request.delegate = self
        logStore.append("Auth session started for \(request.url.absoluteString) [uuid=\(request.uuid.uuidString), ephemeral=\(request.shouldUseEphemeralSession)].")

        onRequestUserInterface()

        let webView = makeWebView(for: request)
        self.webView = webView

        let window = authenticationWindow ?? makeAuthenticationWindow()
        authenticationWindow = window
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        var urlRequest = URLRequest(url: request.url)
        if #available(macOS 14.4, *), let additionalHeaderFields = request.additionalHeaderFields {
            logStore.append("Auth session provided \(additionalHeaderFields.count) additional header fields.")
            for (header, value) in additionalHeaderFields {
                urlRequest.setValue(value, forHTTPHeaderField: header)
            }
        }

        webView.load(urlRequest)
    }

    private func makeWebView(for request: ASWebAuthenticationSessionRequest) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = request.shouldUseEphemeralSession ? .nonPersistent() : .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        return webView
    }

    private func makeAuthenticationWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppIdentity.displayName) Sign In"
        window.minSize = NSSize(width: 640, height: 520)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    private func completeAuthentication(with callbackURL: URL) {
        guard let activeRequest else {
            return
        }

        self.activeRequest = nil
        logStore.append("Auth session completed with callback URL: \(callbackURL.absoluteString)")
        activeRequest.complete(withCallbackURL: callbackURL)
        cleanupWindow()
    }

    private func cancelActiveRequestIfNeeded() {
        guard let activeRequest else {
            return
        }

        self.activeRequest = nil
        logStore.append("Auth session cancelled for \(activeRequest.url.absoluteString).")
        activeRequest.cancelWithError(Self.canceledLoginError)
        cleanupWindow()
    }

    private func cancelMatchingRequestIfNeeded(_ request: ASWebAuthenticationSessionRequest) {
        guard activeRequest?.uuid == request.uuid else {
            return
        }

        activeRequest = nil
        logStore.append("Auth session ended for request \(request.uuid.uuidString).")
        cleanupWindow()
    }

    private func cleanupWindow() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil

        guard let authenticationWindow else {
            return
        }

        authenticationWindow.contentView = nil
        authenticationWindow.delegate = nil
        isClosingWindowProgrammatically = true
        authenticationWindow.close()
        isClosingWindowProgrammatically = false
        self.authenticationWindow = nil
    }

    private func matchesCallback(url: URL, for request: ASWebAuthenticationSessionRequest) -> Bool {
        if #available(macOS 14.4, *), let callback = request.callback {
            return callback.matchesURL(url)
        }

        guard let callbackURLScheme = request.callbackURLScheme else {
            return false
        }

        return url.scheme?.caseInsensitiveCompare(callbackURLScheme) == .orderedSame
    }

    private static let canceledLoginError = NSError(
        domain: ASWebAuthenticationSessionErrorDomain,
        code: ASWebAuthenticationSessionError.canceledLogin.rawValue
    )
}

extension AuthenticationSessionService: ASWebAuthenticationSessionWebBrowserSessionHandling {
    nonisolated func begin(_ request: ASWebAuthenticationSessionRequest) {
        let retainedRequest = Int(bitPattern: Unmanaged.passRetained(request).toOpaque())
        MainActor.assumeIsolated {
            let pointer = UnsafeMutableRawPointer(bitPattern: retainedRequest)!
            let request = Unmanaged<ASWebAuthenticationSessionRequest>.fromOpaque(pointer).takeRetainedValue()
            self.logStore.append("AuthenticationServices called begin() for \(request.url.absoluteString).")
            self.start(request: request)
        }
    }

    nonisolated func cancel(_ request: ASWebAuthenticationSessionRequest) {
        let retainedRequest = Int(bitPattern: Unmanaged.passRetained(request).toOpaque())
        MainActor.assumeIsolated {
            let pointer = UnsafeMutableRawPointer(bitPattern: retainedRequest)!
            let request = Unmanaged<ASWebAuthenticationSessionRequest>.fromOpaque(pointer).takeRetainedValue()
            self.logStore.append("AuthenticationServices called cancel() for \(request.url.absoluteString).")
            self.cancelMatchingRequestIfNeeded(request)
        }
    }
}

extension AuthenticationSessionService: ASWebAuthenticationSessionRequestDelegate {
    nonisolated func authenticationSessionRequest(
        _ authenticationSessionRequest: ASWebAuthenticationSessionRequest,
        didCompleteWithCallbackURL callbackURL: URL
    ) {
        let retainedRequest = Int(bitPattern: Unmanaged.passRetained(authenticationSessionRequest).toOpaque())
        MainActor.assumeIsolated {
            let pointer = UnsafeMutableRawPointer(bitPattern: retainedRequest)!
            let request = Unmanaged<ASWebAuthenticationSessionRequest>.fromOpaque(pointer).takeRetainedValue()
            self.logStore.append("AuthenticationServices delegate reported completion for request \(request.uuid.uuidString).")
            self.cancelMatchingRequestIfNeeded(request)
        }
    }

    nonisolated func authenticationSessionRequest(
        _ authenticationSessionRequest: ASWebAuthenticationSessionRequest,
        didCancelWithError error: any Error
    ) {
        let retainedRequest = Int(bitPattern: Unmanaged.passRetained(authenticationSessionRequest).toOpaque())
        MainActor.assumeIsolated {
            let pointer = UnsafeMutableRawPointer(bitPattern: retainedRequest)!
            let request = Unmanaged<ASWebAuthenticationSessionRequest>.fromOpaque(pointer).takeRetainedValue()
            self.logStore.append("AuthenticationServices delegate reported cancellation for request \(request.uuid.uuidString): \(error.localizedDescription)")
            self.cancelMatchingRequestIfNeeded(request)
        }
    }
}

extension AuthenticationSessionService: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let activeRequest, let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let isMainFrameNavigation = navigationAction.targetFrame?.isMainFrame ?? true
        guard isMainFrameNavigation else {
            decisionHandler(.allow)
            return
        }

        if matchesCallback(url: url, for: activeRequest) {
            logStore.append("Auth session matched callback navigation: \(url.absoluteString)")
            completeAuthentication(with: url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

extension AuthenticationSessionService: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else {
            return nil
        }

        webView.load(navigationAction.request)
        return nil
    }
}

extension AuthenticationSessionService: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        defer {
            authenticationWindow = nil
            webView = nil
        }

        guard !isClosingWindowProgrammatically, let activeRequest else {
            return
        }

        self.activeRequest = nil
        logStore.append("Auth session window closed by user for \(activeRequest.url.absoluteString).")
        activeRequest.cancelWithError(Self.canceledLoginError)
    }
}
