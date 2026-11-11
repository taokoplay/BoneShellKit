import UIKit
import ImageIO

// File ownership travels with an animation descriptor so a downloaded GIF remains available
// for lazy frame reads, then disappears when the cache and its last view release it.
final class ShellBackgroundImageFile: @unchecked Sendable {
    let url: URL
    private let temporary: Bool
    init(_ url: URL, temporary: Bool = false) { self.url = url; self.temporary = temporary }
    deinit { if temporary { try? FileManager.default.removeItem(at: url) } }
}

struct ShellBackgroundAnimationDescriptor: Sendable {
    let file: ShellBackgroundImageFile
    let durations: [TimeInterval]
    let pixelBucket: Int
    var duration: TimeInterval { durations.reduce(0, +) }
}

final class ShellBackgroundPreparedImage: NSObject, @unchecked Sendable {
    let image: UIImage
    let animation: ShellBackgroundAnimationDescriptor?
    let diagnostic: String?
    var pixelSize: CGSize {
        guard let cg = image.cgImage else { return .zero }
        return CGSize(width: cg.width, height: cg.height)
    }
    var cost: Int { Int(pixelSize.width) * Int(pixelSize.height) * 4 }
    init(_ image: UIImage, animation: ShellBackgroundAnimationDescriptor? = nil, diagnostic: String? = nil) {
        self.image = image; self.animation = animation; self.diagnostic = diagnostic
    }
}

struct ShellBackgroundImageError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

@MainActor
public enum ShellBackgroundCache {
    public static var memoryCostLimit: Int = 48 * 1024 * 1024 {
        didSet {
            storage.totalCostLimit = max(0, memoryCostLimit)
            if memoryCostLimit <= 0 { storage.removeAllObjects() }
        }
    }
    public static var statistics: ShellBackgroundCacheStatistics {
        ShellBackgroundCacheStatistics(requestCount: requests, cacheHitCount: hits,
                                       decodeCount: decodes, inFlightCount: jobs.count)
    }

    private static let storage: NSCache<NSString, ShellBackgroundPreparedImage> = {
        let cache = NSCache<NSString, ShellBackgroundPreparedImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        cache.countLimit = 96
        return cache
    }()
    private static var requests = 0
    private static var hits = 0
    private static var decodes = 0
    private static var jobs: [String: Job] = [:]
    private static let worker: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "BoneShellKit.image.prepare"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    private static var memoryObserver: NSObjectProtocol?
    typealias Completion = (Result<ShellBackgroundPreparedImage, Error>) -> Void

    @MainActor private final class Job {
        var completions: [Completion]
        var download: ShellBackgroundImageDownload?
        init(_ completion: @escaping Completion) { completions = [completion] }
    }

    public static func prefetch(_ configuration: ShellBackgroundConfiguration, targetSize: CGSize,
                                scale: CGFloat, traits: UITraitCollection? = nil) {
        switch configuration.source {
        case .image(let resource):
            load(resource, targetSize: targetSize, scale: scale, traits: traits, animated: false) { _ in }
        case .animatedImage(let resource):
            load(resource, targetSize: targetSize, scale: scale, traits: traits, animated: true) { _ in }
        default: break
        }
        if let poster = configuration.poster {
            load(poster, targetSize: targetSize, scale: scale, traits: traits, animated: false) { _ in }
        }
    }

    /// Cancels pending requests and prevents their eventual worker results from repopulating the cache.
    public static func removeAll() {
        storage.removeAllObjects()
        let cancelled = Array(jobs.values)
        jobs.removeAll()
        for job in cancelled {
            job.download?.cancel()
            job.download = nil
            for completion in job.completions {
                completion(.failure(ShellBackgroundImageError("Image request cancelled after cache reset.")))
            }
            job.completions.removeAll()
        }
    }

    public static func resetStatistics() { requests = 0; hits = 0; decodes = 0 }

