# BoneShellKit 0.4 多媒体背景

页面、导航栏、标签栏分别使用 `ShellBackgroundConfiguration`，支持图片、GIF / APNG、MP4 和 HTML。三处可以选择不同资源，也可以复用同一份配置；背景不接收触摸，导航、返回、标签和业务输入仍由原生 UIKit 控件处理。

## 整体背景与分区背景

需要导航栏、页面和标签栏连成一幅画面时，使用整体模式：

```swift
override func configureScreen(_ screen: inout ScreenConfiguration) {
    screen.backgroundComposition = .unified
    screen.background = ShellBackgroundConfiguration(
        source: .video(videoURL),
        poster: .asset("BackgroundPoster", bundle: .main)
    )
}
```

整体模式只创建一个完整容器尺寸的 `ShellBackgroundView`。图片、GIF / APNG、MP4 与 HTML 均只绘制一次，导航和标签透出这同一画布，使用相同坐标、裁切与播放时间。无需再给导航和标签重复配置资源；它们的独立背景和容器媒体默认值在整体模式下暂时停用，文字、按钮、图标与原生导航行为保留。

优先使用当前 `BoneTabBarController` 的完整画布；无该容器时使用 `BoneNavigationController`，独立页面则使用自身视图。画布跟随实际容器 bounds 调整，不缓存固定屏幕尺寸。多 Scene 与独立容器分别拥有画布，不跨窗口共享播放器。

相同配置的整体页面 push / pop 时复用画布和媒体实例，转场中保留可见的共享背景；不为每页重新启动播放器或创建 WKWebView。切到普通页面、退出整体模式或容器消失时停止相应播放，并恢复 SDK 调整过的透明表面。应用切后台、低电量、减少动态效果等策略仍由媒体引擎处理。

整体背景只占一个动态播放名额，即使 `maximumActivePerScene = 3`，同一画布也不会变成三个播放器。可通过 `page.activeBackgroundView` 获取实际画布状态；`page.backgroundView` 继续指独立页面背景，在整体模式下不承载媒体。

SDK 默认 `backgroundComposition = .independent`，保留原有三处独立配置。把同一份资源分别赋给三处配置仍代表三个独立画面，时间和裁切不保证一致；需要整体效果应显式使用 `.unified`。整体模式需要非空的 `screen.background`；未提供媒体时沿用原有页面 / 容器默认处理。

Demo 默认“全部”启用整体模式，另设“分区”用于三处独立呈现及预算对照。业务内容中不透明的卡片或自定义视图会正常覆盖背景；系统玻璃前景可以改变局部光学效果，但不会创建额外媒体时间线。

## 页面接入

```swift
import UIKit
import BoneShellKit

final class GalleryController: BoneViewController {
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "Gallery"

        screen.background = ShellBackgroundConfiguration(
            source: .image(.asset("PagePaper", bundle: .main)),
            overlayColor: UIColor.black.withAlphaComponent(0.15)
        )
        screen.navigation.background = ShellBackgroundConfiguration(
            source: .animatedImage(.asset("NavigationGlow.gif", bundle: .main)),
            poster: .asset("NavigationPoster", bundle: .main)
        )
        if let video = Bundle.main.url(forResource: "TabDrift", withExtension: "mp4") {
            screen.tabBarBackground = ShellBackgroundConfiguration(
                source: .video(video),
                poster: .asset("TabPoster", bundle: .main)
            )
        }
    }

    override func buildContent(in contentView: UIView) {
        // 在 contentView 中创建业务内容，不需要计算导航栏或标签栏高度。
    }
}
```

使用 `BoneNavigationController` 和 `BoneTabBarController` 承载页面时，SDK 自动将栏位背景应用到对应容器。页面背景铺满页面视图，业务内容默认仍位于安全区域。业务视图若使用不透明底色，会遮住其下方的页面背景；需要透出背景的区域自行使用透明色。

页面配置变化后调用 `refreshScreenConfiguration()`，业务内容不会被重新创建。

## 资源类型

| 类型 | 声明方式 | 行为 |
| --- | --- | --- |
| 纯色 | `.color(UIColor)` | 不占动态播放名额 |
| 图片 | `.image(.asset("Paper", bundle: .main))`、`.image(.file(url))`、`.image(.remote(httpsURL))` | 异步准备静态图 |
| GIF / APNG | `.animatedImage(.file(url))`；也支持 bundle 文件及 HTTPS 资源 | 首帧先显示，获得播放名额后按帧播放 |
| MP4 | `.video(url)` | 本地文件或 HTTP(S) URL，静音循环，优先使用所配海报 |
| 本地 HTML | `.htmlFile(url)` | 可访问同目录资源，离屏释放网页 |
| HTML 字符串 | `.htmlString(html, baseURL: url)` | 支持 CSS / JavaScript 动效，相对资源按 baseURL 解析 |
| 远程 HTML | `.htmlURL(httpsURL)` | 仅 HTTPS，按需加载，离屏释放 |
| 清除栏位背景 | `ShellBackgroundConfiguration(source: .none)` | 显式覆盖容器默认背景 |

