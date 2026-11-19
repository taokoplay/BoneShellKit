# 栏位类型：自动、经典、胶囊与系统

`ShellBarPresentation` 将栏位外观与字体、颜色、材质分开配置。SDK 默认 `.system`，Demo 默认 `.automatic`。

已发布行为以 v0.11.0 为基线；NavButton、导航标题视图和标签栏整项自定义 `UIView` 从 v0.11.0 提供。导航动作见 [导航动作](Navigation-Actions.md)，运行结果见 [验证记录](Implementation-Status.md)。示例需要 UIKit / BoneShellKit，在 `@MainActor` 上使用。

| 类型 | iOS 26 及以上 | iOS 26 以下 |
| --- | --- | --- |
| `.automatic` | 胶囊标签栏、系统导航 | 经典标签栏与导航 |
| `.classic` | 经典标签栏与导航 | 经典标签栏与导航 |
| `.capsule` | 标准标签使用原生胶囊；有自定义标签时使用 SDK 胶囊 | SDK 胶囊标签栏、经典导航 |
| `.system` | 标准标签使用 UIKit；有自定义标签时使用 SDK 胶囊 | 标准标签使用 UIKit；需要自定义槽位时使用 SDK 经典栏 |

上述自定义槽位选择只影响标签栏。导航没有胶囊形态，胶囊请求在旧系统上仍由经典导航承载。

表格描述模式解析与 renderer 选择。原生栏位的最终位置和轴向仍由 UIKit / 容器环境决定；已验证紧凑 iPhone 与 Duo 当前窗口的导航栏位，完整 iPad / Duo 姿态矩阵另行验收。带附件的原生 dock 使用 SDK 底部布局，另有独立边界。

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

覆盖优先级：标签栏为“当前页面 → 标签容器 → `.system`”；导航栏为“当前页面 → 导航容器 → 标签容器 → `.system`”。样式是另一个独立配置维度，不会因为文字颜色改变而自动改栏位类型。

页面可以同时覆盖当前导航与标签栏：

```swift
override func configureScreen(_ screen: inout ScreenConfiguration) {
    screen.barPresentation = .capsule
    screen.navigation.title = "胶囊页面"
}
```

修改页面声明后调用 `refreshScreenConfiguration()`；页面值设为 `nil` 时恢复继承。模式切换保留容器、控制器、导航栈、输入与选中项，不重建业务内容。返回按钮继续执行原生 pop，SDK 不替换原生边缘返回手势的 delegate。

`BoneNavigationController.resolvedBarPresentation` 返回导航实际显示的 `.system` 或 `.classic`；标签容器的同名属性返回解析后的 `.system`、`.classic` 或 `.capsule`。

页面的 `BoneViewController.resolvedBarPresentation` 优先反映所在导航容器；需要判断标签栏时应读取标签容器自己的结果，结合 `dockBarView` 等诊断入口区分原生 dock。

## 普通标签的自定义视图

标准模式继续使用图标或图标加文字。自定义模式提供完整的 `UIView`：视图使用整个标签槽位，宿主可自己画图标、文字、角标、背景和选中效果。SDK 不添加默认内容，也不要求配置备用图片。`title` 仍用于无障碍和「更多」列表，不会作为文字额外显示。

```swift
@MainActor
func installCustomTab(on tabs: BoneTabBarController, id: String, makeView: @escaping @MainActor () -> UIView) {
    guard let item = tabs.tabItemConfiguration(for: id) else { return }
    tabs.updateTabItem(id: id, configuration: .init(title: item.title,
                                                     customContent: ShellTabBarCustomContent(makeView: makeView)))
}
```

- 创建时可用 `ShellTab(id:item:root:)`。标准项与自定义项可在同一栏混用。显式传回标准配置才恢复默认图文。
- SDK 负责槽位边界、触控、标签选中与无障碍。自定义视图是展示层，子控件不会抢占标签点击。实现 `ShellTabBarContentUpdating` 可接收 `isSelected`、`isHighlighted`、`isEnabled` 和 `isVisible`。Scene 与「减少动态效果」仍由宿主处理。
- 工厂须返回新的、未挂载的 `UIView`。在同一承载内按条目与 `revision` 复用；改 `revision` 可更换视图，卸载时停止。`tabItemContentMode(for:)` 可区分 `.standard`、`.customView`、`.unavailable`。仅在「更多」里的条目没有独立槽位，其视图不会创建或变成静态图标。
- UIKit 的原生标签项无法挂完整视图。设置可见自定义标签时，SDK 用自己的经典栏或胶囊完整承载；即使请求 `.system`，也不会自动降级成静态图标。清除自定义项后恢复请求的渲染方式。SDK 自绘标签栏不继承原生滚动收起或侧栏布局。

