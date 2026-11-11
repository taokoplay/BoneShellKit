import UIKit

public enum ShellBackgroundResource: Equatable, Sendable {
    case asset(String, bundle: Bundle)
    case file(URL)
    case remote(URL)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.asset(a, ab), .asset(b, bb)): return a == b && ab.isEqual(bb)
        case let (.file(a), .file(b)), let (.remote(a), .remote(b)): return a == b
        default: return false
        }
    }
}

public enum ShellBackgroundSource: Equatable {
    case none
    case color(UIColor)
    case image(ShellBackgroundResource)
    case animatedImage(ShellBackgroundResource)
    case video(URL)
    case htmlFile(URL)
    case htmlString(String, baseURL: URL?)
    case htmlURL(URL)

    public var isDynamic: Bool {
        switch self {
        case .animatedImage, .video, .htmlFile, .htmlString, .htmlURL: return true
        default: return false
        }
    }

    public var isEmpty: Bool { if case .none = self { return true }; return false }

    public var kindName: String {
        switch self {
        case .none: return "none"
        case .color: return "color"
        case .image: return "image"
        case .animatedImage: return "animatedImage"
        case .video: return "video"
        case .htmlFile, .htmlString, .htmlURL: return "html"
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.color(a), .color(b)): return a.isEqual(b)
        case let (.image(a), .image(b)), let (.animatedImage(a), .animatedImage(b)): return a == b
        case let (.video(a), .video(b)), let (.htmlFile(a), .htmlFile(b)),
             let (.htmlURL(a), .htmlURL(b)): return a == b
        case let (.htmlString(a, au), .htmlString(b, bu)): return a == b && au == bu
        default: return false
        }
    }
}

@MainActor
public struct ShellBackgroundConfiguration: @preconcurrency Equatable {
    public var source: ShellBackgroundSource
    public var poster: ShellBackgroundResource?
    public var overlayColor: UIColor
    public var fallbackColor: UIColor
    public var contentMode: UIView.ContentMode
    public var transitionDuration: TimeInterval

    public init(
        source: ShellBackgroundSource,
        poster: ShellBackgroundResource? = nil,
        overlayColor: UIColor = .clear,
        fallbackColor: UIColor = .systemBackground,
        contentMode: UIView.ContentMode = .scaleAspectFill,
        transitionDuration: TimeInterval = 0.15
    ) {
        self.source = source
        self.poster = poster
        self.overlayColor = overlayColor
        self.fallbackColor = fallbackColor
        self.contentMode = contentMode
        self.transitionDuration = transitionDuration
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source && lhs.poster == rhs.poster &&
        lhs.overlayColor.isEqual(rhs.overlayColor) && lhs.fallbackColor.isEqual(rhs.fallbackColor) &&
        lhs.contentMode == rhs.contentMode && lhs.transitionDuration == rhs.transitionDuration
    }
}

public enum ShellBackgroundPhase: String {
    case idle, loading, ready, paused, failed
}

public struct ShellBackgroundStatus: Equatable {
    public let phase: ShellBackgroundPhase
    public let sourceKind: String
    public let detail: String?
    public let pixelSize: CGSize

    init(_ phase: ShellBackgroundPhase, kind: String, detail: String? = nil, pixelSize: CGSize = .zero) {
        self.phase = phase
        self.sourceKind = kind
        self.detail = detail
        self.pixelSize = pixelSize
    }
}

public struct ShellBackgroundCacheStatistics {
    public let requestCount: Int
    public let cacheHitCount: Int
    public let decodeCount: Int
    public let inFlightCount: Int
}