动图应使用原始 GIF / APNG 文件。Assets.car 中的图片通过静态栅格处理；将动图放入图片资产目录不保证保留动画。MP4 的实际编码支持范围以系统 AVFoundation 为准，Demo 使用本地 H.264 MP4。

远程图片和 HTML 要求 HTTPS；MP4 的网络访问仍受宿主 App 的 ATS 配置约束。远程 MP4 与 HTML 不提供完整离线缓存。远程图片使用内存缓存及临时下载文件，不提供长期离线资源管理或 HTTP 更新校验；需要长期缓存或版本管理时，宿主可先下载为自己的文件，再使用 `.file` / `.video` / `.htmlFile`。

## 独立配置与默认值

```swift
let navigation = BoneNavigationController(rootViewController: GalleryController())
navigation.backgroundConfiguration = ShellBackgroundConfiguration(
    source: .image(.asset("DefaultNavigation", bundle: .main))
)

let tabs = BoneTabBarController(tabs: [
    ShellTab(id: "gallery", title: "Gallery", symbol: "photo", root: navigation)
])
tabs.backgroundConfiguration = ShellBackgroundConfiguration(
    source: .color(.secondarySystemBackground)
)
```

| 页面字段 | `nil` | 显式 `.none` |
| --- | --- | --- |
| `screen.background` | 移除页面背景层的配置 | 无媒体内容；底色和遮罩仍由配置决定，彻底移除使用 `nil` |
| `screen.navigation.background` | 继承导航容器的 `backgroundConfiguration` | 关闭本页的导航媒体背景，恢复页面材质策略 |
| `screen.tabBarBackground` | 继承标签容器的 `backgroundConfiguration` | 关闭本页的标签媒体背景，恢复原始 Appearance |

媒体背景启用时，对原生栏位使用公开的透明 Appearance，让媒体可见。系统按钮、返回手势和标签选择仍保留原生行为。这里的背景与 `ShellMaterial` 分别配置；透明栏位背景不代表关闭所有系统按钮的原生玻璃。浮动栏位的具体边界、裁切和系统玻璃表现由运行系统决定。

## 切页与加载性能

- 图片文件读取、文件版本查询、ImageIO 缩略解码在后台进行；最多两个图片准备任务并发。主线程只更新 UIKit 视图与状态。
- 按实际目标大小和显示比例计算像素尺寸，以 128 像素分桶；静态图最长边最多 2048 像素，动图最多 1024 像素。极大窗口不加载原始全分辨率背景。源图片限制为 64 MP，动图限制为 16 MP；图片文件 / 下载大小最多 32 MB。
- 相同资源、尺寸桶和外观条件的并发请求合并；内存缓存使用文件版本区分本地文件，并区分深浅色等 traits。同一背景配置重复应用、桶内尺寸变化不会重新发起解码。
- 解码图的共享 `NSCache` 默认成本限制为 48 MB，最多 96 项。这是系统管理的软限制，不是整个背景功能的进程内存上限；可见图片、动图帧、AVPlayer、WKWebView 有各自占用。
- 动图最多读取 600 帧的时间信息，播放时按需解码，不一次创建完整帧数组；每个播放器的帧缓存最多 3 帧、成本限制 12 MB。超限动图保留首帧并返回诊断原因。
- 导航 push / pop 尝试预取目标页的图片和海报。预取不提前创建 MP4 播放器或 WKWebView；返回已有页面可复用已准备的图片和缓存。
- 图片异步结果带配置与请求版本检查；快速切换后，旧结果不能覆盖新配置。旧的可复用解码任务可以完成并写入缓存。
- 页面转场前先准备静态表示，`viewDidAppear` 后申请动态播放；页面离开时撤销申请。原生返回完成或取消后按当前页面恢复。
- 收到内存警告时清理共享图片缓存、取消待完成的缓存请求，并释放动态媒体。动态媒体在重新激活后恢复，不在内存警告后立即反复重建。

宿主已知即将打开的页面时，也可以主动预取：

```swift
ShellBackgroundCache.prefetch(
    configuration,
    targetSize: view.bounds.size,
    scale: view.window?.screen.scale ?? traitCollection.displayScale,
    traits: traitCollection
)
```

