import UIKit

/// 背景资源的定位方式。
public enum ShellBackgroundResource: Equatable, Sendable {
    /// 从资源包中读取指定名称的资源。
    case asset(String, bundle: Bundle)
    /// 从本地文件 URL 读取资源。
    case file(URL)
    /// 从远程 URL 下载资源。
    case remote(URL)

    /// 比较两个背景资源是否指向同一来源。
    /// - Parameters:
    ///   - lhs: 左侧资源。
    ///   - rhs: 右侧资源。
    /// - Returns: 两个资源的来源和资源包是否相同。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.asset(a, ab), .asset(b, bb)): return a == b && ab.isEqual(bb)
        case let (.file(a), .file(b)), let (.remote(a), .remote(b)): return a == b
        default: return false
        }
    }
}

/// 页面背景的内容来源。
public enum ShellBackgroundSource: Equatable {
    /// 不显示背景内容。
    case none
    /// 使用固定颜色。
    case color(UIColor)
    /// 使用静态图片资源。
    case image(ShellBackgroundResource)
    /// 使用动画图片资源。
    case animatedImage(ShellBackgroundResource)
    /// 使用视频 URL。
    case video(URL)
    /// 使用本地 HTML 文件 URL。
    case htmlFile(URL)
    /// 使用 HTML 字符串和可选的相对资源基准 URL。
    case htmlString(String, baseURL: URL?)
    /// 使用 HTTPS HTML 页面 URL。
    case htmlURL(URL)

    /// 当前来源是否需要持续播放或渲染。
    public var isDynamic: Bool {
        switch self {
        case .animatedImage, .video, .htmlFile, .htmlString, .htmlURL: return true
        default: return false
        }
    }

    /// 当前来源是否为空来源。
    public var isEmpty: Bool { if case .none = self { return true }; return false }

    /// 当前来源的简短类型名称，用于状态和诊断。
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

    /// 比较两个背景来源是否相同。
    /// - Parameters:
    ///   - lhs: 左侧背景来源。
    ///   - rhs: 右侧背景来源。
    /// - Returns: 两个来源的类型及内容是否相同。
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

/// 页面背景的完整呈现配置。
@MainActor
public struct ShellBackgroundConfiguration: @preconcurrency Equatable {
    /// 要呈现的背景来源。
    public var source: ShellBackgroundSource
    /// 动态来源加载前或加载失败时显示的静态海报资源。
    public var poster: ShellBackgroundResource?
    /// 覆盖在背景内容之上的颜色。
    public var overlayColor: UIColor
    /// 没有可用背景内容时使用的回退颜色。
    public var fallbackColor: UIColor
    /// 背景图片、视频或 HTML 内容的填充方式。
    public var contentMode: UIView.ContentMode
    /// 静态图片切换时使用的过渡时长，单位为秒。
    public var transitionDuration: TimeInterval

    /// 创建背景配置。
    /// - Parameters:
    ///   - source: 要呈现的背景来源。
    ///   - poster: 动态来源加载前或失败时显示的静态海报资源。
    ///   - overlayColor: 覆盖在背景内容之上的颜色。
    ///   - fallbackColor: 没有可用背景内容时使用的颜色。
    ///   - contentMode: 背景内容的填充方式。
    ///   - transitionDuration: 静态图片切换的过渡时长，单位为秒。
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

    /// 比较两个背景配置是否相同。
    /// - Parameters:
    ///   - lhs: 左侧配置。
    ///   - rhs: 右侧配置。
    /// - Returns: 所有配置项是否相同。
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.source == rhs.source && lhs.poster == rhs.poster &&
        lhs.overlayColor.isEqual(rhs.overlayColor) && lhs.fallbackColor.isEqual(rhs.fallbackColor) &&
        lhs.contentMode == rhs.contentMode && lhs.transitionDuration == rhs.transitionDuration
    }
}

/// 背景视图当前的加载或播放阶段。
public enum ShellBackgroundPhase: String {
    /// 尚未开始加载。
    case idle
    /// 正在加载资源。
    case loading
    /// 资源已经准备好。
    case ready
    /// 资源已暂停播放。
    case paused
    /// 资源加载或播放失败。
    case failed
}

/// 背景视图向宿主报告的状态快照。
public struct ShellBackgroundStatus: Equatable {
    /// 当前背景阶段。
    public let phase: ShellBackgroundPhase
    /// 当前来源的类型名称。
    public let sourceKind: String
    /// 可选的诊断详情或错误信息。
    public let detail: String?
    /// 当前已解码内容的像素尺寸。
    public let pixelSize: CGSize

    init(_ phase: ShellBackgroundPhase, kind: String, detail: String? = nil, pixelSize: CGSize = .zero) {
        self.phase = phase
        self.sourceKind = kind
        self.detail = detail
        self.pixelSize = pixelSize
    }
}

/// 背景图片缓存的运行统计信息。
public struct ShellBackgroundCacheStatistics {
    /// 收到的资源请求总数。
    public let requestCount: Int
    /// 直接命中内存缓存的请求数。
    public let cacheHitCount: Int
    /// 实际执行解码的次数。
    public let decodeCount: Int
    /// 当前正在等待结果的请求数。
    public let inFlightCount: Int
}