Demo：**示例 → 标签栏 → 标签图标 → 自定义标签视图**。

## 标签栏附加按钮

`ShellTabBarAccessory` 在标签栏两侧增加动作按钮，按钮不参与标签选中。

```swift
tabs.tabBarAccessories = [
    ShellTabBarAccessory(id: "profile", icon: .systemSymbol("person.crop.circle"),
                         position: .leading, accessibilityLabel: "个人中心") { [weak self] in self?.openProfile() },
    ShellTabBarAccessory(id: "compose", icon: .systemSymbol("plus"),
                         position: .trailing, accessibilityLabel: "新建") { [weak self] in self?.openComposer() }
]
```

| 配置 | 承载方式 | 外观 |
| --- | --- | --- |
| iOS 26+ · `.automatic` / `.capsule` | 独立 `UITabBar` 与圆按钮组成 dock | 圆按钮悬浮在胶囊外侧 |
| iOS 26+ · `.system` | `UITabAccessory` 系统槽位 | 常规状态在标签栏上方，收起状态由系统管理 |
| iOS 26 以下 · `.system` | 原生 tab item，拦截 `shouldSelect` 执行动作 | UIKit 排列在目的地两端 |
| `.classic` | 栏内两端，复用经典栏表面 | 图标在上，可选标题在下，占一个标签槽位 |
| iOS 26 以下 · `.capsule` | SDK 胶囊外侧圆按钮 | 纯图标，与胶囊同高度、同模糊材质和阴影 |

经典栏内按钮使用普通标签的颜色，不绘制独立背景或阴影。胶囊外侧及当前系统槽位使用紧凑的纯图标按钮；无障碍名称可由 `accessibilityLabel` 提供。`isEnabled = false` 标记不可用并拒绝执行回调。

请为每个附件提供稳定且唯一的 `id`。替换同 ID 的 `handler` 会使用最新回调，外观相同的列表无需重建触控对象；移除列表后释放相应业务回调并恢复目的地与栏位布局。旧系统原生 tab item 路径会转发宿主 delegate 的 `shouldSelect`、`didSelect` 和转场动画。

当前没有附件溢出菜单。视觉验收建议采用三个目的地、每侧最多一个按钮；更多附件和极窄空间需单独验收。

诊断入口包括 `classicTabBarView`、`capsuleTabBarView`、`dockBarView` 和 `nativeTabAccessoryView`；`leadingAccessoryButtons` / `trailingAccessoryButtons` 对应兼容渲染器管理的按钮。

### 自定义附加按钮

附加动作也可使用完整 `UIView`。标准附件仍使用 `icon:` 构造器；自定义构造器不收图标。玻璃底或背景若需要，由宿主视图绘制。

```swift
@MainActor
func installAssistant(on tabs: BoneTabBarController, makeView: @escaping @MainActor () -> UIView,
                      openAssistant: @escaping () -> Void) {
    let assistant = ShellTabBarAccessory(id: "home.assistant",
        customContent: ShellTabBarCustomContent(makeView: makeView),
        position: .trailing, accessibilityLabel: "AI 助理", handler: openAssistant)
    tabs.barPresentation = .capsule
    tabs.tabBarAccessories = [assistant]
}
```

`.capsule` 把动作放在胶囊外侧，`.classic` 放在栏内两端。iOS 26+ 的 `.system` 可通过 `UITabAccessory` 挂载；旧系统的原生 tab item 无法挂视图，改用 SDK 经典栏承载，不用静态图标替代。通过 `tabBarAccessoryContentMode(for:)` 查询承载状态。使用 `ShellTabBarContentUpdating` 时，动作项的 `isSelected` 恒为 `false`。Demo：**示例 → 标签栏 → 胶囊 → 动态**。

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
- dock 使用稳定的原生条目副本，避免与隐藏容器栏共享 UI 表示。字体 / 几何指标变化后，在实际拟合尺寸建立时刷新原生文字布局，保留选中项和可访问性标识；普通选中回调继续复用既有控件。

独立 `UITabBar` 保留自己的 UIKit 外观、选中指示与标签手势；控制器原生栏的滚动收起联动需单独适配。

### 兼容胶囊与经典栏

iOS 26 以下的 SDK 胶囊左右各留 12 pt，底边高于安全区 8 pt，高度至少 52 pt 并按标签字体行高调整。材质使用 `systemChromeMaterial`；减少透明度时改为实色。圆按钮与胶囊共用阴影配置，选中项显示半透明胶囊高亮，支持 badge。超过五个目的地时提供“更多”入口。

经典标签栏全宽，内容高度至少 49 pt，并覆盖底部安全区。经典导航沿用原生导航容器的布局区域，使用平直前景与普通操作按钮；大标题随可用高度显示或收起。

