# 栏位字体、颜色与图标

适用于 **v0.9.0 验证版**；“标签文字显示策略”自 v0.9.0 提供，v0.8.0 不包含，运行与视觉验证见 [验证记录](Implementation-Status.md#090-标签文字显示策略与验证)。示例需 `import UIKit`、`import BoneShellKit`，并在主线程 / `@MainActor` 上使用。栏位形态与样式分别配置，四种呈现模式见 [栏位类型](Bar-Presentation.md)。

导航栏和标签栏的文字通过 `ShellTextStyle` 设置，支持字号、字体、粗细、颜色及 Dynamic Type。导航提供普通标题、大标题、副标题与按钮四种角色；标签提供普通态和选中态的文字及图标颜色。标签图标可使用 SF Symbol、bundle 资源图片或 UIImage，并可在运行时替换。
`ShellNavigationStyle.backgroundColor` 可传入带透明度的主题色；系统玻璃保留 `UIGlassEffect`，并将该颜色作为栏位色彩叠加，标题和按钮仍使用各自的文字样式。媒体背景存在时，栏位颜色由 `ShellBackgroundConfiguration` 接管。

## 材质表面由谁绘制

`ShellMaterial` 只表达请求，实际绘制分两类：

| 承载 | 绘制者 | 裁剪规则 |
| --- | --- | --- |
| 导航栏、标签栏本体 | UIKit（`UINavigationBarAppearance` / `UITabBarAppearance`，SDK 只叠加颜色） | 系统决定 |
| 导航按钮、按钮组、兼容胶囊栏、标签附加按钮 | SDK 的 `ShellGlassView` 或等价绘制层 | `.systemGlass` 不裁剪溢出层，保留系统玻璃的边缘高光；回退材质继续用圆角遮罩 |

因此 `ShellMaterial.systemGlass` 只描述“要系统玻璃”。请求被 `ShellMaterials` 解析为 `.solid`（开启“减少透明度”）或回退磨砂（iOS 15–25）时，裁剪与描边恢复为回退材质的行为。SDK 自己绘制的玻璃关闭 `UIGlassEffect.isInteractive`：这些表面层不参与命中测试，按压反馈由承载控件自身负责。

按钮组始终只画一块覆盖整个模块的表面，系统玻璃与回退材质共用同一个 `ShellGlassView`，区别只在效果与裁剪。系统分组玻璃本身也是一整块无分隔线的连续表面；尝试过给组内每个按钮各配一个玻璃元素再用 `UIGlassContainerEffect` 合并，两枚胶囊相接时并集轮廓会在接缝处凹下去（44 pt 高、8 pt 净距时凹陷约 9 pt），重叠时又会因双重折射出现暗带，因此不再采用。组与相邻模块之间保持独立表面，与“组是原子模块”的语义一致。

主题色有两条同源通道：栏位用 `ShellNavigationStyle.backgroundColor`，按钮表面用 `ShellNavButton.Style.tintColor`，按钮组用 `NavigationButtonGroup.tintColor`。系统玻璃把它们交给 `UIGlassEffect.tintColor`，回退磨砂把它们作为叠加色。

## 导航栏字体与颜色

```swift
final class DetailController: BoneViewController {
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "详情"
        screen.navigation.subtitle = "副标题"
        screen.navigation.style = ShellNavigationStyle(
            title: ShellTextStyle(size: 22, weight: .semibold, color: .label),
            largeTitle: ShellTextStyle(size: 34, weight: .bold, color: .systemBlue),
            subtitle: ShellTextStyle(size: 12, color: .secondaryLabel),
            buttons: ShellTextStyle(size: 17, weight: .medium, color: .systemBlue)
        )
        // 不传 symbol 就显示文字按钮，字体使用 buttons 配置。
        screen.navigation.trailingModules = [
            NavigationAction(id: "save", title: "保存", priority: 20, handler: {})
        ].map(\.asNavigationModule)
    }
}
```

`ShellTextStyle(font:color:scalesWithDynamicType:)` 也接受完整 UIFont，例如 `.monospacedSystemFont(ofSize: 18, weight: .medium)`，或宿主已注册的自定义字体。简便初始化器 `size:` 要求有限且大于零的字号。

字体默认通过 `UIFontMetrics` 随 Dynamic Type 调整；需要固定字号时使用 `scalesWithDynamicType: false`。颜色可以传入 `.label`、`.secondaryLabel` 或根据 traits 返回颜色的动态 UIColor，以适配深浅色。

| 角色 | 影响范围 |
| --- | --- |
| `title` | 普通导航标题 |
| `largeTitle` | `usesLargeTitle = true` 时的大标题 |
| `subtitle` | iOS 26+ 原生副标题及大标题副标题；iOS 15–25 的 SDK 副标题视图 |
| `buttons` | 导航文字按钮及返回文字的字体与颜色，并设置栏位和 SDK 操作的 tint |

SF Symbol 导航操作仍保留原生图标尺寸；`buttons.font` 用于文字按钮，不会把图标当成字体放大。系统更多菜单里的行文字继续使用系统菜单字体。按钮禁用态保留 UIKit 的禁用颜色；系统玻璃返回图标保留 UIKit 自身的表现。

SDK 会用实际标题和按钮字体测量宽度；文字按钮过宽时进入原生更多菜单，保持操作可达。设置很大的字体不会强制增加系统导航栏高度；标题截断、紧凑显示和大标题折叠仍受 UIKit 约束。

## 标签栏字体与颜色

容器级默认配置：

```swift
tabs.tabBarStyle = ShellTabBarStyle(
    normal: ShellTextStyle(size: 11, color: .secondaryLabel),
    selected: ShellTextStyle(size: 12, weight: .semibold, color: .systemBlue),
    normalIconColor: .secondaryLabel,
    selectedIconColor: .systemBlue
)
```

页面级覆盖：

```swift
override func configureScreen(_ screen: inout ScreenConfiguration) {
    screen.tabBarStyle = ShellTabBarStyle(
        normal: ShellTextStyle(size: 12, color: .systemGray),
        selected: ShellTextStyle(size: 14, weight: .bold, color: .systemOrange),
        selectedIconColor: .systemOrange
    )
}
```

原生栏位的样式写入 stacked、inline、compact inline 三种布局，以及 standard / scroll-edge Appearance；经典与兼容胶囊使用同一份样式配置，原生 dock 同步文字属性并维护独立条目副本。当前接口配置整个标签栏的普通 / 选中态，每个标签单独提供标题与图标。过大字号仍受系统栏位高度、截断和紧凑布局约束。

iOS 26 原生 dock 的非选中文字颜色受 UIKit 玻璃合成影响，本轮配置蓝色后仍观察到系统深色文字。不能将属性已设置解释为最终像素完全一致；字号和完整行高已单独验证，详见 [实现与验证记录](Implementation-Status.md)。

`normalIconColor` / `selectedIconColor` 作用于可着色的模板图标，文字颜色可以分别配置。明确配置颜色时，SDK 按当前 traits 生成对应颜色的图标，兼容原生栏位未采用未选中 tint 的情况。使用 `.alwaysOriginal` 的彩色 UIImage 保留自身颜色。

## 标签文字显示策略

本节 API **自 v0.9.0 提供，v0.8.0 不包含**。`ShellTabLabelDisplayMode: String, CaseIterable, Sendable` 声明四种策略：

| 策略 | 文字显示 |
| --- | --- |
| `.always` | 始终显示；`ShellTabBarStyle` 初始化器的默认值 |
| `.never` | 始终隐藏 |
| `.selectedOnly` | 仅选中条目显示 |
| `.unselectedOnly` | 仅未选中条目显示 |

全栏通过容器样式设置：

```swift
tabs.tabBarStyle.labelDisplayMode = .selectedOnly
```

页面 `screen.tabBarStyle` 仍为整份覆盖，`labelDisplayMode` 与字体、颜色一起参与覆盖。新建 `ShellTabBarStyle()` 的该字段为 `.always`；需要继承容器的其他字段时，先复制容器样式：

```swift
override func configureScreen(_ screen: inout ScreenConfiguration) {
    var style = (tabBarController as? BoneTabBarController)?.tabBarStyle ?? ShellTabBarStyle()
    style.labelDisplayMode = .never
    screen.tabBarStyle = style
}
```

单个条目可通过 `ShellTabItemConfiguration.labelDisplayMode` 覆盖当前生效样式。该可选字段及初始化器参数默认为 `nil`，表示继承；设回 `nil` 即恢复继承：

```swift
if var configuration = tabs.tabItemConfiguration(for: "home") {
    configuration.labelDisplayMode = .always
    tabs.updateTabItem(id: "home", configuration: configuration)
}
```

`ShellTab` 的 `symbol:` 与 `icon:` 两种初始化器均在 `root:` 前新增可选参数 `labelDisplayMode: ShellTabLabelDisplayMode? = nil`，例如：

```swift
ShellTab(id: "home", title: "首页", symbol: "house",
         labelDisplayMode: .always, root: HomeController())
ShellTab(id: "profile", title: "我的", icon: .systemSymbol("person"),
         labelDisplayMode: .never, root: ProfileController())
```

策略只控制栏上的可见文字，配置中的语义 `title` 保留；隐藏时提供无障碍名称，并保留宿主自定义名称。隐藏文字时图标在条目内居中。当前选中项变化后重新判定文字，字体、图标、颜色、内容实例和导航栈沿用原有配置。原生“更多”按钮跟随整栏策略，溢出列表中的目的地名称保留。实现涵盖原生、经典、兼容胶囊和原生 dock；iOS 26 实测和旧系统尚未验证的范围见 [验证记录](Implementation-Status.md#090-标签文字显示策略与验证)，不能用自动化树中的文字名称判断视觉隐藏。

## 默认值、继承与恢复

```swift
navigation.navigationStyle = ShellNavigationStyle(
    title: ShellTextStyle(size: 20, weight: .semibold, color: .systemBlue)
)

// 页面不设置 style 时，继承 navigation.navigationStyle。
// 页面不设置 tabBarStyle 时，继承 tabs.tabBarStyle。
```

`screen.navigation.style = nil` 与 `screen.tabBarStyle = nil` 继承对应容器配置。显式设置空的 `ShellNavigationStyle()` 或 `ShellTabBarStyle()` 跳过 SDK 容器的字体 / 颜色样式，使用宿主原始 / 系统外观；v0.9.0 中空 `ShellTabBarStyle()` 还会将文字策略设为默认 `.always`。

页面样式是整份覆盖值，其中 font 或 color 为 nil 的字段保留 UIKit 值。需要只修改容器样式中的一个字段时，先复制容器样式，再修改字段并赋给页面。

修改页面状态后调用 `refreshScreenConfiguration()`；修改容器的 `navigationStyle` 或 `tabBarStyle` 会刷新当前页面。内容和导航栈不会因此重新创建。样式与图片 / 动图 / MP4 / HTML 背景共同应用，切换背景时不会清除字体和颜色。

## 选中时使用颜色还是图片

每个条目通过 `selectedIconMode` 明确选择选中时的显示方式：

| 模式 | 选中图案与颜色 |
| --- | --- |
| `.automatic` | 默认兼容已有行为：采用已有 selectedIcon 和 UIImage 渲染模式。 |
| `.selectedColor` | 沿用普通图标图案，保留透明孔洞和轮廓，按当前选中颜色着色；不换成独立的选中图案。 |
| `.selectedImage` | 使用 selectedIcon 的原色图片，保留图案、透明区域和多色细节；未提供时用普通图片原色回退。 |

```swift
ShellTab(
    id: "profile", title: "我的",
    icon: .asset("ProfileTab", bundle: .main),
    selectedIcon: .asset("ProfileTabSelected", bundle: .main),
    selectedIconMode: .selectedImage,
    root: ProfileController()
)
```

如果只希望选中时改变颜色，设置 `.selectedColor`；使用的颜色依次为 `tabBarStyle.selectedIconColor`、选中标题颜色 `tabBarStyle.selected.color` 和当前标签栏 tint。通过 SDK 的样式属性更新颜色会刷新条目。该模式即使普通 UIImage 原先为 `.alwaysOriginal`，也会明确按选中颜色绘制。

颜色模式根据 alpha 轮廓着色，适合透明底图；带有不透明背景或多色细节的图片应选择 `.selectedImage` 来保留图案像素。两个显式模式都会提供确定的选中图像，避免系统自动替换 SF Symbol 的填充图案。普通态的原有配置保持独立。

运行时也可更新：

```swift
if var item = tabs.tabItemConfiguration(for: "profile") {
    item.selectedIconMode = .selectedColor
    tabs.updateTabItem(id: "profile", configuration: item)
}
```

这会更新原有目的地条目及当前栏位呈现，包括经典、兼容胶囊和原生 dock，不重建标签内容控制器，也不改变选中项、导航栈或业务输入。Demo 首页进入“标签栏”，在“选中时如何显示”中对照普通轮廓着色与独立选中图片原色。

## 普通和选中图标

原有写法继续有效：

```swift
ShellTab(id: "home", title: "首页", symbol: "house", root: HomeController())
```

不同选中图标：

```swift
ShellTab(
    id: "home", title: "首页",
    icon: .systemSymbol("house"),
    selectedIcon: .systemSymbol("house.fill"),
    root: HomeController()
)

ShellTab(
    id: "profile", title: "我的",
    icon: .asset("ProfileTab", bundle: .main),
    selectedIcon: .asset("ProfileTabSelected", bundle: .main),
    root: ProfileController()
)
```

`ShellTabIcon.image(image)` 直接使用 UIImage；要保留彩色图标，可传入 `image.withRenderingMode(.alwaysOriginal)`。需要随选中颜色着色的图片可使用 `.alwaysTemplate`，资源目录中也可以配置模板渲染。图标请准备为适合系统标签栏的尺寸与透明边界，不建议把大幅照片直接作为图标。

图标当前使用本地资源，`.asset` 遵循 `UIImage(named:in:compatibleWith:)` 的资源命名和缓存规则；普通 PNG 的自动渲染模式会转为模板模式，以便普通 / 选中颜色生效，资产目录中显式设置的模板或原色模式则保留。远程下载与图片解码可由宿主处理后传入 UIImage。

## 运行时替换图标或标题

```swift
let updated = tabs.updateTabItem(
    id: "home",
    configuration: ShellTabItemConfiguration(
        title: "主页",
        icon: .systemSymbol("square.grid.2x2"),
        selectedIcon: .systemSymbol("square.grid.2x2.fill")
    )
)
```

目的地更新发生在原有 `UITabBarItem` 上；原生 dock 使用稳定副本同步显示数据，避免与隐藏的容器栏共享 UI 表示。标签控制器、当前选中项、各标签的导航栈和业务输入会保留。ID 必须是初始化时唯一的 `ShellTab.id`；找不到 ID 或对应控制器已移除时返回 `false`，不修改其他标签。

`tabItemConfiguration(for:)` 返回当前条目配置，可复制修改后再整体更新。配置是完整替换：`selectedIcon = nil` 表示选中时采用普通图标；`icon = nil` 清除普通图标。稳定 ID、tag 和可访问性标识不会随标题变化而变化。兼容属性 `ShellTab.symbol` 对自定义图片返回空字符串，新代码可读取 `ShellTab.item.icon`。

所有样式和更新入口均在 `@MainActor` 上使用，不修改全局 `UIAppearance`，不使用私有类名或 KVC。原生 dock 的拟合测量和标识恢复使用公开的 `UIView`、`UIControl`、`UILabel` 属性；系统版本升级后仍需验证实际呈现。

## Demo 与验证

Demo 的设置分为两页：

- “导航栏”：标题字号 / 颜色、副标题、大标题、按钮字号、导航形态，以及输入详情页。标题和按钮字号独立；按钮选择“系统”时保留系统字号。形态可跟随标签、使用系统或使用经典导航。
- “标签栏”：标签字号 / 颜色、SF Symbol / 资源 / 原色 UIImage、选中策略、自动 / 经典 / 胶囊形态、左右附加按钮，以及整体背景。v0.9.0 提供 `tabbar.labels` 四段开关“始终显示 / 始终隐藏 / 仅选中 / 仅未选中”，状态包含“文字：…”。

恢复默认时，导航页恢复继承标签容器；标签页恢复 Demo 默认 `.automatic`，并清除附加按钮和页面背景，文字策略同时恢复 `.always`。空样式恢复字体 / 颜色，与 `.system` 栏位呈现是两个独立设置。

实际执行数量、运行环境、截图及手机安装结果见 [验证记录](Implementation-Status.md)。旧版 OS 和 iPad / Duo 全部布局仍按 [测试规划](Demo-Test-Plan.md) 单独验收；公开 API 编译通过不等同于所有系统姿态都已运行。
