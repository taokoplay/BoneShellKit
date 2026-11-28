# BoneShellKit

UIKit 页面骨架 SDK。提供页面内容区域、原生容器封装、栏位模式与样式、标签栏附加动作，以及页面 / 导航 / 标签多媒体背景。

最新版本 **v0.14.4** 修复只有右侧操作时兼容导航栏的标题宽度分配。v0.14.3 开始支持自定义标题随文字或字体变化自动调整宽度。版本变化见 [更新记录](CHANGELOG.md)。

[导航动作与自适应](Documentation/Navigation-Actions.md) 包含导航动作、NavButton、系统共享玻璃、自定义按钮承载、标题视图和兼容策略。NavButton 等扩展自 v0.11.0 提供，导航动作强制显示自 v0.12.0 提供，v0.12.1 补充 iOS 26 返回恢复和自定义 confirmation 行为，v0.14.0 将轴向偏好改为模块级 `sidebarBehavior` 并统一玻璃绘制。

## 构建与运行基线

| 项目 | 当前配置 |
| --- | --- |
| 最低部署目标 | iOS / iPadOS 15 |
| Swift Package | tools version 5.9，Swift 5 语言模式，一个 `BoneShellKit` library 产品 |
| 编译工具链 | 已验证 Xcode 27.1；源码使用 UIKit 26 / 27.1 API，需包含这些声明的编译 SDK，不能据部署目标推断旧 Xcode 可构建 |
| 依赖 | Apple 系统框架，无第三方 Package 依赖 |
| Demo | UIKit Universal App，0.14.0（Build 1），共享 Scheme `BoneShellDemo` |

最低部署目标与实际运行验证分开记录。导航动作已在 iPhone Duo / iOS 27.1 与 iPhone 16 Pro / iOS 18.6 模拟器执行相关回归；此前 iOS 26 的功能验证独立保留，完整系统 / 姿态矩阵见 [实现与验证记录](Documentation/Implementation-Status.md)。

## Swift Package 接入

在 Xcode 的 Package Dependencies 中添加本地仓库目录，选择 `BoneShellKit` 产品。宿主 Package 可使用相对路径：

```swift
.package(path: "../BoneShellKit")
```

通过 SwiftPM 锁定 `v0.14.4`。

```swift
.package(url: "https://github.com/taokoplay/BoneShellKit.git", exact: "0.14.4")
```

按精确标签锁定所需能力：`v0.14.0` 包含模块级侧栏策略、统一的玻璃绘制、Duo 侧栏整组竖排，以及此前的 NavButton、导航标题视图和标签栏整项自定义视图；`v0.12.1` 包含 iOS 26 导航共享玻璃修复与 NavButton 返回恢复；更早版本能力见对应发布说明。分支接入的可用功能以实际修订为准，不能将默认分支等同于发布标签。

## 最小接入

重写两个方法即可接入页面：`configureScreen(_:)` 设置外观，`buildContent(in:)` 添加业务视图。

```swift
import UIKit
import BoneShellKit

@MainActor
final class HomeController: BoneViewController {
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "首页"     // 导航标题
        screen.content = .safeArea            // 内容放在安全区内
        screen.avoidsKeyboard = true          // 开启键盘避让，默认关闭
    }

    override func buildContent(in contentView: UIView) {
        // 在 contentView 中添加业务视图。
    }
}

@MainActor
func makeRootController() -> BoneNavigationController {
    BoneNavigationController(rootViewController: HomeController())
}
```

在宿主 Scene 创建窗口后，将 `makeRootController()` 赋给 `window.rootViewController`。页面状态变化后调用 `refreshScreenConfiguration()`，只更新配置，保留业务视图与导航栈。

## SDK 方法与可设置字段

- [SDK 方法说明](Documentation/Usage-Examples.md)：按类型列出创建方法、可调用 / 可重写的方法，以及参数、返回值和中文用途。
- [可设置字段与中文说明](Documentation/API-Reference.md)：逐项列出页面、导航、标签、背景、材质等字段的类型、默认值和中文含义。