尺寸应接近目标区域；导航、标签和整页的尺寸不同，可能使用不同的缓存桶。布局扩大跨桶后会重新准备合适尺寸的缩略图。

## 动态播放预算与生命周期

```swift
// 默认 1；取值会限制到 0...3。0 表示全部使用静态表示。
ShellBackgroundPlaybackBudget.maximumActivePerScene = 1
let running = ShellBackgroundPlaybackBudget.activeCount(in: view.window?.windowScene)
```

播放预算按 `UIWindowScene` 分配，配置上限为进程统一值。默认优先级为页面 30、导航 20、标签 10；同优先级按登记顺序选择。先暂停失去名额的背景，再启动新背景。默认三个区域都是动态资源时，页面播放，其他两处显示海报或静态帧；设置为 3 可让三处同时播放。

仅前台可见、宿主已激活的背景可以申请播放。无窗口、离屏、隐藏、低透明度或 App / Scene 不活跃时暂停；共享的 4 Hz 检查补充处理祖先视图的隐藏与透明度变化。系统“减少动态效果”“减少透明度”或低电量模式开启时使用静态表示。

GIF 保留静态帧并暂停显示链；MP4 暂停推进，可保留播放器及静态画面以便返回恢复，切换资源或内存回收时释放。MP4 静音循环，不修改全局音频会话，不阻止显示器自动休眠。未配置海报的本地视频会异步尝试提取首帧；远程视频应明确提供海报。

HTML 只有在可见且获得播放名额后才创建和加载 `WKWebView`，失去名额或离屏即停止并释放，不建立隐藏网页池。回到页面后重新加载，因此动态 HTML 的内部状态不承诺跨切页保留。HTML 应提供海报，避免受限状态只显示回退色。

HTML 使用非持久网站数据存储，不注册原生桥接，不响应触摸、不弹窗；媒体要求用户动作，播放事件进一步静音。复杂脚本、Canvas / WebGL 仍有独立的 CPU / GPU 和 WebKit 进程成本，应由资源作者控制。骨架 SDK 的播放预算不能替代具体 HTML 内容的性能优化。

## 状态、回退与缓存控制

`ShellBackgroundView` 提供只读 `configuration`、`status`、`isPlaybackRunning`，以及 `onStatusChange` 回调。状态包括 `idle`、`loading`、`ready`、`paused`、`failed`；`detail` 给出暂停、降级或失败原因，`pixelSize` 提供已准备图像的尺寸。

配置中的 `poster`、`fallbackColor`、`overlayColor` 和 `contentMode` 分别控制海报、加载或失败底色、遮罩和裁切。`transitionDuration` 默认 0.15 秒，图片切换在减少动态效果时移除淡入淡出。`ready` 表示媒体准备状态，不是视觉正确性或帧率的验收证明。

`ShellBackgroundCache.statistics` 提供 `requestCount`、`cacheHitCount`、`decodeCount` 和 `inFlightCount`。使用 `resetStatistics()` 重置计数，使用 `removeAll()` 清缓存并取消缓存请求；清缓存不会移除视图正在显示的图片。要重新加载同 URL 的已显示资源，应明确切换配置或重建该资源的呈现，而非只看计数变化。

SDK 的 UI、配置、缓存和播放预算入口使用 `@MainActor`。宿主直接使用 `ShellBackgroundView` 时，应自行调用 `apply(_:)`、`setPlaybackActive(_:)` 管理生命周期；`stopAndRelease()` 同时清除配置和所有媒体。

## Demo 与验证范围

Demo 首页“背景与切页”提供图片 / 动图 / MP4 / HTML、页面 / 导航 / 标签 / 全部 / 分区、1–3 个动态播放名额、预加载与清缓存切页、连续切换 8 次，以及实时媒体和缓存诊断。

自动化覆盖缓存合并 / 命中 / 清理、文件与外观变化、损坏资源、过期加载结果、尺寸桶复用、首帧预取、离屏 HTML、弱引用释放、三处配置、页面内容实例保留、返回恢复、标签切换暂停、MP4 / HTML 和播放名额调整。实际执行环境、测试数量及真机交付见 [实现与验证记录](Implementation-Status.md)。

当前策略旨在限制后台工作、解码尺寸和同时播放数量；未经过 Instruments 的 FPS、峰值内存与耗电测试，不宣称所有资源都能达到特定帧率。旧版 OS、iPad / Duo 全部姿态和多 Scene 的完整设备矩阵仍需按 [测试规划](Demo-Test-Plan.md) 验收。
