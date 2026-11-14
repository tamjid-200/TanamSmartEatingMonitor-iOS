import WebKit
import Combine
import SwiftUI

/// In-app YouTube browser. Sign-in persists (default website data store).
/// Video is controlled through injected JS on the page's <video> element.
class YouTubeWebView: WKWebView {
    private let navDelegate = WebViewNavigationDelegate()
    private let webUIDelegate = WebViewUIDelegate()

    static let safariUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// Must be configured BEFORE the web view is created — WKWebView copies its configuration.
    static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()          // keeps Google/YouTube login
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false

        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: videoControlJS,
                                              injectionTime: .atDocumentEnd,
                                              forMainFrameOnly: true))
        controller.add(VideoStateHandler(), name: "videoState")
        config.userContentController = controller
        return config
    }

    static func make() -> YouTubeWebView {
        YouTubeWebView(frame: .zero, configuration: makeConfiguration())
    }

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        customUserAgent = YouTubeWebView.safariUserAgent
        allowsBackForwardNavigationGestures = true
        navigationDelegate = navDelegate
        uiDelegate = webUIDelegate
        scrollView.contentInsetAdjustmentBehavior = .automatic
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func loadYouTube(useKids: Bool = false) {
        let url = URL(string: useKids ? "https://www.youtubekids.com" : "https://m.youtube.com")!
        load(URLRequest(url: url))
    }

    func pauseVideo() {
        evaluateJavaScript("window.TANAM && window.TANAM.pause(); 0") { _, _ in }
    }

    func playVideo() {
        evaluateJavaScript("window.TANAM && window.TANAM.play(); 0") { _, _ in }
    }

    func isVideoPlaying(completion: @escaping (Bool) -> Void) {
        evaluateJavaScript("window.TANAM ? window.TANAM.isPlaying() : false") { result, _ in
            completion(result as? Bool ?? false)
        }
    }

    /// While locked, keep pausing in case the page auto-plays the next video.
    func enforcePaused() {
        evaluateJavaScript("window.TANAM && window.TANAM.setLocked(true); 0") { _, _ in }
    }

    func releasePause() {
        evaluateJavaScript("window.TANAM && window.TANAM.setLocked(false); 0") { _, _ in }
    }

    func signOut(reloadKids: Bool = false) {
        let store = WKWebsiteDataStore.default()
        let domains = ["google", "youtube", "gstatic", "ytimg"]
        store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
            let toRemove = records.filter { record in
                domains.contains { record.displayName.lowercased().contains($0) }
            }
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: toRemove) { [weak self] in
                self?.loadYouTube(useKids: reloadKids)
            }
        }
    }

    private static let videoControlJS = """
    (function() {
        if (window.TANAM) return;
        var locked = false;
        function video() { return document.querySelector('video'); }
        function attach(v) {
            if (!v || v.__tanam) return;
            v.__tanam = true;
            v.addEventListener('play', function() {
                if (locked) { v.pause(); return; }
                window.webkit.messageHandlers.videoState.postMessage({ playing: true });
            });
            v.addEventListener('pause', function() {
                window.webkit.messageHandlers.videoState.postMessage({ playing: false });
            });
        }
        function check() {
            var v = video();
            if (v) { attach(v); if (locked && !v.paused) { v.pause(); } }
        }
        new MutationObserver(check).observe(document.documentElement, { childList: true, subtree: true });
        setInterval(check, 1000);
        window.TANAM = {
            play: function() { var v = video(); if (v) { v.play().catch(function(){}); } },
            pause: function() { var v = video(); if (v) { v.pause(); } },
            isPlaying: function() { var v = video(); return v ? (!v.paused && !v.ended) : false; },
            setLocked: function(value) { locked = value; check(); }
        };
        check();
    })();
    """
}

/// Keeps browsing on YouTube/Google; other links open in Safari.
class WebViewNavigationDelegate: NSObject, WKNavigationDelegate {
    private let allowedDomains = ["youtube.com", "youtubekids.com", "youtu.be", "google.com", "google.co",
                                  "gstatic.com", "ytimg.com", "googlevideo.com", "googleusercontent.com",
                                  "googleapis.com", "accounts.youtube.com"]

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let host = url.host?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        let allowed = allowedDomains.contains { host == $0 || host.hasSuffix("." + $0) || host.contains($0) }
        if !allowed && navigationAction.navigationType == .linkActivated {
            decisionHandler(.cancel)   // stay in the app; external sites are blocked during a session
        } else {
            decisionHandler(.allow)
        }
    }
}

/// target=_blank / window.open → load in the same web view
class WebViewUIDelegate: NSObject, WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

class VideoStateHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any], let playing = dict["playing"] as? Bool else { return }
        NotificationCenter.default.post(name: .videoPlaybackStateChanged, object: nil, userInfo: ["playing": playing])
    }
}

extension Notification.Name {
    static let videoPlaybackStateChanged = Notification.Name("videoPlaybackStateChanged")
}
