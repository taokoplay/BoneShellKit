# SDK 可设置字段与中文说明

适用于 **v0.12.1**。NavButton、导航标题视图和标签栏整项自定义视图自 v0.11.0 提供，导航动作强制显示自 v0.12.0 提供，iOS 26 导航共享玻璃、NavButton 返回恢复和自定义 confirmation 行为自 v0.12.1 提供；导航图片、动作角色、轴向偏好及系统动作布局自 v0.10.0 提供，v0.9.1 不包含。方法和创建入口见 [SDK 方法说明](Usage-Examples.md)，源码分区和类型维护入口见 [源码结构说明](Source-Layout.md)。页面字段在 `configureScreen(_:)` 中设置；容器字段直接赋值。标注“创建时设置”的值不能在创建后直接修改，只读结果单列在文末。

## 页面配置：ScreenConfiguration

| 字段 | 类型 | 默认值 | 中文说明 |
| --- | --- | --- | --- |
| `navigation` | `NavigationConfiguration` | `NavigationConfiguration()` | 导航栏配置，子字段见下一节 |
| `barPresentation` | `ShellBarPresentation?` | `nil` | 本页的导航栏和标签栏模式；`nil` 继承容器 |
| `content` | `ShellContentPlacement` | `.safeArea` | 内容布局范围：安全区内或延伸到栏位下方 |
| `avoidsKeyboard` | `Bool` | `false` | 是否让内容底边避开停靠键盘，不跟随悬浮键盘 |
| `floatingTabBarFadeHeight` | `CGFloat` | `80` | 主滚动内容在浮动标签栏下方的渐隐高度，单位 pt；`0` 关闭 |
| `background` | `ShellBackgroundConfiguration?` | `nil` | 页面背景；`nil` 清除页面背景 |
| `backgroundComposition` | `ShellBackgroundComposition` | `.independent` | 背景分区显示，或用一张完整画布贯穿页面和栏位 |
| `tabBarBackground` | `ShellBackgroundConfiguration?` | `nil` | 本页标签栏背景；`nil` 继承标签容器背景 |
| `tabBarStyle` | `ShellTabBarStyle?` | `nil` | 本页整栏标签样式；`nil` 继承标签容器样式 |

主滚动视图通过 `registerPrimaryScrollView(_:)` 注册。浮动标签栏下的滚动视口可延伸到底边，SDK 调整避让策略并保留业务 `contentInset`；渐隐只影响内容，不影响标签按钮。

## 导航配置：NavigationConfiguration

通过 `screen.navigation` 设置。

| 字段 | 类型 | 默认值 | 中文说明 |
| --- | --- | --- | --- |
| `title` | `String` | `""` | 导航标题 |
| `subtitle` | `String?` | `nil` | 导航副标题；`nil` 不显示 |
| `titleView`（v0.11.0+） | `UIView?` | `nil` | 完整可交互的内联标题；替换文字与副标题，自定义时不显示大标题。设回 `nil` 恢复标准配置 |
| `usesLargeTitle` | `Bool` | `false` | 是否请求大标题显示 |
| `leadingModules` | `[NavigationModule]` | `[]` | 前侧有序模块；模块可以是独立按钮或按钮组 |
| `trailingModules` | `[NavigationModule]` | `[]` | 后侧有序模块；模块顺序参与布局、溢出和 Duo 位置计算 |
| `moduleSpacing` | `CGFloat` | `8` | 相邻模块可见边界之间的固定间距；SDK 会校正系统栏位和按钮内边距产生的额外空间 |
| `material` | `ShellMaterial` | `.automatic` | 导航材质，不改变栏位模式 |
| `background` | `ShellBackgroundConfiguration?` | `nil` | 本页导航背景；`nil` 继承导航容器背景 |
| `style` | `ShellNavigationStyle?` | `nil` | 本页导航字体与颜色；`nil` 继承导航容器样式 |

## 导航按钮：NavigationAction

