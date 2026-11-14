# 栏位类型：自动、经典、胶囊与系统

`ShellBarPresentation` 将栏位外观与字体、颜色、材质分开配置。SDK 默认 `.system`，Demo 默认 `.automatic`。

| 类型 | iOS 26 及以上 | iOS 26 以下 |
| --- | --- | --- |
| `.automatic` | 胶囊标签栏、系统导航 | 经典标签栏与导航 |
| `.classic` | 经典标签栏与导航 | 经典标签栏与导航 |
| `.capsule` | 原生胶囊标签栏、系统导航 | SDK 胶囊标签栏、经典导航 |
| `.system` | UIKit 原生栏位 | UIKit 原生栏位 |

显式模式不因系统版本改变其请求的外观。导航没有胶囊形态，因此胶囊请求在旧系统上回退为经典导航。

```swift
ShellBarPresentation.automatic.resolved(supportsNativeCapsule: true)  // .capsule
ShellBarPresentation.automatic.resolved(supportsNativeCapsule: false) // .classic
ShellBarPresentation.supportsNativeCapsule // 当前运行系统的能力
```

## 容器设置与页面覆盖

```swift
let tabs = BoneTabBarController(tabs: [
    ShellTab(id: "home", title: "首页", symbol: "house", root: HomeController()),
    ShellTab(id: "settings", title: "设置", symbol: "gearshape", root: SettingsController())
])
tabs.barPresentation = .automatic
```

标签容器中的 `BoneNavigationController` 默认继承标签容器的模式。`navigation.barPresentation = nil` 表示继承，没有上级容器时使用 `.system`；设置具体值只改变该导航容器。

页面可以同时覆盖当前导航与标签栏：

```swift
override func configureScreen(_ screen: inout ScreenConfiguration) {
    screen.barPresentation = .capsule
    screen.navigation.title = "胶囊页面"
}
```

修改页面声明后调用 `refreshScreenConfiguration()`；页面值设为 `nil` 时恢复继承。模式切换保留容器、控制器、导航栈、输入与选中项，不重建业务内容。返回按钮继续执行原生 pop，SDK 不替换原生边缘返回手势的 delegate。

`BoneNavigationController.resolvedBarPresentation` 返回导航实际显示的 `.system` 或 `.classic`；标签容器的同名属性返回解析后的 `.system`、`.classic` 或 `.capsule`。

## 标签栏附加按钮

`ShellTabBarAccessory` 在标签栏两侧增加动作按钮，按钮不参与标签选中。

```swift
tabs.tabBarAccessories = [
    ShellTabBarAccessory(id: "profile", icon: .systemSymbol("person.crop.circle"),
                         position: .leading, accessibilityLabel: "个人中心") { openProfile() },
    ShellTabBarAccessory(id: "compose", icon: .systemSymbol("plus"),
                         position: .trailing, accessibilityLabel: "新建") { openComposer() }
]
```

| 配置 | 承载方式 | 外观 |
| --- | --- | --- |
| iOS 26+ · `.automatic` / `.capsule` | 独立 `UITabBar` 与圆按钮组成 dock | 圆按钮悬浮在胶囊外侧 |
| iOS 26+ · `.system` | `UITabAccessory` 系统槽位 | 常规状态在标签栏上方，收起状态由系统管理 |
| iOS 26 以下 · `.system` | 原生 tab item，拦截 `shouldSelect` 执行动作 | UIKit 排列在目的地两端 |
| `.classic` | 栏内两端，复用经典栏表面 | 图标在上，可选标题在下，占一个标签槽位 |
| iOS 26 以下 · `.capsule` | SDK 胶囊外侧圆按钮 | 纯图标，与胶囊同高度、同模糊材质和阴影 |

经典栏内按钮使用普通标签的颜色，不绘制独立背景或阴影。胶囊外侧即使指定 `title` 也只显示图标；无障碍名称仍可通过 `accessibilityLabel` 提供。`isEnabled = false` 降低不透明度、标记不可用且不执行回调。

移除列表后恢复目的地与栏位布局。旧系统原生 tab item 路径会转发宿主 delegate 的 `shouldSelect`、`didSelect` 和转场动画。

诊断入口包括 `classicTabBarView`、`capsuleTabBarView`、`dockBarView` 和 `nativeTabAccessoryView`；`leadingAccessoryButtons` / `trailingAccessoryButtons` 对应兼容渲染器管理的按钮。

## 胶囊布局与安全区

### 原生 dock

带附加按钮时，SDK 隐藏容器自身的标签栏，在一个横向栈中放置圆按钮、独立 `UITabBar` 和圆按钮：

