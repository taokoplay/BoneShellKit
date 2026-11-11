# BoneShellKit

原生 UIKit 自适应页面骨架。当前为 **0.6 验证版**，最低部署目标 iOS 15，使用 Xcode 27.1 构建。

## Swift Package 接入

在 Xcode 的 Package Dependencies 中添加 `https://github.com/taokoplay/BoneShellKit`，选择 `main` 分支；或在宿主 Package 中声明：

```swift
.package(url: "https://github.com/taokoplay/BoneShellKit.git", branch: "main")
```

选择 `BoneShellKit` 产品并 `import BoneShellKit`。当前以分支提供验证版本，尚未发布语义版本标签。

## 运行 Demo

打开 `Examples/BoneShellDemo/BoneShellDemo.xcodeproj`，选择共享 Scheme `BoneShellDemo`，选择模拟器或自己的手机运行。Demo 通过相对路径引用本地 Swift Package，无需远程服务。

Demo 提供导航与多按钮、栏位字体 / 颜色 / 图标、图片 / 动图 / MP4 / HTML 背景与切页、实时窗口 / 安全区、表单与键盘、标签导航栈保留、系统 sheet、列表详情分栏和玻璃材质对照。底部“材质”可切换自动、原生玻璃、仿玻璃及实色。

## 当前实现

- `BoneViewController` 管理内容区域和页面配置；页面覆盖 `configureScreen` 与 `buildContent`。
- `BoneNavigationController`、`BoneTabBarController`、`BoneSplitViewController` 封装系统容器。
- `ShellBarPresentation.system / .classic` 切换系统与 iOS 26 以下风格的平直栏位。经典类型提供普通导航按钮和全宽底部标签，保留原生容器、页面与导航状态；Demo 默认经典。
- `NavigationAction` 描述图标或文字操作；按实际字体测量，空间不足时按优先级进入更多菜单。
- `ShellNavigationStyle` / `ShellTabBarStyle` 配置导航标题、大标题、副标题、按钮和标签普通 / 选中态的字体与颜色，支持 Dynamic Type、页面覆盖和恢复。
- 标签图标支持 SF Symbol、bundle 图片和 UIImage，普通 / 选中态可分别提供；按稳定 ID 更新条目时保留导航栈与输入。
- `ShellTabSelectedIconMode` 选择选中颜色或原色选中图片，保留普通图标轮廓或指定选中图案，兼容系统与经典类型；默认自动模式保留原有行为。
- `ShellGlassView` 管理 SDK 自有材质表面：iOS 26+ 使用公开原生玻璃，旧版本使用公开模糊材质，减少透明度时降级为实色。
- 页面、导航栏、标签栏分别配置 `ShellBackgroundConfiguration`，支持图片、GIF / APNG、MP4 和 HTML，以及海报、遮罩、加载 / 失败回退。
- 整体模式用一个完整容器画布贯穿导航、页面和标签，统一播放与裁切；同资源切页复用媒体。Demo 的“全部”为整体，“分区”为三个独立区域。
- 图片后台缩略解码、尺寸桶缓存、重复请求合并与切页预取；动态背景按可见性运行，每个 Scene 默认一个播放名额，可调至三个，HTML 离屏释放。
- XCTest 覆盖解析规则、背景缓存 / 生命周期与 Demo 集成；XCUITest 覆盖媒体切换、独立栏位、播放预算、返回、标签状态、材质及 sheet。

本版提供系统与经典导航 / 标签呈现；完整 adapter、其他栏位扩展及全部设备 / 系统矩阵仍属后续范围。栏位类型和自有材质表面分别配置，系统菜单与键盘继续由 UIKit 管理。

## 重新生成工程与测试

已包含生成后的 Xcode 工程。只有改动工程规格时，才需要安装 XcodeGen 并从本项目根目录运行：

```sh
xcodegen generate --spec Examples/BoneShellDemo/project.yml --project Examples/BoneShellDemo
```

测试前设置自己的模拟器 UDID 与临时构建目录，再从项目根目录运行：

```sh
xcodebuild \
  -project Examples/BoneShellDemo/BoneShellDemo.xcodeproj \
  -scheme BoneShellDemo \
  -destination "platform=iOS Simulator,id=$BONE_SHELL_SIMULATOR_ID" \
  -derivedDataPath "$BONE_SHELL_BUILD_DIR" \
  test
```

Demo 测试目标同时包含本地 SDK 的单元测试源与 Demo 集成测试。真机签名团队在工程配置中设置，其他开发者需替换为自己的 Development Team。

## 文档

- [SDK 规划](Documentation/SDK-Plan.md)
- [Demo 与测试规划](Documentation/Demo-Test-Plan.md)
- [多媒体背景接入与性能策略](Documentation/Backgrounds.md)
- [栏位字体、颜色与标签图标](Documentation/Bar-Styling.md)
- [系统与经典栏位类型](Documentation/Bar-Presentation.md)

最新的测试数量、截图核对和手机安装状态见 [实现与验证记录](Documentation/Implementation-Status.md)。最低部署目标不代表全部旧版 OS / iPad / Duo 姿态已经实测；FPS、峰值内存与耗电尚未进行 Instruments 测量。