| 字段 | 类型 | 默认值 | 中文说明 |
| --- | --- | --- | --- |
| `id` | `String` | 必填 | 按钮的稳定标识，同一页左右两组应唯一；重复时保留首项 |
| `title` | `String` | 必填 | 按钮名称，也用于菜单和无障碍名称 |
| `symbol` | `String` | `""` | SF Symbol 图标名称；空字符串显示文字按钮 |
| `icon`（v0.10.0+） | `ShellNavigationIcon?` | `nil` | 非 nil 时覆盖 symbol；支持系统符号、资源图片和 UIImage，解析失败显示标题 |
| `navButton`（v0.11.0+） | `ShellNavButton?` | `nil` | 自定义按钮的横栏样式、iPhone Duo 样式及整项内容；SDK 将组内按钮材质解析为组材质 |
| `role`（v0.10.0+） | `ShellNavigationActionRole` | `.normal` | `.cancellation` 放在前侧；`.confirmation` 放在后侧，原生布局固定首个确认动作；带 `navButton` 的 confirmation 保留语义优先级但使用自定义按钮外观 |
| `axisBehavior`（v0.10.0+） | `ShellNavigationActionAxisBehavior` | `.automatic` | 自动 / `.horizontalOnly` 仅横向 / `.verticalPreferred` 优先竖向，iOS 27.1+ 映射到系统 |
| `visibility`（v0.12.0+） | `ShellNavigationActionVisibility` | `.automatic` | `.automatic` 允许动作按空间与优先级进入溢出；`.always` 要求动作保留在导航栏中 |
| `priority` | `Int` | `0` | 保留在栏上的优先级，越大越优先，不改变显示顺序 |
| `isEnabled` | `Bool` | `true` | 是否允许点击 |
| `handler` | `() -> Void` | 必填 | 点击回调，引用页面时可用 `[weak self]` |

自 v0.10.0 起，iOS 27+ 原生导航将完整唯一动作交给系统分组、优先级及溢出；经典和旧系统保留 SDK 宽度算法。图片渲染、多个确认动作及诊断语义见 [导航动作与自适应](Navigation-Actions.md)。

`ShellNavButton(normal:iPhoneDuo:)` 支持分轴配置按钮尺寸、图标尺寸、方向性内边距、整项视图工厂和背景。`iPhoneDuo` 仅在实际侧边栏生效；`axisBehavior.horizontalOnly` 可关闭默认侧边栏迁移。完整示例见[导航动作与自适应](Navigation-Actions.md)。
自定义 NavButton 不与系统 `UIBarButtonItem` 的 `primaryAction`、`title`、`image` 或单独 `customView` 内容混用。系统栏位负责位置、分组、溢出和共享玻璃，SDK cluster 负责自定义按钮的内容、材质和点击区域。页面 push / pop 返回时，SDK 按稳定 ID 重新提交按钮和分组。

## 容器字段

| 类型 | 字段 | 默认值 | 中文说明 |
| --- | --- | --- | --- |
| `BoneNavigationController` | `barPresentation: ShellBarPresentation?` | `nil` | 导航栏模式；`nil` 继承标签容器，独立使用时为 `.system` |
| `BoneNavigationController` | `navigationStyle: ShellNavigationStyle` | `ShellNavigationStyle()` | 导航栏默认字体与颜色 |
| `BoneNavigationController` | `backgroundConfiguration: ShellBackgroundConfiguration?` | `nil` | 导航栏默认媒体背景 |
| `BoneTabBarController` | `barPresentation: ShellBarPresentation` | `.system` | 标签栏默认模式，也可由内部导航容器继承 |
| `BoneTabBarController` | `tabBarStyle: ShellTabBarStyle` | `ShellTabBarStyle()` | 标签栏默认文字、图标颜色和文字显示策略 |
| `BoneTabBarController` | `tabBarAccessories: [ShellTabBarAccessory]` | `[]` | 标签栏附加按钮，空数组移除全部附加按钮 |
| `BoneTabBarController` | `backgroundConfiguration: ShellBackgroundConfiguration?` | `nil` | 标签栏默认媒体背景 |

