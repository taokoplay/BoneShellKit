# 栏位类型：系统与经典

`ShellBarPresentation` 将栏位形态与字体、颜色、材质及真实系统版本分开。SDK 默认使用 `.system`；Demo 0.5 默认 `.classic`，可在首页“栏位类型”切换。

| 类型 | 表现 |
| --- | --- |
| `.system` | 使用当前 UIKit 原生栏位。iOS 26+ 采用系统的玻璃 / 浮动表现，旧系统采用其原有导航和标签栏。 |
| `.classic` | 使用 SDK 的经典栏位：平直导航、普通操作按钮、全宽底部标签栏和细分隔线，参考 iOS 26 以前的 UIKit 风格。 |

经典类型是显式的 SDK 呈现方式，不会更改真实系统版本，不使用兼容性 Info.plist 键，也不影响系统菜单、键盘、Sheet 或 SDK 业务内容中的独立材质表面。

## 全局容器设置

```swift
let tabs = BoneTabBarController(tabs: [
    ShellTab(id: "home", title: "首页", symbol: "house", root: HomeController()),
    ShellTab(id: "settings", title: "设置", symbol: "gearshape", root: SettingsController())
])
tabs.barPresentation = .classic

// 随时恢复当前系统原生类型。
tabs.barPresentation = .system
```

标签容器中的 `BoneNavigationController` 默认继承标签容器的类型。单独使用导航容器时：

```swift
let navigation = BoneNavigationController(rootViewController: HomeController())
navigation.barPresentation = .classic
```

`navigation.barPresentation = nil` 表示继承包含它的 Bone 标签容器；没有该容器时使用 `.system`。显式为某个导航设置 `.system` 可以只让该导航采用系统类型。

## 页面覆盖

```swift
override func configureScreen(_ screen: inout ScreenConfiguration) {
    screen.barPresentation = .classic
    screen.navigation.title = "经典页面"
}
```

页面值同时覆盖当前管理的导航与标签栏。设为 `nil` 恢复容器继承；更新页面状态后调用 `refreshScreenConfiguration()`。`resolvedBarPresentation` 可读取当前页面、导航或标签容器实际选用的类型。

类型切换更新已有容器的呈现，不替换标签控制器、导航栈和页面内容。经典按钮继续执行原有 `NavigationAction`，更多操作使用原有 UIMenu；返回按钮仍调用原生 pop。导航原生手势的 delegate 不被替换。

## 字体、图标与背景

[字体、颜色与图标](Bar-Styling.md) 的配置继续有效：普通 / 大标题 / 副标题、导航文字按钮、标签普通 / 选中态，以及本地图片和选中图标均可设置。经典标签栏显示 badge；超过五个目的地时显示“更多”入口，不无限压缩所有按钮。

经典类型不创建 UIGlassEffect。普通栏位使用 UIBlurEffect 的 systemMaterial 表面；导航的 `.solid` 与减少透明度采用实色。没有悬浮胶囊和共享按钮玻璃底。业务内容里的 ShellGlassView 仍由自己的材质配置控制。

已有 [独立与整体背景](Backgrounds.md) 不变：栏位有媒体或页面启用 `.unified` 时，经典栏位的底色和分隔线透出背景，保留同一整体画布和媒体实例。类型切换不会主动重建整体背景。

## 布局、安全区域与状态

经典导航沿用原生 UINavigationController 的栏位布局区域，隐藏原生前景并显示 SDK 控件，保留原生容器与返回路径。大标题随原生可用栏位高度展示或收起。 SDK 为当前经典导航补充必要的页面顶部安全区，并在切回系统类型时移除自身贡献；业务内容仍使用 contentView / safe area，无需自行计算导航高度。

经典标签固定在容器底部，宽度覆盖整个容器；内容高度至少 49 pt，并按字体行高调整，额外覆盖底部系统安全区域。iOS 18+ 通过公开的 setTabBarHidden API 停用原生标签呈现，并只为经典内容增加必要的安全区贡献；切回系统时移除这部分贡献、恢复原生显示。旧版使用原有栏位占位。不要另外给业务内容重复增加相同的底栏高度。

`hidesBottomBarWhenPushed` 仍表示详情页不显示底部栏位。`classicNavigationBarView` 与 `classicTabBarView` 是可选的只读 UIView 诊断入口；它们不提供业务内容容器，也不应被宿主重新布局。原生 `isTabBarHidden` 描述的是原生标签栏，经典类型下原生栏位可能隐藏而经典栏位可见。

切换回系统类型会恢复 SDK 修改过的原生 alpha、可访问性状态和自身安全区贡献。使用自己额外的 safe area inset 时，由宿主管理自身贡献，不应把 SDK 的贡献再次累加。

在 iOS 27.1 的经典类型中，页面明确选择横向栏位；系统类型继续使用系统轴向适配。Duo 的完整姿态、分栏与键盘矩阵仍需对应设备验收，不能把新 SDK 编译检查视为设备测试。

## Demo 与验收

首页“栏位类型”可以切换系统 / 经典，开启整体背景并进入输入详情。详情导航中提供类型切换，便于对照输入内容和返回状态。Demo 默认经典；已有系统类型 UI 回归使用 `-system-bars` 启动参数，新经典用例使用默认配置，均不伪造 OS 能力。

实际构建、测试、截图和手机安装结果见 [验证记录](Implementation-Status.md)。这里描述的是经典风格，不承诺与某一具体旧版系统逐像素一致。
