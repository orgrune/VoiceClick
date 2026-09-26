import AppKit
import Combine
import WebKit

final class AppModel: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate {
    static let defaultURL = "https://app.quantic.edu/course/136267fd-0b9d-4420-a433-b94e793da97f/chapter/0/lesson/27d74298-71cf-4978-9a9a-7e19691d4bce/show"

    @Published var urlString = AppModel.defaultURL
    @Published var isListening = false
    @Published var status = "Not listening"
    @Published var heard = ""
    @Published var lastCommand = ""
    @Published var lastResult = ""
    @Published var lastOK = true
    @Published var candidates: [String] = []
    @Published var log: [String] = []

    let webView: WKWebView
    private let speech = SpeechListener()
    private var pollTimer: Timer?

    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        super.init()
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        speech.onPartial = { [weak self] text in self?.heard = text }
        speech.onCommand = { [weak self] text in self?.handleCommand(text) }
        speech.onStatus = { [weak self] text in self?.status = text }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshCandidates()
        }
    }

    // MARK: - Navigation

    func load() {
        var s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) else { return }
        webView.load(URLRequest(url: url))
    }

    // MARK: - Listening

    func toggleListening() {
        if isListening { stopListening() } else { startListening() }
    }

    func startListening() {
        status = "Requesting microphone and speech permissions…"
        speech.requestPermissions { [weak self] ok, message in
            guard let self else { return }
            guard ok else { self.status = message; return }
            do {
                try self.speech.start()
                self.isListening = true
            } catch {
                self.status = "Could not start: \(error.localizedDescription)"
            }
        }
    }

    func stopListening() {
        speech.stop()
        isListening = false
        status = "Not listening"
        heard = ""
    }

    // MARK: - Commands

    func handleCommand(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lastCommand = t
        heard = ""

        let lower = t.lowercased().trimmingCharacters(in: .punctuationCharacters)
        switch lower {
        case "stop listening":
            stopListening()
            report(ok: true, "Stopped listening", for: t)
            return
        case "scroll down", "scroll up":
            webView.evaluateJavaScript("window.scrollBy({top: \(lower == "scroll down" ? 500 : -500), behavior: 'smooth'})")
            report(ok: true, "Scrolled", for: t)
            return
        case "go back":
            webView.goBack()
            report(ok: true, "Went back", for: t)
            return
        case "reload", "refresh":
            webView.reload()
            report(ok: true, "Reloaded", for: t)
            return
        default:
            break
        }

        Clicker.click(spoken: t, in: webView) { [weak self] outcome in
            self?.report(ok: outcome.ok, outcome.message, for: t)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.refreshCandidates() }
        }
    }

    func refreshCandidates() {
        Clicker.list(in: webView) { [weak self] list in
            guard let self, list != self.candidates else { return }
            self.candidates = list
        }
    }

    private func report(ok: Bool, _ message: String, for command: String) {
        lastOK = ok
        lastResult = message
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.insert("\(stamp)  “\(command)” → \(message)", at: 0)
        if log.count > 100 { log.removeLast() }
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url?.absoluteString { urlString = url }
        refreshCandidates()
    }
}
