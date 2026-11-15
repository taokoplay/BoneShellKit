# BoneShellKit

UIKit 页面骨架 SDK，当前为 **0.8 验证版**。提供页面内容区域、原生容器封装、栏位模式与样式、标签栏附加动作，以及页面 / 导航 / 标签多媒体背景。

## 构建与运行基线

| 项目 | 当前配置 |
| --- | --- |
| 最低部署目标 | iOS / iPadOS 15 |
| Swift Package | tools version 5.9，Swift 5 语言模式，一个 `BoneShellKit` library 产品 |
| 编译工具链 | 已验证 Xcode 27.1；源码使用 UIKit 26 / 27.1 API，需包含这些声明的编译 SDK，不能据部署目标推断旧 Xcode 可构建 |
| 依赖 | Apple 系统框架，无第三方 Package 依赖 |
| Demo | UIKit Universal App，0.8.0（Build 1），共享 Scheme `BoneShellDemo` |

最低部署目标与实际运行验证分开记录。当前功能回归运行于 iPhone 13 Pro / iOS 26.0 模拟器；旧系统、iPad / Duo 等矩阵的完成情况见 [实现与验证记录](Documentation/Implementation-Status.md)。

## Swift Package 接入

在 Xcode 的 Package Dependencies 中添加本地仓库目录，选择 `BoneShellKit` 产品。宿主 Package 可使用相对路径：

```swift
.package(path: "../BoneShellKit")
```

远程接入本次发布的 0.8 验证版本：

```swift
.package(url: "https://github.com/taokoplay/BoneShellKit.git", exact: "0.8.0")
```

0.8 验证版通过 `v0.8.0` 标签接入；历史标签 `v0.6.0` 不包含后续的自动 / 胶囊模式与标签栏附加动作。需要使用开发分支时可改为 `branch: "main"`，接入范围按该分支实际修订确认。

## 最小接入

页面在 `configureScreen(_:)` 中声明外观与操作，在 `buildContent(in:)` 中一次性构建业务内容。状态变化后调用 `refreshScreenConfiguration()` 更新声明，内容视图和导航栈保持原有实例。

```swift
import UIKit
import BoneShellKit

@MainActor
final class HomeController: BoneViewController {
    private var eventCount = 0
    private let message = UILabel()

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "首页"
        screen.navigation.subtitle = "已触发 \(eventCount) 次"
        screen.navigation.trailingActions = [
            NavigationAction(id: "add", title: "新增", symbol: "plus", priority: 20) { [weak self] in
                guard let self = self else { return }
                self.eventCount += 1
                self.refreshScreenConfiguration()
            }
        ]
    }

    override func buildContent(in contentView: UIView) {
        message.text = "业务内容放在 contentView 中"
        message.numberOfLines = 0
        message.textColor = .label
        message.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(message)
        NSLayoutConstraint.activate([
            message.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            message.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            message.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }
}

@MainActor
final class SettingsController: BoneViewController {
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "设置"
    }
}

@MainActor
func makeRootController() -> BoneTabBarController {
    let tabs = BoneTabBarController(tabs: [
        ShellTab(id: "home", title: "首页", symbol: "house", root: HomeController()),
        ShellTab(id: "settings", title: "设置", symbol: "gearshape", root: SettingsController())
    ])
    tabs.barPresentation = .automatic
    return tabs
}
```

在宿主的 Scene 创建窗口后，将 `makeRootController()` 赋给 `window.rootViewController`。SDK 自动把非导航类型的标签 root 包装为 `BoneNavigationController`；已传入的导航控制器会被复用。需要完整的 SDK 导航模式与容器默认配置时，使用 `BoneNavigationController`。

## 当前能力与默认值