- 两侧至少 18 pt，最大宽度 440 pt，水平居中，可见表面之间保持 12 pt 间距。
- 行高和圆按钮直径取最终可见胶囊的高度，上下沿对齐；系统栏仍保留 UIKit 拟合出的完整高度。
- 竖向位置使用系统栏在可见胶囊下方的透明留白，与没有附加按钮时的 UIKit 默认基线一致。SDK 不硬编码系统胶囊坐标或高度。
- 宿主内部补偿 UIKit 的透明横向边距；达到胶囊自然宽度上限后整行收紧居中，不使用负栈间距。
- 尺寸和底部留白的变化合并到下一轮主线程布局，避免从子视图布局同步重入容器。
- 圆按钮使用原生 `UIGlassEffect` 与公开的胶囊圆角配置，保留系统边缘和投影，不裁切或额外叠加手工阴影。
- 透明空隙透传给下方列表；模式切换移除非当前渲染器的旧视图，避免重影或残留按钮。

独立 `UITabBar` 保留自己的 UIKit 外观、选中指示与标签手势；控制器原生栏的滚动收起联动需单独适配。

### 兼容胶囊与经典栏

iOS 26 以下的 SDK 胶囊左右各留 12 pt，底边高于安全区 8 pt，高度至少 52 pt 并按标签字体行高调整。材质使用 `systemChromeMaterial`；减少透明度时改为实色。圆按钮与胶囊共用阴影配置，选中项显示半透明胶囊高亮，支持 badge。超过五个目的地时提供“更多”入口。

经典标签栏全宽，内容高度至少 49 pt，并覆盖底部安全区。经典导航沿用原生导航容器的布局区域，使用平直前景与普通操作按钮；大标题随可用高度显示或收起。

SDK 为兼容栏位增加必要的安全区贡献，退出时只移除自身贡献；宿主额外的 `additionalSafeAreaInsets` 会保留。在 iOS 27.1 中，经典类型明确选择横向栏位，其余模式继续使用系统轴向适配。

## 列表在胶囊下方滚动与底部渐隐

通过 `registerPrimaryScrollView(_:)` 注册的主列表会延伸到页面底边，内容可从胶囊和圆按钮后方经过。顶部和侧边仍遵循页面声明；经典栏和没有注册主滚动视图的固定表单仍使用原来的安全区。

- 使用滚动内边距确保最后一项和滚动指示器能完整移到胶囊上方，不覆盖业务方设置的 `contentInset`。
- 不绘制全宽底部色块。iOS 26+ 隐藏该模式的 `bottomEdgeEffect`，退出时恢复原值。
- 内容默认在视口底部 80 pt 内平滑透明，胶囊与圆按钮仍清晰；渐隐位置不随列表滚动。
- 切回经典栏或键盘缩短内容视口时移除渐隐。宿主的自定义 `contentView.layer.mask` 优先，SDK 不覆盖或误删它。

```swift
override func configureScreen(_ screen: inout ScreenConfiguration) {
    screen.floatingTabBarFadeHeight = 80 // 设为 0 关闭渐隐
}
```

## 字体、图标与背景

[字体、颜色与图标](Bar-Styling.md) 的配置会传递到各模式，包含普通 / 大标题 / 副标题、导航文字按钮、标签普通 / 选中态、本地图片和独立选中图标。栏位类型与 `ShellGlassView` 的材质分别配置。

iOS 26 独立原生 dock 的非选中文字颜色受 UIKit 玻璃合成影响：本轮观察到传入蓝色后仍呈系统深色，当前不保证该颜色的像素一致性。字号、完整文字行高与图标渲染分别验证。

[独立与整体背景](Backgrounds.md) 保留原来的资源和播放生命周期。使用 `.unified` 时，页面与栏位透出同一整体画布；切换栏位模式不重建背景资源。

## 为什么不借用系统搜索角色

UIKit 对 `UISearchTab` 提供专用搜索呈现，普通 `UITab` 的 placement 不提供通用外围按钮位。SDK 使用独立原生标签栏组成 dock，避免将任意业务动作伪装为系统搜索标签。

## Demo 与验证

Demo 的“导航栏”和“标签栏”分别集中对应设置。标签栏页可以选择自动 / 经典 / 胶囊以及附加按钮无 / 左 / 右 / 左右，点击按钮显示回执。

启动参数仅选择请求类型，不伪造系统能力：

```sh
-classic-bars
-capsule-bars
-system-bars
-tabs-accessory leading   # 也支持 trailing / both，用于直接观察组合
# 无模式参数时使用 automatic
```

执行命令见 [README](../README.md)，用例与设备矩阵见 [Demo 与测试规划](Demo-Test-Plan.md)，已完成范围见 [实现与验证记录](Implementation-Status.md)。几何、命中、遮罩、恢复及低版本兼容分支由单元 / 集成测试检查；UI 测试在实际运行系统中保留截图附件，用于核对文字、间距、投影与连续切换状态。