继承、覆盖和恢复默认值的区别见 [设置生效规则](Documentation/API-Reference.md#设置生效规则)。

## 当前能力与默认值

| 能力 | 接口与实际行为 |
| --- | --- |
| 页面内容 | `BoneViewController` + `ScreenConfiguration`；默认 `.safeArea`，`avoidsKeyboard = false`；键盘避让需按页开启 |
| 原生容器 | `BoneNavigationController`、`BoneTabBarController`、`BoneSplitViewController`；分栏的业务选择和数据由宿主管理 |
| 栏位呈现 | `.automatic / .classic / .capsule / .system`；SDK 默认 `.system`，Demo 默认 `.automatic`；导航只有系统与经典两种外观 |
| 导航操作 | 图片 / SF Symbol / 文字、稳定 ID、角色、整数优先级、自动或强制显示、禁用状态及按钮组级侧栏策略；iOS 27+ 使用系统布局，经典与旧系统保留 SDK 宽度预算 |
| 字体与图标 | 页面 / 容器样式、Dynamic Type、普通 / 选中图标、颜色 / 原图选中策略、按 ID 更新条目 |
| 普通标签自定义视图 | 开发版 `ShellTabItemConfiguration.customContent` 接收整项 `UIView`；可与标准图文混用。见[接入说明](Documentation/Bar-Presentation.md#普通标签的自定义视图) |
| 标签附加动作 | `tabBarAccessories`；开发版支持 [自定义整项内容](Documentation/Bar-Presentation.md#自定义附加按钮)，不改变当前选中标签 |
| 浮动栏下滚动 | 注册主滚动视图后延伸到底边，保留业务 `contentInset`；默认底部 80 pt 渐隐，设为 0 可关闭 |
| 多媒体背景 | 图片、GIF / APNG、MP4、HTML；默认分区，`.unified` 共享完整容器画布 |
| 缓存与播放 | 后台图像解码、尺寸桶、请求合并、预取；每 Scene 默认 1 个动态名额，进程统一上限可设为 0–3 |
| 自有材质 | `ShellGlassView` 选择自动、系统默认、原生玻璃、仿玻璃或实色；原生玻璃不可用时降级 |

原生 dock 的非选中文字颜色受 UIKit 玻璃合成影响，当前不保证指定颜色与最终像素完全一致。其原生滚动收起联动也未作为 SDK 能力提供，详见 [栏位模式与边界](Documentation/Bar-Presentation.md)。

### 标签文字显示（v0.9.0+）

以下 API **自 v0.9.0 提供，v0.8.0 不包含**，运行与视觉结果见 [验证记录](Documentation/Implementation-Status.md#090-标签文字显示策略与验证)。`ShellTabLabelDisplayMode` 支持：

| 模式 | 可见文字 |
| --- | --- |
| `.always` | 始终显示，默认值 |
| `.never` | 始终隐藏 |
| `.selectedOnly` | 仅选中项显示 |
| `.unselectedOnly` | 仅未选中项显示 |

```swift
tabs.tabBarStyle.labelDisplayMode = .selectedOnly

if var item = tabs.tabItemConfiguration(for: "home") {
    item.labelDisplayMode = .never  // 单独隐藏首页文字
    tabs.updateTabItem(id: "home", configuration: item)
}
```

整栏通过 `tabs.tabBarStyle` 设置，页面的 `screen.tabBarStyle` 仍为整份覆盖；单个条目的 `ShellTabItemConfiguration.labelDisplayMode` 默认 `nil`，继承当前生效样式，设回 `nil` 即恢复继承。两种 `ShellTab` 初始化器也可在 `root:` 前传入该可选参数。隐藏时保留配置中的语义标题和无障碍名称，并让图标居中；原生“更多”按钮跟随整栏策略，溢出列表中的目的地名称保留。完整规则见 [样式说明](Documentation/Bar-Styling.md#标签文字显示策略)。

当前没有 App / Scene 全局配置对象、通用 adapter、导航分组 / 加载 / badge 声明、自定义侧栏或 SwiftUI 桥接产品。完整能力清单与后续计划见 [SDK 范围与规划](Documentation/SDK-Plan.md)。

## 运行 Demo 与测试

打开 `Examples/BoneShellDemo/BoneShellDemo.xcodeproj`，选择共享 Scheme `BoneShellDemo`。Demo 通过本地相对路径引用 SDK，不需要网络或账号。「标签栏」页可启用「自定义标签视图」，也可单独体验胶囊右侧的动态附加按钮。完整入口见 [Demo 与测试说明](Documentation/Demo-Test-Plan.md)。

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

- [SDK 方法说明](Documentation/Usage-Examples.md)
- [可设置字段与中文说明](Documentation/API-Reference.md)
- [源码结构说明](Documentation/Source-Layout.md)
- [版本更新记录](CHANGELOG.md)
- [SDK 当前范围与后续规划](Documentation/SDK-Plan.md)
- [Demo 入口、自动化与待验收矩阵](Documentation/Demo-Test-Plan.md)
- [导航动作与自适应栏位（v0.14.4）](Documentation/Navigation-Actions.md)
- [自动、经典、胶囊与系统栏位](Documentation/Bar-Presentation.md)
- [字体、颜色、图标与运行时更新](Documentation/Bar-Styling.md)
- [多媒体背景、缓存与播放生命周期](Documentation/Backgrounds.md)
- [功能代码基线、执行结果与已知限制](Documentation/Implementation-Status.md)
- [完整设计草案归档](Documentation/Archive/Design-Draft.md) / [0.1–0.6 历史验证记录](Documentation/Archive/Implementation-History.md)
