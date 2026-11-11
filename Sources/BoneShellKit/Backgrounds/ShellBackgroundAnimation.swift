import UIKit
import ImageIO

private final class ShellBackgroundFrameReader {
    private let descriptor: ShellBackgroundAnimationDescriptor
    private let queue = DispatchQueue(label: "BoneShellKit.animation.frame", qos: .userInitiated)
    private var source: CGImageSource?
    init(_ descriptor: ShellBackgroundAnimationDescriptor) { self.descriptor = descriptor }

    func read(_ index: Int, completion: @escaping (UIImage?) -> Void) {
        queue.async { [self] in
            let image: UIImage? = autoreleasepool {
                if source == nil {
                    source = CGImageSourceCreateWithURL(descriptor.file.url as CFURL,
                                                       [kCGImageSourceShouldCache: false] as CFDictionary)
                }
                guard let source = source,
                      let cg = ShellBackgroundImageIO.thumbnail(source, index: index,
                                                                 bucket: descriptor.pixelBucket) else { return nil }
                // Keep ImageIO's internal frame cache bounded as well as our three-frame NSCache.
                CGImageSourceRemoveCacheAtIndex(source, index)
                return UIImage(cgImage: cg)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }
}

@MainActor
private final class ShellBackgroundDisplayLinkTarget: NSObject {
    weak var owner: ShellBackgroundAnimationPlayer?
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}

@MainActor
final class ShellBackgroundAnimationPlayer {
    private let descriptor: ShellBackgroundAnimationDescriptor
    private let reader: ShellBackgroundFrameReader
    private let frames = NSCache<NSNumber, UIImage>()
    private let target = ShellBackgroundDisplayLinkTarget()
    private var displayLink: CADisplayLink?
    private var elapsed: TimeInterval = 0
    private var lastTimestamp: TimeInterval?
    private var pendingIndex: Int?
    private var desiredIndex = 0
    private let duration: TimeInterval
    private var displayedIndex = 0
    private let onFrame: (UIImage) -> Void
    private let onFailure: (String) -> Void
    private(set) var isRunning = false

    init(descriptor: ShellBackgroundAnimationDescriptor, firstFrame: UIImage,
         onFrame: @escaping (UIImage) -> Void, onFailure: @escaping (String) -> Void) {
        self.descriptor = descriptor
        reader = ShellBackgroundFrameReader(descriptor)
        duration = descriptor.duration
        self.onFrame = onFrame
        self.onFailure = onFailure
        frames.countLimit = 3
        frames.totalCostLimit = 12 * 1024 * 1024
        frames.setObject(firstFrame, forKey: 0, cost: Self.cost(firstFrame))
        target.owner = self
    }

    func play() {
        guard displayLink == nil, duration > 0 else { return }
        lastTimestamp = nil
        let link = CADisplayLink(target: target, selector: #selector(ShellBackgroundDisplayLinkTarget.tick(_:)))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        displayLink = link
        isRunning = true
    }

    func pause() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        isRunning = false
    }

    func clearFrames() { pause(); frames.removeAllObjects() }
    deinit { displayLink?.invalidate() }

    fileprivate func tick(_ link: CADisplayLink) {
        guard isRunning else { return }
        if let lastTimestamp = lastTimestamp {
            elapsed = (elapsed + max(0, link.timestamp - lastTimestamp)).truncatingRemainder(dividingBy: duration)
        }
        lastTimestamp = link.timestamp
        var remaining = elapsed
        var index = descriptor.durations.count - 1
        for (candidate, delay) in descriptor.durations.enumerated() {
            if remaining < delay { index = candidate; break }
            remaining -= delay
        }
        desiredIndex = index
        guard index != displayedIndex else { return }
        if let image = frames.object(forKey: NSNumber(value: index)) {
            displayedIndex = index
            onFrame(image)
        } else if pendingIndex == nil {
            pendingIndex = index
            reader.read(index) { [weak self] image in
                guard let self = self else { return }
                self.pendingIndex = nil
                guard let image = image else {
                    self.pause()
                    self.onFailure("Animation frame \(index) could not be decoded; keeping a still image.")
                    return
                }
                self.frames.setObject(image, forKey: NSNumber(value: index), cost: Self.cost(image))
                if self.isRunning && self.desiredIndex == index {
                    self.displayedIndex = index
                    self.onFrame(image)
                }
            }
        }
    }

    private static func cost(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.width * cg.height * 4
    }
}
