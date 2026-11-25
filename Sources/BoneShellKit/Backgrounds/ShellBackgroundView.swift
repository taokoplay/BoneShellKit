import UIKit
import AVFoundation

/// 非交互式媒体背景视图。宿主应在自身可见性生命周期中控制播放。
@MainActor
public final class ShellBackgroundView: UIView {
    /// 当前应用的背景配置，只读反映最近一次 `apply` 结果。
    public private(set) var configuration: ShellBackgroundConfiguration?
    /// 当前背景加载或播放状态。
    public private(set) var status = ShellBackgroundStatus(.idle, kind: "none")
    /// 状态发生变化时调用的回调。
    public var onStatusChange: ((ShellBackgroundStatus) -> Void)?
    /// 播放预算分配时使用的优先级；数值越大越优先获得播放资格。
    public var playbackPriority: Int = 0 { didSet { ShellBackgroundPlaybackBudget.rebalance() } }
    /// 当前是否正在播放动态背景。
    public private(set) var isPlaybackRunning = false

    private let posterView = UIImageView()
    private let imageView = UIImageView()
    private let overlayView = UIView()
    private var generation: UInt64 = 0
    private var imageVersion: UInt64 = 0
    private var posterVersion: UInt64 = 0
    private var videoVersion: UInt64 = 0
    private var htmlVersion: UInt64 = 0
    private var imageSignature: String?
    private var posterSignature: String?
    private var primaryImage: ShellBackgroundPreparedImage?
    private var posterImage: ShellBackgroundPreparedImage?
    private var primaryComplete = false
    private var failure: String?
    private var posterFailure: String?
    private var playbackActive = false
    private var budgetGranted = false
    private var pauseReason: String?
    private var memorySuspended = false
    private var animation: ShellBackgroundAnimationPlayer?
    private var video: ShellBackgroundVideoPlayer?
    private var html: ShellBackgroundHTMLRenderer?
    private var videoReady = false
    private var htmlReady = false
    private var videoPixels: CGSize = .zero
    private var videoPosterGenerator: AVAssetImageGenerator?
    private var videoPosterAttempted = false
    private var videoPosterVersion: UInt64 = 0

    /// 创建指定 frame 的背景视图。
    /// - Parameter frame: 视图的初始 frame。
    public override init(frame: CGRect = .zero) { super.init(frame: frame); initialize() }

    /// 从归档恢复背景视图。
    /// - Parameter coder: 用于解码视图的归档对象。
    public required init?(coder: NSCoder) { super.init(coder: coder); initialize() }
    deinit { videoPosterGenerator?.cancelAllCGImageGeneration() }

    private func initialize() {
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        for view in [posterView, imageView, overlayView] {
            view.isUserInteractionEnabled = false
            view.clipsToBounds = true
            addSubview(view)
        }
        ShellBackgroundPlaybackBudget.register(self)
    }

    /// 视图隐藏状态变化时重新计算动态背景播放预算。
    public override var isHidden: Bool { didSet { ShellBackgroundPlaybackBudget.rebalance() } }
    /// 视图透明度变化时重新计算动态背景播放预算。
    public override var alpha: CGFloat { didSet { ShellBackgroundPlaybackBudget.rebalance() } }

    /// 按当前边界布局背景内容并重新计算播放资格。
    public override func layoutSubviews() {
        super.layoutSubviews()
        posterView.frame = bounds
        imageView.frame = bounds
        overlayView.frame = bounds
        video?.surface.frame = bounds
        html?.webView.frame = bounds
        refreshImagesIfNeeded()
        ShellBackgroundPlaybackBudget.rebalance()
    }

