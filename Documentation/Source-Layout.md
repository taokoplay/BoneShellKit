# BoneShellKit 源码结构

本文说明当前工作树的源码分区和拆分边界。它描述实现文件的组织方式，不改变公开类型名称、模块导入方式或宿主接入方式。

## Swift Package 入口

`Package.swift` 继续只声明一个 `BoneShellKit` library target 和一个测试 target。SwiftPM 会自动发现 `Sources/BoneShellKit/` 下各级目录中的 Swift 文件，因此新增 `Containers/` 和 `Navigation/` 不需要修改 Package manifest，也不会改变 `import BoneShellKit`。

最低部署目标仍为 iOS 15，源码使用 Swift 5 语言模式；系统 API 的编译可用性以当前 Xcode SDK 和每个声明的 availability 保护为准。

## 当前目录

```text
Sources/BoneShellKit/
├── Containers/
│   ├── BoneNavigationController.swift
│   ├── BoneTabBarController.swift
│   ├── BoneSplitViewController.swift
│   └── ShellTab.swift
├── Navigation/
│   ├── NavigationAction.swift
│   ├── NavigationConfiguration.swift
│   ├── ScreenConfiguration.swift
│   └── ShellActionLayout.swift
├── Accessory/
│   ├── ShellTabBarAccessory.swift
│   └── ShellSystemTabAccessoryRow.swift
├── Backgrounds/
│   ├── ShellBackgroundTypes.swift
│   ├── ShellBackgroundView.swift
│   ├── ShellBackgroundCache.swift
│   ├── ShellBackgroundMedia.swift
│   ├── ShellBackgroundAnimation.swift
│   └── ShellBackgroundPlaybackBudget.swift
├── Capsule/
├── Classic/
├── BoneViewController.swift
├── NavigationModules.swift
├── ShellNavButton.swift
├── ShellNavButtonCluster.swift
├── ShellNavButtonHost.swift
├── ShellNavigationTitleHost.swift
├── ShellBarPresentation.swift
├── ShellBarStyle.swift
├── ShellMaterial.swift
├── ShellGlassView.swift
└── 其他公共样式、标签内容和背景承载类型
```

`Containers/` 保存容器级公开类型。`BoneTabBarController` 的 `UITabBarControllerDelegate` extension 与类本体放在同一文件，因为它访问容器的 `private` 状态。`BoneViewController` 保留在根目录，作为页面基类及页面级导航、背景协调入口。

`Navigation/` 保存导航声明模型和兼容布局计算：`NavigationAction`、`NavigationConfiguration`、`ScreenConfiguration` 以及 `ShellActionLayout`。`NavigationModules.swift`、`ShellNavButton.swift` 和 NavButton 的内部承载文件仍保留在根目录，原因是它们同时服务公开按钮 API 和现有内部渲染器；后续移动时应保持相关文件一起迁移。

`Accessory/`、`Backgrounds/`、`Capsule/` 和 `Classic/` 按渲染职责分组。它们包含公共配置与内部 renderer 时，公共类型的文档仍以声明本身为准；目录位置不代表额外的模块边界。

## 类型和文件边界

- 一个公开容器类型及其依赖 `private` 状态尽量放在同一个文件中。
- 同文件 extension 可以访问该文件内的 `private` 成员；移动到其他文件前必须检查是否需要改为 `fileprivate` 或重新设计内部协作接口。
- 公开配置值和枚举优先按领域拆成小文件，避免把导航动作、页面配置和布局算法重新合并到一个大文件。
- 公开类型名称、初始化器标签和 `import BoneShellKit` 保持稳定；源码文件名和目录调整不会成为宿主代码的接入条件。
- 公开或 `open` 声明必须保留中文类型、属性、方法、参数和返回值文档。源码结构调整后应重新运行公开 API 文档扫描。

## 维护入口

| 需要修改的内容 | 入口文件 |
| --- | --- |
| 页面生命周期、页面配置刷新、页面背景协调 | `BoneViewController.swift` |
| 导航栈容器和经典导航栏 | `Containers/BoneNavigationController.swift` |
| 标签目的地、标签栏模式、附加操作 | `Containers/BoneTabBarController.swift`、`Containers/ShellTab.swift` |
| 分栏容器 | `Containers/BoneSplitViewController.swift` |
| 动作语义、角色、可见性和侧栏策略 | `Navigation/NavigationAction.swift` |
| 标题、导航模块、材质和背景配置 | `Navigation/NavigationConfiguration.swift` |
| 页面内容、栏位和背景组合 | `Navigation/ScreenConfiguration.swift` |
| 兼容导航宽度筛选 | `Navigation/ShellActionLayout.swift` |
| 按钮组、组侧栏策略、按钮材质和 iPhone Duo 样式 | `NavigationModules.swift`、`ShellNavButton.swift` |
| 动态背景资源、缓存和播放预算 | `Backgrounds/` |
| 经典栏、胶囊栏和 dock 渲染 | `Classic/`、`Capsule/` |

## 结构调整后的检查

源码结构变更后至少执行以下检查：

1. 确认每个公开类型只定义一次，旧文件路径没有被文档或脚本引用。
2. 运行 `git diff --check`，并检查新目录中的尾随空格。
3. 运行公开 API 中文文档扫描，确认没有遗漏。
4. 使用 iOS Simulator 编译 SDK，并运行导航模块和资源回退的定向测试。

目录拆分只改变源码组织；行为、公开 API、版本兼容默认值和宿主接入方式以 [API 参考](API-Reference.md)、[方法说明](Usage-Examples.md) 及 [导航动作说明](Navigation-Actions.md) 为准。