    static func pixelBucket(targetSize: CGSize, scale: CGFloat, animated: Bool) -> Int {
        let limit = animated ? 1024 : 2048
        let raw = max(targetSize.width, targetSize.height) * (scale.isFinite ? max(1, scale) : 1)
        guard raw.isFinite else { return limit }
        return min(limit, max(128, Int(ceil(min(CGFloat(limit), max(1, raw)) / 128)) * 128))
    }

    static func appearanceKey(_ traits: UITraitCollection?) -> String {
        guard let traits = traits else { return "default" }
        return "\(traits.userInterfaceStyle.rawValue):\(traits.accessibilityContrast.rawValue):\(traits.displayGamut.rawValue):\(traits.legibilityWeight.rawValue)"
    }

    static func load(_ resource: ShellBackgroundResource, targetSize: CGSize, scale: CGFloat,
                     traits: UITraitCollection?, animated: Bool, completion: @escaping Completion) {
        if memoryObserver == nil {
            memoryObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
            ) { _ in Task { @MainActor in ShellBackgroundCache.removeAll() } }
        }
        requests += 1
        let traits = traits ?? UIScreen.main.traitCollection
        let bucket = pixelBucket(targetSize: targetSize, scale: scale, animated: animated)
        let key = identity(resource) + "|\(bucket)|\(animated)|" + appearanceKey(traits)
        if let job = jobs[key] { job.completions.append(completion); return }
        let job = Job(completion)
        jobs[key] = job
        // Resolve file metadata off the main thread before consulting the memory cache.
        worker.addOperation {
            let resolved = Result { try ShellBackgroundImageIO.resolve(resource, traits: traits) }
            Task { @MainActor in
                guard jobs[key] === job else { return }
                switch resolved {
                case .failure(let error): finish(key, job: job, result: .failure(error))
                case .success(let location):
                    let cacheKey = key + "|" + location.version
                    if let image = storage.object(forKey: cacheKey as NSString) {
                        hits += job.completions.count
                        finish(key, job: job, result: .success(image))
                    } else {
                        prepare(location, bucket: bucket, animated: animated, key: key,
                                cacheKey: cacheKey, job: job)
                    }
                }
            }
        }
    }

    private static func identity(_ resource: ShellBackgroundResource) -> String {
        switch resource {
        case .asset(let name, let bundle): return "asset:\(bundle.bundleURL.absoluteString):\(name)"
        case .file(let url): return "file:\(url.standardizedFileURL.absoluteString)"
        case .remote(let url): return "remote:\(url.absoluteString)"
        }
    }

    private static func prepare(_ location: ShellBackgroundImageIO.Location, bucket: Int, animated: Bool,
                                key: String, cacheKey: String, job: Job) {
        if case .remote(let url) = location.payload {
            let download = ShellBackgroundImageDownload(url: url) { [weak job] result in
                Task { @MainActor in
                    guard let job = job, jobs[key] === job else { return }
                    job.download = nil
                    switch result {
                    case .failure(let error): finish(key, job: job, result: .failure(error))
                    case .success(let file):
                        decode(.file(file), bucket: bucket, animated: animated,
                               key: key, cacheKey: cacheKey, job: job)
                    }
                }
            }
            job.download = download
            download.start()
        } else {
            decode(location.payload, bucket: bucket, animated: animated, key: key, cacheKey: cacheKey, job: job)
        }
    }

    private static func decode(_ payload: ShellBackgroundImageIO.Payload, bucket: Int, animated: Bool,
                               key: String, cacheKey: String, job: Job) {
        decodes += 1
        worker.addOperation {
            let result = autoreleasepool {
                Result { try ShellBackgroundImageIO.decode(payload, bucket: bucket, animated: animated) }
            }
            Task { @MainActor in
                guard jobs[key] === job else { return }
                if case .success(let image) = result, memoryCostLimit > 0 {
                    storage.setObject(image, forKey: cacheKey as NSString, cost: image.cost)
                }
                finish(key, job: job, result: result)
            }
        }
    }

    private static func finish(_ key: String, job: Job, result: Result<ShellBackgroundPreparedImage, Error>) {
        guard jobs[key] === job else { return }
        jobs.removeValue(forKey: key)
        let callbacks = job.completions
        job.completions.removeAll()
        for completion in callbacks { completion(result) }
    }
}