| 能力 | 接口与实际行为 |
| --- | --- |
| 页面内容 | `BoneViewController` + `ScreenConfiguration`；默认 `.safeArea`，`avoidsKeyboard = false`；键盘避让需按页开启 |
| 原生容器 | `BoneNavigationController`、`BoneTabBarController`、`BoneSplitViewController`；分栏的业务选择和数据由宿主管理 |
| 栏位呈现 | `.automatic / .classic / .capsule / .system`；SDK 默认 `.system`，Demo 默认 `.automatic`；导航只有系统与经典两种外观 |
| 导航操作 | SF Symbol 或文字、稳定 ID、整数优先级、禁用状态；SDK 测量可用宽度并通过 `UIMenu` 展示溢出操作 |
| 字体与图标 | 页面 / 容器样式、Dynamic Type、普通 / 选中图标、颜色 / 原图选中策略、按 ID 更新条目 |
| 标签附加动作 | `tabBarAccessories`；经典栏内、兼容胶囊外侧、原生 dock，或显式系统模式的槽位 / 旧系统 tab item |
| 浮动栏下滚动 | 注册主滚动视图后延伸到底边，保留业务 `contentInset`；默认底部 80 pt 渐隐，设为 0 可关闭 |
| 多媒体背景 | 图片、GIF / APNG、MP4、HTML；默认分区，`.unified` 共享完整容器画布 |
| 缓存与播放 | 后台图像解码、尺寸桶、请求合并、预取；每 Scene 默认 1 个动态名额，进程统一上限可设为 0–3 |
| 自有材质 | `ShellGlassView` 选择自动、系统默认、原生玻璃、仿玻璃或实色；原生玻璃不可用时降级 |

原生 dock 的非选中文字颜色受 UIKit 玻璃合成影响，当前不保证指定颜色与最终像素完全一致。其原生滚动收起联动也未作为 SDK 能力提供，详见 [栏位模式与边界](Documentation/Bar-Presentation.md)。

当前没有 App / Scene 全局配置对象、通用 adapter、导航分组 / 加载 / badge 声明、自定义侧栏或 SwiftUI 桥接产品。完整能力清单与后续计划见 [SDK 范围与规划](Documentation/SDK-Plan.md)。

## 运行 Demo 与测试

打开 `Examples/BoneShellDemo/BoneShellDemo.xcodeproj`，选择共享 Scheme `BoneShellDemo`。Demo 通过本地相对路径引用 SDK，内置素材不需要网络或账号。底部有“示例 / 材质 / 关于”；导航栏和标签栏设置位于两个独立页面，完整入口见 [Demo 与测试说明](Documentation/Demo-Test-Plan.md)。

已包含生成后的 Xcode 工程。修改 `project.yml`，或增删 Demo / 测试源文件时，从仓库根目录重新生成：

```sh
xcodegen generate --spec Examples/BoneShellDemo/project.yml --project Examples/BoneShellDemo
```

SDK 的源文件由 Swift Package 自动发现。真机运行需将 `project.yml` 中的 `DEVELOPMENT_TEAM` 换成自己的团队，再生成工程；也可按自己的签名流程配置宿主 App。

设置已启动的模拟器 UDID，并为每次运行建立独立输出目录：

```sh
export BONE_SHELL_SIMULATOR_ID="<SIMULATOR_UDID>"
BONE_SHELL_RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/BoneShellKit.XXXXXX")"

xcodebuild test \
  -project Examples/BoneShellDemo/BoneShellDemo.xcodeproj \
  -scheme BoneShellDemo \
  -destination "platform=iOS Simulator,id=$BONE_SHELL_SIMULATOR_ID" \
  -derivedDataPath "$BONE_SHELL_RUN_DIR/DerivedData" \
  -resultBundlePath "$BONE_SHELL_RUN_DIR/Regression.xcresult" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -collect-test-diagnostics never
```

Scheme 包含 `BoneShellDemoTests` 和 `BoneShellDemoUITests`；前者同时编译 SDK 单元测试与 Demo 集成测试。可用 `-only-testing:BoneShellDemoTests` 或 `-only-testing:BoneShellDemoUITests` 选择范围。当前没有独立的 Smoke / Regression `.xctestplan` 文件。

## 文档导航

- [SDK 当前范围与后续规划](Documentation/SDK-Plan.md)
- [Demo 入口、自动化与待验收矩阵](Documentation/Demo-Test-Plan.md)
- [自动、经典、胶囊与系统栏位](Documentation/Bar-Presentation.md)
- [字体、颜色、图标与运行时更新](Documentation/Bar-Styling.md)
- [多媒体背景、缓存与播放生命周期](Documentation/Backgrounds.md)
- [功能代码基线、执行结果与已知限制](Documentation/Implementation-Status.md)
- [完整设计草案归档](Documentation/Archive/Design-Draft.md) / [0.1–0.6 历史验证记录](Documentation/Archive/Implementation-History.md)