    /// 视图进入窗口时刷新资源和播放资格。
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshImagesIfNeeded()
        ShellBackgroundPlaybackBudget.rebalance()
    }

    /// 视图进入或离开父视图时重新计算播放资格。
    public override func didMoveToSuperview() {
        super.didMoveToSuperview()
        ShellBackgroundPlaybackBudget.rebalance()
    }

    /// 特征环境变化时刷新图片资源和播放资格。
    /// - Parameter previousTraitCollection: 变化前的特征环境。
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshImagesIfNeeded()
        ShellBackgroundPlaybackBudget.rebalance()
    }

    /// 应用新的背景配置；传入 nil 会停止并释放当前背景资源。
    /// - Parameter configuration: 要应用的背景配置；为空时清除背景。
    public func apply(_ configuration: ShellBackgroundConfiguration?) {
        guard let configuration = configuration else { stopAndRelease(); return }
        if self.configuration == configuration {
            refreshImagesIfNeeded()
            ShellBackgroundPlaybackBudget.rebalance()
            return
        }
        generation &+= 1
        releaseMedia()
        self.configuration = configuration
        imageSignature = nil; posterSignature = nil
        imageVersion &+= 1; posterVersion &+= 1
        primaryImage = nil; posterImage = nil
        primaryComplete = false
        failure = nil; posterFailure = nil
        memorySuspended = false; budgetGranted = false; pauseReason = nil
        videoReady = false; htmlReady = false; videoPixels = .zero
        videoPosterAttempted = false
        posterView.image = nil; imageView.image = nil; imageView.backgroundColor = .clear
        backgroundColor = configuration.fallbackColor
        overlayView.backgroundColor = configuration.overlayColor
        posterView.contentMode = configuration.contentMode
        imageView.contentMode = configuration.contentMode
        switch configuration.source {
        case .color(let color): imageView.backgroundColor = color; primaryComplete = true
        case .none: primaryComplete = true
        case .video(let url):
            if !url.isFileURL && !["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                failure = "Video requires a local file or HTTP(S) URL."
            }
        case .htmlFile(let url):
            if !url.isFileURL { failure = "HTML file source requires a local file URL." }
        case .htmlURL(let url):
            if url.scheme?.lowercased() != "https" || url.host == nil { failure = "HTML URL source requires HTTPS." }
        default: break
        }
        refreshImagesIfNeeded()
        updateStatus()
        ShellBackgroundPlaybackBudget.rebalance()
    }

    /// 设置宿主是否希望动态背景播放。
    /// - Parameter active: 为 true 时请求播放，为 false 时请求暂停。
    public func setPlaybackActive(_ active: Bool) {
        let changed = playbackActive != active
        playbackActive = active
        if active {
            memorySuspended = false
            if changed, let source = configuration?.source {
                switch source {
                case .video(let url) where url.isFileURL || ["http", "https"].contains(url.scheme?.lowercased() ?? ""):
                    failure = nil
                case .htmlFile(let url) where url.isFileURL: failure = nil
                case .htmlURL(let url) where url.scheme?.lowercased() == "https" && url.host != nil: failure = nil
                case .htmlString: failure = nil
                default: break
                }
            }
        }
        ShellBackgroundPlaybackBudget.rebalance()
    }

    /// 清除配置并释放该视图拥有的全部媒体资源；重新应用配置后可以继续复用视图。
    public func stopAndRelease() {
        generation &+= 1
        configuration = nil
        playbackActive = false; budgetGranted = false
        releaseMedia()
        primaryImage = nil; posterImage = nil
        imageView.image = nil; posterView.image = nil
        imageView.backgroundColor = .clear; overlayView.backgroundColor = .clear
        backgroundColor = .clear
        imageSignature = nil; posterSignature = nil
        failure = nil; posterFailure = nil
        isPlaybackRunning = false
        publish(ShellBackgroundStatus(.idle, kind: "none"))
        ShellBackgroundPlaybackBudget.rebalance()
    }

    private var renderScale: CGFloat {
        let scale = window?.screen.scale ?? traitCollection.displayScale
        return scale > 0 ? scale : UIScreen.main.scale
    }

    private func signature(animated: Bool) -> String {
        "\(ShellBackgroundCache.pixelBucket(targetSize: bounds.size, scale: renderScale, animated: animated))|"
            + ShellBackgroundCache.appearanceKey(traitCollection)
    }

    private func refreshImagesIfNeeded() {
        guard let configuration = configuration, bounds.width > 0, bounds.height > 0 else { return }
        let currentGeneration = generation
        if let poster = configuration.poster {
            let key = signature(animated: false)
            if posterSignature != key {
                posterSignature = key
                posterVersion &+= 1
                let version = posterVersion
                ShellBackgroundCache.load(poster, targetSize: bounds.size, scale: renderScale,
                                          traits: traitCollection, animated: false) { [weak self] result in
                    guard let self = self, self.generation == currentGeneration, self.posterVersion == version else { return }
                    switch result {
                    case .success(let prepared):
                        self.posterImage = prepared
                        self.posterView.image = prepared.image
                        self.posterFailure = nil
                    case .failure(let error): self.posterFailure = "Poster failed: \(error.localizedDescription)"
                    }
                    self.updateStatus()
                }
            }
        }
        let resource: ShellBackgroundResource
        let animated: Bool
        switch configuration.source {
        case .image(let image): resource = image; animated = false
        case .animatedImage(let image): resource = image; animated = true
        default: return
        }
        let key = signature(animated: animated)
        guard imageSignature != key else { return }
        imageSignature = key
        imageVersion &+= 1
        let version = imageVersion
        animation?.pause(); animation = nil
        if animated { isPlaybackRunning = false }
        primaryComplete = false
        failure = nil
        ShellBackgroundCache.load(resource, targetSize: bounds.size, scale: renderScale,
                                  traits: traitCollection, animated: animated) { [weak self] result in
            guard let self = self, self.generation == currentGeneration, self.imageVersion == version else { return }
            self.primaryComplete = true
            switch result {
            case .success(let prepared):
                self.primaryImage = prepared
                self.showImage(prepared.image)
                if let descriptor = prepared.animation {
                    self.animation = ShellBackgroundAnimationPlayer(
                        descriptor: descriptor, firstFrame: prepared.image,
                        onFrame: { [weak self] image in
                            guard let self = self, self.generation == currentGeneration,
                                  self.imageVersion == version, self.budgetGranted else { return }
                            self.imageView.image = image
                        }, onFailure: { [weak self] detail in
                            guard let self = self, self.generation == currentGeneration,
                                  self.imageVersion == version else { return }
                            self.failMedia(detail)
                        })
                }
            case .failure(let error): self.failure = "Image failed: \(error.localizedDescription)"
            }
            self.updateStatus()
            ShellBackgroundPlaybackBudget.rebalance()
        }
        updateStatus()
    }

    private func showImage(_ image: UIImage) {
        let requested = configuration?.transitionDuration ?? 0
        let duration = requested.isFinite ? min(2, max(0, requested)) : 0
        if duration > 0 && window != nil && !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: imageView, duration: duration,
                              options: [.transitionCrossDissolve, .allowAnimatedContent, .beginFromCurrentState]) {
                self.imageView.image = image
            }
        } else { imageView.image = image }
    }

    var backgroundRequestsPlayback: Bool { playbackActive && configuration?.source.isDynamic == true }

    private var visibleInForeground: Bool {
        guard let window = window, !bounds.isEmpty, !window.isHidden, window.alpha > 0.01,
              UIApplication.shared.applicationState == .active else { return false }
        if let scene = window.windowScene, scene.activationState != .foregroundActive { return false }
        var ancestor: UIView? = self
        while let view = ancestor {
            if view.isHidden || view.alpha <= 0.01 { return false }
            ancestor = view.superview
        }
        return convert(bounds, to: window).intersects(window.bounds)
    }

    var backgroundPlaybackBlockReason: String? {
        if let failure = failure { return failure }
        if !playbackActive { return "Playback is inactive." }
        if !visibleInForeground { return "Background is outside a visible foreground window." }
        if memorySuspended { return "Media released after memory warning; reactivate to resume." }
        if UIAccessibility.isReduceMotionEnabled { return "Reduce Motion: displaying a static background." }
        if UIAccessibility.isReduceTransparencyEnabled { return "Reduce Transparency: displaying a static background." }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return "Low Power Mode: displaying a static background." }
        if case .animatedImage = configuration?.source, primaryComplete, primaryImage?.animation == nil {
            return primaryImage?.diagnostic ?? "Animation is unavailable; displaying a still image."
        }
        return nil
    }

    func backgroundSetBudgetGranted(_ granted: Bool, reason: String?) {
        guard let configuration = configuration, configuration.source.isDynamic else { return }
        let wasGranted = budgetGranted
        budgetGranted = granted
        pauseReason = reason
        if !granted {
            animation?.pause()
            if wasGranted { video?.pause() }
            // Keep an already decoded video frame only when no configured poster exists.
            video?.surface.isHidden = configuration.poster != nil || !videoReady
            if html != nil { releaseHTML() }
            isPlaybackRunning = false
            if playbackActive && visibleInForeground { prepareLocalVideoStillIfNeeded() }
            else { cancelVideoPoster() }
            updateStatus()
            return
        }
        switch configuration.source {
        case .animatedImage:
            restoreAnimationIfNeeded()
            animation?.play()
            isPlaybackRunning = animation?.isRunning == true
        case .video(let url):
            prepareLocalVideoStillIfNeeded()
            if video == nil { createVideo(url: url) }
            video?.surface.isHidden = !videoReady
            video?.play()
        case .htmlFile, .htmlString, .htmlURL:
            if html == nil { createHTML(source: configuration.source) }
        default: break
        }
        updateStatus()
    }

    private func createVideo(url: URL) {
        let token = generation
        videoVersion &+= 1
        let version = videoVersion
        let renderer = ShellBackgroundVideoPlayer(
            url: url, contentMode: configuration?.contentMode ?? .scaleAspectFill,
            onReady: { [weak self] size in
                guard let self = self, self.generation == token, self.videoVersion == version else { return }
                self.videoReady = true
                self.videoPixels = size
                self.video?.surface.isHidden = !self.budgetGranted && self.configuration?.poster != nil
                self.updateStatus()
            }, onRunning: { [weak self] running in
                guard let self = self, self.generation == token, self.videoVersion == version else { return }
                self.isPlaybackRunning = running && self.budgetGranted
                self.updateStatus()
            }, onFailure: { [weak self] detail in
                guard let self = self, self.generation == token, self.videoVersion == version else { return }
                self.failMedia(detail)
            })
        video = renderer
        renderer.surface.frame = bounds
        renderer.surface.isHidden = true
        insertSubview(renderer.surface, belowSubview: overlayView)
    }

    private func createHTML(source: ShellBackgroundSource) {
        let token = generation
        htmlVersion &+= 1
        let version = htmlVersion
        htmlReady = false
        let renderer = ShellBackgroundHTMLRenderer(source: source, onReady: { [weak self] in
            guard let self = self, self.generation == token, self.htmlVersion == version,
                  self.budgetGranted else { return }
            self.htmlReady = true
            self.html?.webView.isHidden = false
            self.updateStatus()
        }, onFailure: { [weak self] detail in
            guard let self = self, self.generation == token, self.htmlVersion == version else { return }
            self.failMedia(detail)
        })
        html = renderer
        renderer.webView.frame = bounds
        renderer.webView.isHidden = true
        insertSubview(renderer.webView, belowSubview: overlayView)
        isPlaybackRunning = true // The content process may execute JavaScript as soon as loading starts.
        renderer.load()
    }

    private func prepareLocalVideoStillIfNeeded() {
        guard !memorySuspended, failure == nil, !videoPosterAttempted, configuration?.poster == nil,
              case .video(let url) = configuration?.source, url.isFileURL else { return }
        videoPosterAttempted = true
        let token = generation
        videoPosterVersion &+= 1
        let version = videoPosterVersion
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        videoPosterGenerator = generator
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { [weak self] _, image, _, result, error in
            Task { @MainActor in
                guard let self = self, self.generation == token, self.videoPosterVersion == version,
                      self.videoPosterGenerator != nil else { return }
                self.videoPosterGenerator = nil
                if result == .succeeded, let image = image {
                    self.posterView.image = UIImage(cgImage: image)
                } else if result != .cancelled {
                    self.posterFailure = "Video still unavailable: \(error?.localizedDescription ?? "no first frame")"
                }
                self.updateStatus()
            }
        }
    }

    private func cancelVideoPoster() {
        guard let generator = videoPosterGenerator else { return }
        videoPosterVersion &+= 1
        generator.cancelAllCGImageGeneration()
        videoPosterGenerator = nil
        videoPosterAttempted = false
    }

    private func failMedia(_ detail: String) {
        failure = detail
        releaseMedia()
        isPlaybackRunning = false
        updateStatus()
        ShellBackgroundPlaybackBudget.rebalance()
    }

    private func releaseHTML() {
        htmlVersion &+= 1
        html?.stop(); html = nil
        htmlReady = false
    }

    private func releaseMedia() {
        animation?.pause(); animation = nil
        videoVersion &+= 1
        video?.stop(); video = nil
        releaseHTML()
        cancelVideoPoster()
        isPlaybackRunning = false
    }

    func backgroundReleaseForMemoryPressure() {
        guard configuration?.source.isDynamic == true else { return }
        memorySuspended = true
        budgetGranted = false
        releaseMedia()
        if let first = primaryImage?.image { imageView.image = first }
        videoReady = false; videoPosterAttempted = false
        // Preserve the source and its still image, but release the frame reader and all live media.
        updateStatus()
    }

    func backgroundResumeAfterActivation() {
        memorySuspended = false
        restoreAnimationIfNeeded()
    }

    private func restoreAnimationIfNeeded() {
        guard animation == nil, let prepared = primaryImage, let descriptor = prepared.animation,
              failure == nil else { return }
        let token = generation
        animation = ShellBackgroundAnimationPlayer(descriptor: descriptor, firstFrame: prepared.image,
            onFrame: { [weak self] image in
                guard let self = self, self.generation == token, self.budgetGranted else { return }
                self.imageView.image = image
            }, onFailure: { [weak self] detail in
                guard let self = self, self.generation == token else { return }
                self.failMedia(detail)
            })
    }

    private func updateStatus() {
        guard let configuration = configuration else { publish(ShellBackgroundStatus(.idle, kind: "none")); return }
        let kind = configuration.source.kindName
        let pixels: CGSize
        if videoReady && videoPixels != .zero { pixels = videoPixels }
        else if htmlReady { pixels = CGSize(width: bounds.width * renderScale, height: bounds.height * renderScale) }
        else if let prepared = primaryImage ?? posterImage { pixels = prepared.pixelSize }
        else if let still = posterView.image?.cgImage { pixels = CGSize(width: still.width, height: still.height) }
        else { pixels = .zero }
        if configuration.source.isEmpty { publish(ShellBackgroundStatus(.idle, kind: kind)); return }
        if let failure = failure {
            publish(ShellBackgroundStatus(.failed, kind: kind, detail: failure, pixelSize: pixels)); return
        }
        if configuration.source.isDynamic {
            if case .animatedImage = configuration.source, primaryComplete, primaryImage?.animation == nil {
                publish(ShellBackgroundStatus(.ready, kind: kind, detail: primaryImage?.diagnostic, pixelSize: pixels)); return
            }
            if !budgetGranted {
                let reason = pauseReason ?? backgroundPlaybackBlockReason ?? "Waiting for playback budget."
                let detail = [reason, posterFailure].compactMap { $0 }.joined(separator: " ")
                publish(ShellBackgroundStatus(.paused, kind: kind, detail: detail, pixelSize: pixels)); return
            }
            let ready: Bool
            switch configuration.source {
            case .animatedImage: ready = primaryComplete
            case .video: ready = videoReady
            default: ready = htmlReady
            }
            var detail = primaryImage?.diagnostic
            if case .video(let url) = configuration.source, !url.isFileURL {
                detail = "Remote video streams without a complete offline disk cache."
            }
            publish(ShellBackgroundStatus(ready ? .ready : .loading, kind: kind, detail: detail, pixelSize: pixels))
        } else {
            publish(ShellBackgroundStatus(primaryComplete ? .ready : .loading, kind: kind,
                                          detail: primaryImage?.diagnostic, pixelSize: pixels))
        }
    }

    private func publish(_ next: ShellBackgroundStatus) {
        guard next != status else { return }
        status = next
        onStatusChange?(next)
    }
}