修改容器字段会自动应用当前外观；页面已有覆盖时仍优先采用页面值。`selectedIndex`、`selectedViewController`、`hidesBottomBarWhenPushed` 等是 UIKit 属性，按 UIKit 使用。

## 文字样式：ShellTextStyle

| 字段 / 创建参数 | 类型 | 默认值 | 中文说明 |
| --- | --- | --- | --- |
| `font` | `UIFont?` | `nil` | 基础字体；`nil` 保留对应 UIKit 字体 |
| `color` | `UIColor?` | `nil` | 文字颜色，支持动态色；`nil` 保留对应 UIKit 颜色 |
| `scalesWithDynamicType` | `Bool` | `true` | 是否随系统文字大小设置缩放 |
| `size`（创建参数） | `CGFloat` | `size:` 入口必填 | 基础字号，单位 pt，必须有限且大于 0 |
| `weight`（创建参数） | `UIFont.Weight` | `.regular` | 字重，配合 `size:` 创建系统字体 |

`size`、`weight` 仅用于创建；创建后修改字体使用 `font`。

## 导航样式：ShellNavigationStyle

通过 `screen.navigation.style` 或 `navigation.navigationStyle` 设置。以下字段均为 `ShellTextStyle`，`backgroundColor` 除外；默认值均为空样式或 `nil`。

| 字段 | 中文说明 |
| --- | --- |
| `title` | 普通导航标题的字体和颜色 |
| `largeTitle` | 大标题的字体和颜色 |
| `subtitle` | 副标题的字体和颜色 |
| `buttons` | 文字按钮、返回文字的字体和颜色，以及 SDK 操作 tint |
| `backgroundColor` | 导航栏背景色，类型为 `UIColor?`，默认 `nil`；可携带主题透明度，玻璃材质会叠加该颜色，媒体背景存在时由背景配置接管 |

## 标签栏样式：ShellTabBarStyle

通过 `screen.tabBarStyle` 或 `tabs.tabBarStyle` 设置。

| 字段 | 类型 | 默认值 | 中文说明 |
| --- | --- | --- | --- |
| `normal` | `ShellTextStyle` | `ShellTextStyle()` | 未选中标签的文字样式 |
| `selected` | `ShellTextStyle` | `ShellTextStyle()` | 选中标签的文字样式 |
| `normalIconColor` | `UIColor?` | `nil` | 未选中模板图标的颜色，原色图片保留自身颜色 |
| `selectedIconColor` | `UIColor?` | `nil` | 选中模板图标的颜色 |
| `labelDisplayMode` | `ShellTabLabelDisplayMode` | `.always` | 整栏文字显示策略，单标签可覆盖；v0.9.0 起支持 |

## 创建标签：ShellTab

以下为创建时设置的参数。

| 参数 | 类型 | 默认值 | 中文说明 |
| --- | --- | --- | --- |
| `id` | `String` | 必填 | 标签唯一标识，后续按此 ID 更新 |
| `title` | `String` | 必填 | 标签名称 |
| `symbol` | `String` | `symbol:` 入口必填 | 普通 SF Symbol 图标名称，与 `icon:` 入口二选一 |
| `icon` | `ShellTabIcon` | `icon:` 入口必填 | 普通态图标，可用系统图标、资源图片或 UIImage |
| `selectedIcon` | `ShellTabIcon?` | `nil` | 独立选中图标，仅 `icon:` 入口支持 |
| `selectedIconMode` | `ShellTabSelectedIconMode` | `.automatic` | 选中时按颜色还是按原图显示 |
| `labelDisplayMode` | `ShellTabLabelDisplayMode?` | `nil` | 单标签文字策略；`nil` 跟随当前整栏样式 |
| `root` | `UIViewController` | 必填 | 标签根页面，已有导航容器会直接复用 |

`ShellTab` 创建后通过 `item` 读取展示配置；修改容器内的标签使用 `tabItemConfiguration(for:)` 和 `updateTabItem(id:configuration:)`。

## 更新标签：ShellTabItemConfiguration

