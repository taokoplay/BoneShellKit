import UIKit
import AVFoundation
import WebKit

@MainActor
final class ShellBackgroundVideoSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

@MainActor
final class ShellBackgroundVideoPlayer {
    let surface = ShellBackgroundVideoSurface()
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var observations: [NSKeyValueObservation] = []
    private var itemObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var wantsPlayback = false
    private let onReady: (CGSize) -> Void
    private let onRunning: (Bool) -> Void
    private let onFailure: (String) -> Void

    init(url: URL, contentMode: UIView.ContentMode, onReady: @escaping (CGSize) -> Void,
         onRunning: @escaping (Bool) -> Void, onFailure: @escaping (String) -> Void) {
        self.onReady = onReady; self.onRunning = onRunning; self.onFailure = onFailure
        surface.isUserInteractionEnabled = false
        surface.backgroundColor = .clear
        surface.playerLayer.videoGravity = contentMode == .scaleAspectFit ? .resizeAspect
            : (contentMode == .scaleToFill ? .resize : .resizeAspectFill)
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 2
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.volume = 0
        queue.preventsDisplaySleepDuringVideoPlayback = false
        queue.actionAtItemEnd = .none
        queue.audiovisualBackgroundPlaybackPolicy = .pauses
        player = queue
        surface.playerLayer.player = queue
        let looper = AVPlayerLooper(player: queue, templateItem: item)
        self.looper = looper
        observations.append(queue.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in self?.observeItem(player.currentItem) }
        })
        observations.append(queue.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.onRunning(self.wantsPlayback && player.timeControlStatus == .playing)
            }
        })
        observations.append(surface.playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            Task { @MainActor in
                guard let self = self, layer.isReadyForDisplay else { return }
                self.onReady(self.player?.currentItem?.presentationSize ?? .zero)
            }
        })
        observations.append(looper.observe(\.status, options: [.initial, .new]) { [weak self] looper, _ in
            Task { @MainActor in
                if looper.status == .failed {
                    self?.onFailure("Video loop failed: \(looper.error?.localizedDescription ?? "unknown error")")
                }
            }
        })
        failureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self = self, let item = notification.object as? AVPlayerItem,
                      self.player?.currentItem === item else { return }
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                self.onFailure("Video playback failed: \(error?.localizedDescription ?? "unknown error")")
            }
        }
    }

    private func observeItem(_ item: AVPlayerItem?) {
        itemObservation = item?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self = self else { return }
                if item.status == .failed {
                    self.onFailure("Video could not load: \(item.error?.localizedDescription ?? "unknown error")")
                } else if item.status == .readyToPlay && self.wantsPlayback {
                    self.player?.play()
                }
            }
        }
    }

    func play() {
        wantsPlayback = true
        surface.playerLayer.player = player
        player?.play()
    }

    func pause() {
        wantsPlayback = false
        player?.pause()
        // Paused AVPlayerLayer retains a still frame without advancing the decoder.
        // stop() detaches it when the configuration changes or memory is reclaimed.
        onRunning(false)
    }

    func stop() {
        pause()
        surface.playerLayer.player = nil
        itemObservation = nil
        observations.removeAll()
        if let token = failureObserver { NotificationCenter.default.removeObserver(token) }
        failureObserver = nil
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        player = nil
        surface.removeFromSuperview()
    }

    deinit { if let token = failureObserver { NotificationCenter.default.removeObserver(token) } }
}

@MainActor
final class ShellBackgroundHTMLRenderer: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private let source: ShellBackgroundSource
    private let allowedFileDirectory: URL?
    private let onReady: () -> Void
    private let onFailure: (String) -> Void
    private var stopped = false

    init(source: ShellBackgroundSource, onReady: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
        self.source = source; self.onReady = onReady; self.onFailure = onFailure
        if case .htmlFile(let url) = source {
            allowedFileDirectory = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        } else if case .htmlString(_, let baseURL) = source, let baseURL = baseURL, baseURL.isFileURL {
            allowedFileDirectory = (baseURL.hasDirectoryPath ? baseURL : baseURL.deletingLastPathComponent())
                .resolvingSymlinksInPath().standardizedFileURL
        } else { allowedFileDirectory = nil }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // No script message handlers, native bridges or persistent website storage.
        let mute = """
        document.addEventListener('play', function(e) {
            if (e.target instanceof HTMLMediaElement) { e.target.muted = true; e.target.volume = 0; }
        }, true);
        """
        configuration.userContentController.addUserScript(
            WKUserScript(source: mute, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isUserInteractionEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
    }

    func load() {
        switch source {
        case .htmlFile(let url):
            guard url.isFileURL, let directory = allowedFileDirectory else {
                onFailure("HTML file source requires a local file URL."); return
            }
            webView.loadFileURL(url, allowingReadAccessTo: directory)
        case .htmlString(let html, let baseURL): webView.loadHTMLString(html, baseURL: baseURL)
        case .htmlURL(let url):
            guard url.scheme?.lowercased() == "https", url.host != nil else {
                onFailure("HTML URL source requires HTTPS."); return
            }
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        default: onFailure("Unsupported HTML background source.")
        }
    }

    func stop() {
        stopped = true
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllUserScripts()
        webView.removeFromSuperview()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if !stopped { onReady() } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if !stopped { onFailure("HTML content process terminated; displaying the poster or fallback color.") }
    }
    private func fail(_ error: Error) {
        if !stopped && (error as NSError).code != NSURLErrorCancelled {
            onFailure("HTML navigation failed: \(error.localizedDescription)")
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !stopped, navigationAction.targetFrame != nil, let url = navigationAction.request.url else {
            decisionHandler(.cancel); return
        }
        if url.isFileURL, let directory = allowedFileDirectory {
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            let root = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
            let allowed = path.hasPrefix(root)
            decisionHandler(allowed ? .allow : .cancel)
            if !allowed && navigationAction.targetFrame?.isMainFrame == true {
                onFailure("HTML file navigation left its authorized directory.")
            }
        } else if url.absoluteString == "about:blank" || url.scheme?.lowercased() == "https" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if navigationAction.targetFrame?.isMainFrame == true {
                onFailure("HTML navigation blocked an unsupported URL scheme.")
            }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) { completionHandler() }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) { completionHandler(false) }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) { completionHandler(nil) }
}