SDK 为兼容栏位增加必要的安全区贡献，退出时只移除自身贡献；宿主额外的 `additionalSafeAreaInsets` 会保留。在 iOS 27.1 中，经典类型禁用原生自动竖向栏位，其余模式继续采用系统行为；这不是保留区域或姿态适配 API。

## 列表在胶囊下方滚动与底部渐隐

当页面所在容器呈现可见的浮动标签栏（包含 iOS 26+ 的原生 `.system`），且页面没有 `hidesBottomBarWhenPushed` 时，已通过 `registerPrimaryScrollView(_:)` 注册的列表会延伸到页面底边，内容可从胶囊和圆按钮后方经过。顶部和侧边仍遵循页面声明；经典栏及没有主滚动视图的固定内容继续使用原来的边界策略。

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

v0.9.0 新增 `ShellTabLabelDisplayMode`，提供 `.always / .never / .selectedOnly / .unselectedOnly`。使用 `tabs.tabBarStyle.labelDisplayMode = .selectedOnly` 设置全栏；页面样式仍整份覆盖该字段，单条目通过可选的 `configuration.labelDisplayMode` 覆盖（`nil` 继承当前样式）。`ShellTabBarStyle` 初始化器默认 `.always`，两种 `ShellTab` 初始化器在 `root:` 前接受默认 `nil` 的可选策略。v0.8.0 不包含此 API。

策略覆盖原生、经典、兼容胶囊与原生 dock；配置中的语义 `title` 保留，隐藏时提供无障碍名称并保留宿主自定义名称。隐藏文字后图标居中，选中项变化后重新判定文字。文字策略与栏位形态、附件配置相互独立；iOS 26 的实际截图已核对，兼容胶囊通过能力注入单元测试，尚未完成旧系统实际运行验证。详细继承规则见 [样式说明](Bar-Styling.md#标签文字显示策略)。

iOS 26 独立原生 dock 的非选中文字颜色受 UIKit 玻璃合成影响：本轮观察到传入蓝色后仍呈系统深色，当前不保证该颜色的像素一致性。字号、完整文字行高与图标渲染分别验证。

[独立与整体背景](Backgrounds.md) 保留原来的资源和播放生命周期。使用 `.unified` 时，页面与栏位透出同一整体画布；切换栏位模式不重建背景资源。

## 为什么不借用系统搜索角色

UIKit 对 `UISearchTab` 提供专用搜索呈现，普通 `UITab` 的 placement 不提供通用外围按钮位。SDK 使用独立原生标签栏组成 dock，避免将任意业务动作伪装为系统搜索标签。

## Demo 与验证

Demo 的“导航栏”和“标签栏”分别集中对应设置。导航形态可跟随标签 / 系统 / 经典；标签页可选择自动 / 经典 / 胶囊和附加按钮无 / 左 / 右 / 左右，点击页内按钮显示回执。标签页恢复默认会回到 `.automatic`；显式 `.system` 可通过启动参数或宿主 API 请求。v0.9.0 新增 `tabbar.labels` 四段开关“始终显示 / 始终隐藏 / 仅选中 / 仅未选中”、状态“文字：…”，reset 回到 `.always` 并保留原有恢复规则。

启动参数仅选择请求类型，不伪造系统能力：

```text
-classic-bars
-capsule-bars
-system-bars
-tabs-accessory leading   # 也支持 trailing / both，用于直接观察组合
# 无模式参数时使用 automatic
-ui-testing              # 仅关闭 UIView 动画，不改变系统能力
```

启动时的 `-tabs-accessory` 按钮 handler 为空，只用于观察外形；验证回执应进入标签页使用其设置。若同时传多个模式参数，按 classic → capsule → system 顺序选择。

执行命令见 [README](../README.md)，用例与设备矩阵见 [Demo 与测试规划](Demo-Test-Plan.md)，已完成范围见 [实现与验证记录](Implementation-Status.md)。几何、命中、遮罩、恢复及低版本兼容分支由单元 / 集成测试检查；UI 测试在实际运行系统中保留截图附件，用于核对文字、间距、投影与连续切换状态。

UI case `testLabelDisplayModesAcrossClassicNativeCapsuleAndDock` 已在 iPhone 13 Pro / iOS 26.0 遍历经典、原生胶囊无附件、原生 dock 左右附件与四种策略，保留 12 张策略截图及 3 张切到关于的截图，均为 `.keepAlways`。仅选中时往返关于 / 示例，验证设置页、选中项与 AX 名称；15 张原图和对比已打开核对，视觉隐藏及图标居中与几何断言分别确认，不能由 AX 文字名称推断。该用例包含在文字策略的 105 项相关回归中，实际范围见 [验证记录](Implementation-Status.md#090-标签文字显示策略与验证)，不沿用既有 0.8 回归结论。