// This namespace is deliberately nonisolated: file IO, ImageIO and raster scaling only run on workers.
enum ShellBackgroundImageIO {
    static let maximumFileBytes: Int64 = 32 * 1024 * 1024
    enum Payload: Sendable {
        case file(ShellBackgroundImageFile)
        case catalog(String, Bundle, UITraitCollection?)
        case remote(URL)
    }
    struct Location: Sendable { let payload: Payload; let version: String }

    static func resolve(_ resource: ShellBackgroundResource, traits: UITraitCollection?) throws -> Location {
        switch resource {
        case .file(let url): return try local(url)
        case .remote(let url):
            guard url.scheme?.lowercased() == "https", url.host != nil else {
                throw ShellBackgroundImageError("Remote images require an HTTPS URL.")
            }
            return Location(payload: .remote(url), version: "remote")
        case .asset(let name, let bundle):
            if let url = bundle.url(forResource: name, withExtension: nil) { return try local(url) }
            if (name as NSString).pathExtension.isEmpty {
                for ext in ["png", "jpg", "jpeg", "gif", "apng", "heic", "webp"] {
                    if let url = bundle.url(forResource: name, withExtension: ext) { return try local(url) }
                }
            }
            return Location(payload: .catalog(name, bundle, traits), version: "catalog")
        }
    }

    private static func local(_ url: URL) throws -> Location {
        guard url.isFileURL else { throw ShellBackgroundImageError("Expected a local file URL.") }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw ShellBackgroundImageError("Image resource is not a regular file.")
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, size <= maximumFileBytes else {
            throw ShellBackgroundImageError("Image file is empty or exceeds the 32 MB limit.")
        }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return Location(payload: .file(ShellBackgroundImageFile(url)), version: "\(modified):\(size)")
    }