| 字段 | 类型 | 默认值 | 中文说明 |
| --- | --- | --- | --- |
| `title` | `String` | 必填 | 标签名称，隐藏文字时仍保留语义标题 |
| `icon` | `ShellTabIcon?` | `nil` | 普通态图标，`nil` 清除普通图标 |
| `selectedIcon` | `ShellTabIcon?` | `nil` | 选中态图标，`nil` 回退普通图标 |
| `selectedIconMode` | `ShellTabSelectedIconMode` | `.automatic` | 选中图标显示策略 |
| `labelDisplayMode` | `ShellTabLabelDisplayMode?` | `nil` | 单标签文字策略，设回 `nil` 恢复继承 |
| `customContent` | `ShellTabBarCustomContent?` | `nil` | v0.11.0+：整项 `UIView`；非空时不渲染标准图标、文字、角标或选中样式 |

更新为整份替换；先读取旧配置再修改单个字段，可保留其余设置。

`ShellTabBarCustomContent(revision:makeView:)` 的版本默认为 `0`。`makeView` 必须返回未挂载的 `UIView`；视图填满槽位。`tabItemContentMode(for:)` 返回 `.standard`、`.customView`、`.unavailable`，或在未加载 / 未注册时返回 `nil`。见[示例](Bar-Presentation.md#普通标签的自定义视图)。

## 标签栏附加按钮：ShellTabBarAccessory

| 字段 | 类型 | 默认值 | 中文说明 |
| --- | --- | --- | --- |
| `id` | `String` | 必填，创建时设置 | 按钮唯一标识，相同 ID 更新后使用最新回调 |
| `icon` | `ShellTabIcon?` | 标准构造器必填 | 标准按钮图标；自定义构造器无需传入 |
| `title` | `String?` | `nil` | 可选按钮文字，经典栏可显示，胶囊外侧及当前系统槽位使用纯图标 |
| `position` | `Position` | 必填 | `.leading` 在前侧，`.trailing` 在后侧 |
| `isEnabled` | `Bool` | `true` | 是否允许点击 |
| `accessibilityLabel` | `String?` | `nil` | 无障碍名称，纯图标按钮建议设置 |
| `customContent` | `ShellTabBarCustomContent?` | `nil` | v0.11.0+：替换整项视觉内容，无自动静态回退 |
| `handler` | `() -> Void` | 必填 | 点击回调，按钮本身不成为选中的标签 |

`tabBarAccessoryContentMode(for:)` 查询承载结果。自定义视图可实现 `ShellTabBarContentUpdating` 接收状态。详见[自定义附加按钮](Bar-Presentation.md#自定义附加按钮)。

## 背景配置：ShellBackgroundConfiguration

| 字段 | 类型 | 默认值 | 中文说明 |
| --- | --- | --- | --- |
| `source` | `ShellBackgroundSource` | 必填 | 背景来源，支持纯色、图片、动图、视频和 HTML |
| `poster` | `ShellBackgroundResource?` | `nil` | 静态海报，用于加载、暂停或降级时显示 |
| `overlayColor` | `UIColor` | `.clear` | 叠加在背景上的颜色，可用于压暗背景 |
| `fallbackColor` | `UIColor` | `.systemBackground` | 资源加载失败或尚未就绪时的底色 |
| `contentMode` | `UIView.ContentMode` | `.scaleAspectFill` | 图片 / 海报 / 视频的缩放裁切方式，HTML 布局由自身 CSS 控制 |
| `transitionDuration` | `TimeInterval` | `0.15` | 静态图像淡入秒数，实际限制为 0–2 秒；`0` 关闭 |

## 背景播放、缓存和材质字段

| 类型 | 字段 | 默认值 | 中文说明 |
| --- | --- | --- | --- |
| `ShellBackgroundView` | `onStatusChange: ((ShellBackgroundStatus) -> Void)?` | `nil` | 背景状态变化回调，重新赋值替换旧回调 |
| `ShellBackgroundView` | `playbackPriority: Int` | `0` | 动态播放优先级，越大越优先；SDK 页面 / 导航 / 标签默认为 30 / 20 / 10 |
| `ShellBackgroundCache` | `memoryCostLimit: Int`（静态） | `48 * 1024 * 1024` 字节 | 图片缓存软上限；非正数清理缓存并停止后续缓存写入，直到恢复正值 |
| `ShellBackgroundPlaybackBudget` | `maximumActivePerScene: Int`（静态） | `1` | 每个 Scene 最多播放的动态背景数，赋值限制为 `0...3`，`0` 全部静态显示 |
| `ShellGlassView` | `material: ShellMaterial` | `.automatic` | 业务材质视图的材质，赋值后自动刷新 |

播放上限对进程统一设置、按 Scene 分配。不可见、应用不活跃、低电量或无障碍减少动态效果 / 透明度时，动态背景可能暂停。

## 枚举可选值

| 类型 | 可设置值 | 中文说明 |
| --- | --- | --- |
| `ShellBarPresentation` | `.automatic` / `.classic` / `.capsule` / `.system` | 自动选择 / 经典栏位 / 胶囊标签栏 / UIKit 原生栏位 |
| `ShellContentPlacement` | `.safeArea` / `.underBars` | 安全区内布局 / 延伸到栏位下方 |
| `ShellBackgroundComposition` | `.independent` / `.unified` | 分区背景 / 共用完整容器背景；整体模式需提供非 `.none` 的页面背景 |
| `ShellTabLabelDisplayMode` | `.always` / `.never` / `.selectedOnly` / `.unselectedOnly` | 始终显示 / 始终隐藏 / 仅选中时显示 / 仅未选中时显示 |
| `ShellNavigationActionVisibility` | `.automatic` / `.always` | 自动按空间和优先级处理 / 保留在导航栏中 |
| `ShellTabSelectedIconMode` | `.automatic` / `.selectedColor` / `.selectedImage` | 自动 / 普通图案按选中颜色着色 / 选中图原色显示 |
| `ShellMaterial` | `.automatic` / `.systemDefault` / `.systemGlass` / `.frostedGlass` / `.solid` | 自动 / 系统默认 / 原生玻璃 / 仿玻璃 / 实色 |

`.automatic` 栏位在 iOS 26+ 使用胶囊标签栏与系统导航，旧系统使用经典栏位。导航本身没有胶囊形态；`.capsule` 请求在旧系统使用经典导航。

`ShellMaterial.automatic` 在支持时使用原生玻璃，否则使用系统默认材质；显式 `.systemGlass` 不可用时回退仿玻璃。减少透明度开启时材质解析为实色。

### 图标来源：ShellTabIcon

| 值 | 中文说明 |
| --- | --- |
| `.systemSymbol("house")` | 使用 SF Symbol 图标 |
| `.asset("TabHome", bundle: .main)` | 使用指定 bundle 中的图片资源 |
| `.image(image)` | 使用已有 UIImage，可通过其渲染模式选择原色或模板着色 |

### 背景资源：ShellBackgroundResource

| 值 | 中文说明 |
| --- | --- |
| `.asset("Paper", bundle: .main)` | 使用 bundle 中的图片资源或原始文件 |
| `.file(url)` | 使用本地文件 URL |
| `.remote(url)` | 使用 HTTPS 图片、动图或海报 URL |

### 背景来源：ShellBackgroundSource

| 值 | 中文说明 |
| --- | --- |
| `.none` | 无媒体，用于显式关闭本页栏位媒体背景 |
| `.color(color)` | 纯色背景 |
| `.image(resource)` | 静态图片 |
| `.animatedImage(resource)` | GIF / APNG 动图，使用原始文件 |
| `.video(url)` | 本地或 HTTP(S) 视频，静音循环，网络访问受宿主 ATS 设置约束 |
| `.htmlFile(url)` | 本地 HTML 文件 |
| `.htmlString(html, baseURL: url)` | HTML 字符串，相对资源按 baseURL 解析；无基准 URL 时传 `nil` |
| `.htmlURL(url)` | HTTPS 网页背景 |

## 只读属性与结果

以下用于读取视图或状态，不能直接给属性赋新值；可在内容视图中添加业务子视图。

| 类型 | 属性 | 中文说明 |
| --- | --- | --- |
| `BoneViewController` | `contentView` | 业务内容容器 |
| `BoneViewController` | `backgroundView` / `activeBackgroundView` | 独立页面背景 / 当前实际背景；整体模式使用后者 |
| `BoneViewController` | `screenConfiguration` | 最新生成的页面配置快照 |
| `BoneViewController` | `usesUnifiedBackground` / `resolvedBarPresentation` | 是否启用整体背景 / 当前实际栏位模式，优先反映所属导航容器 |
| `BoneViewController` | `visibleActionIDs` / `overflowActionIDs` | SDK 提交到栏位 / 预先放入菜单的动作 ID；v0.10.0 系统布局下前者为候选项，后者为空，不能推断实际可见性 |
| `BoneViewController` | `usesSystemNavigationActionLayout`（v0.10.0+） | 是否处于 iOS 27+ 原生动作布局路径；不表示当前已竖排 |
| 两种 SDK 栏位容器 | `backgroundView` / `unifiedBackgroundView` / `resolvedBarPresentation` | 独立栏位背景 / 此容器拥有的整体背景 / 解析后的栏位模式 |
| `BoneNavigationController` | `classicNavigationBarView` | 当前经典导航栏视图，非对应模式时为 `nil` |
| `BoneTabBarController` | `classicTabBarView` / `capsuleTabBarView` / `dockBarView` / `nativeTabAccessoryView` | 经典栏 / 旧系统 SDK 胶囊 / 原生 dock / 系统附加按钮槽位视图 |
| `BoneTabBarController` | `leadingAccessoryButtons` / `trailingAccessoryButtons` / `supportsTabBarAccessories` | 兼容渲染器前后侧按钮 / 是否支持附件承载，当前支持值为 `true` |
| `ShellBackgroundView` | `configuration` / `status` / `isPlaybackRunning` | 当前配置 / 当前状态 / 动态媒体是否实际播放 |
| `ShellBackgroundStatus` | `phase` | `.idle` 未配置、`.loading` 加载中、`.ready` 就绪、`.paused` 暂停、`.failed` 失败 |
| `ShellBackgroundStatus` | `sourceKind` / `detail` / `pixelSize` | 资源类型 / 暂停或失败原因 / 已准备媒体的像素尺寸 |
| `ShellBackgroundCache` | `statistics` | 当前缓存统计快照 |
| `ShellBackgroundCacheStatistics` | `requestCount` / `cacheHitCount` / `decodeCount` / `inFlightCount` | 请求次数 / 缓存命中次数 / 解码次数 / 当前合并后的在途任务数 |
| `ShellBackgroundSource` | `isDynamic` / `isEmpty` / `kindName` | 是否动态资源 / 是否 `.none` / 资源类型名称 |
| `ShellBarPresentation` | `supportsNativeCapsule`（静态）/ `resolvedForCurrentSystem` | 是否支持原生胶囊 / 当前系统下解析后的模式 |
| `ShellGlassView` | `contentView` / `resolution` | 材质内的业务内容容器 / 当前材质解析结果 |
| `ShellMaterialResolution` | `requested` / `resolved` / `reason` | 请求材质 / 实际材质 / 降级原因；创建参数默认 `.automatic` / `.systemDefault` / `nil`，创建后只读 |

## 设置生效规则

- 页面状态变化后调用 `refreshScreenConfiguration()`；容器属性赋值、标签条目更新会自动应用。
- 页面样式整份覆盖容器样式。`nil` 继承，空样式恢复 UIKit 字体颜色；仅改一项时先复制容器样式。
- 单标签 `labelDisplayMode` 优先于整栏策略，设回 `nil` 恢复继承。整栏空样式的文字策略为 `.always`。
- 页面 `background = nil` 清除背景；导航 / 标签背景为 `nil` 时继承容器，`source: .none` 显式关闭本页栏位媒体背景。

系统外观与多媒体的具体边界见 [栏位模式](Bar-Presentation.md)、[样式说明](Bar-Styling.md)、[背景说明](Backgrounds.md)。