    static func decode(_ payload: Payload, bucket: Int, animated: Bool) throws -> ShellBackgroundPreparedImage {
        switch payload {
        case .remote: throw ShellBackgroundImageError("Image download has not finished.")
        case let .catalog(name, bundle, traits):
            guard let image = UIImage(named: name, in: bundle, compatibleWith: traits),
                  let cg = image.cgImage else {
                throw ShellBackgroundImageError("Image asset '\(name)' was not found or cannot be rasterized.")
            }
            // ImageIO cannot open Assets.car. Scale its CGImage with a bounded CoreGraphics context.
            let ratio = min(1, CGFloat(bucket) / CGFloat(max(cg.width, cg.height)))
            let width = max(1, Int(CGFloat(cg.width) * ratio))
            let height = max(1, Int(CGFloat(cg.height) * ratio))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw ShellBackgroundImageError("Cannot allocate image thumbnail.")
            }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let scaled = context.makeImage() else { throw ShellBackgroundImageError("Cannot scale asset.") }
            return ShellBackgroundPreparedImage(UIImage(cgImage: scaled), diagnostic: animated
                ? "Asset catalog image is static; use a GIF/APNG file for animation." : nil)
        case .file(let file):
            guard let source = CGImageSourceCreateWithURL(file.url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(source) > 0 else {
                throw ShellBackgroundImageError("ImageIO could not open the image (unsupported or damaged file).")
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
            let width = (properties?[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue ?? 0
            let height = (properties?[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue ?? 0
            let maximumPixels: Double = animated ? 16_000_000 : 64_000_000
            guard width > 0, height > 0, width * height <= maximumPixels else {
                throw ShellBackgroundImageError("Invalid dimensions or image exceeds the \(Int(maximumPixels / 1_000_000)) megapixel source limit.")
            }
            guard let first = thumbnail(source, index: 0, bucket: bucket) else {
                throw ShellBackgroundImageError("ImageIO could not decode the first frame.")
            }
            let count = CGImageSourceGetCount(source)
            guard animated, count > 1 else {
                return ShellBackgroundPreparedImage(UIImage(cgImage: first), diagnostic: animated
                    ? "Resource contains one frame; displaying a static image." : nil)
            }
            guard count <= 600 else {
                return ShellBackgroundPreparedImage(UIImage(cgImage: first), diagnostic:
                    "Animation has \(count) frames; showing its first frame (limit 600).")
            }
            let durations = (0..<count).map { index -> TimeInterval in
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
                let gif = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
                let png = properties?[kCGImagePropertyPNGDictionary as String] as? [String: Any]
                let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? NSNumber)?.doubleValue
                    ?? (gif?[kCGImagePropertyGIFDelayTime as String] as? NSNumber)?.doubleValue
                    ?? (png?[kCGImagePropertyAPNGUnclampedDelayTime as String] as? NSNumber)?.doubleValue
                    ?? (png?[kCGImagePropertyAPNGDelayTime as String] as? NSNumber)?.doubleValue ?? 0.1
                // Preserve short frame delays; the 30 Hz clock skips frames instead of slowing the timeline.
                return delay.isFinite && delay > 0 ? delay : 0.1
            }
            let totalDuration = durations.reduce(0, +)
            guard totalDuration.isFinite, totalDuration > 0 else {
                return ShellBackgroundPreparedImage(UIImage(cgImage: first), diagnostic:
                    "Animation has invalid timing; displaying its first frame.")
            }
            return ShellBackgroundPreparedImage(UIImage(cgImage: first), animation:
                ShellBackgroundAnimationDescriptor(file: file, durations: durations, pixelBucket: bucket))
        }
    }

    static func thumbnail(_ source: CGImageSource, index: Int, bucket: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: bucket
        ] as CFDictionary)
    }
}

/// Downloads to a temporary file, cancels at the byte limit, and never constructs a whole-file Data.
final class ShellBackgroundImageDownload: NSObject, URLSessionDownloadDelegate {
    private let url: URL
    private let completion: (Result<ShellBackgroundImageFile, Error>) -> Void
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private let lock = NSLock()
    private var completed = false

    init(url: URL, completion: @escaping (Result<ShellBackgroundImageFile, Error>) -> Void) {
        self.url = url; self.completion = completion
    }

    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.downloadTask(with: url)
        lock.lock()
        guard !completed else { lock.unlock(); session.invalidateAndCancel(); return }
        self.session = session
        self.task = task
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock()
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > ShellBackgroundImageIO.maximumFileBytes ||
            totalBytesExpectedToWrite > ShellBackgroundImageIO.maximumFileBytes {
            finish(.failure(ShellBackgroundImageError("Remote image exceeds the 32 MB download limit.")))
            downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode), response.url?.scheme?.lowercased() == "https" else {
                throw ShellBackgroundImageError("Image server returned an invalid response or an insecure redirect.")
            }
            let size = (try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0, size <= ShellBackgroundImageIO.maximumFileBytes else {
                throw ShellBackgroundImageError("Downloaded image is empty or exceeds 32 MB.")
            }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("boneshell-image-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(ShellBackgroundImageFile(destination, temporary: true)))
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme?.lowercased() == "https" else {
            completionHandler(nil)
            finish(.failure(ShellBackgroundImageError("Image redirect must use HTTPS.")))
            return
        }
        completionHandler(request)
    }

    private func finish(_ result: Result<ShellBackgroundImageFile, Error>) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        let session = session
        self.session = nil
        task = nil
        lock.unlock()
        completion(result)
        session?.finishTasksAndInvalidate()
    }
}
