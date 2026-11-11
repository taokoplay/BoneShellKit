# BoneShellKit 0.3 栏位字体、颜色与图标

导航栏和标签栏的文字通过 `ShellTextStyle` 设置，支持字号、字体、粗细、颜色及 Dynamic Type。导航提供普通标题、大标题、副标题与按钮四种角色；标签提供普通态和选中态的文字及图标颜色。标签图标可使用 SF Symbol、bundle 资源图片或 UIImage，并可在运行时替换。

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
        screen.navigation.trailingActions = [
            NavigationAction(id: "save", title: "保存", priority: 20, handler: { })
        ]
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

样式同时应用到系统的 stacked、inline、compact inline 三种布局，以及标准和滚动边缘 Appearance。当前接口配置整个标签栏的普通 / 选中态；每个标签分别提供自己的标题和图标。过大的标签文字仍可能按系统栏位规则截断或紧凑化。

`normalIconColor` / `selectedIconColor` 作用于可着色的模板图标，文字颜色可以分别配置。明确配置颜色时，SDK 按当前 traits 生成对应颜色的图标，兼容原生栏位未采用未选中 tint 的情况。使用 `.alwaysOriginal` 的彩色 UIImage 保留自身颜色。

## 默认值、继承与恢复

```swift
navigation.navigationStyle = ShellNavigationStyle(
    title: ShellTextStyle(size: 20, weight: .semibold, color: .systemBlue)
)

// 页面不设置 style 时，继承 navigation.navigationStyle。
// 页面不设置 tabBarStyle 时，继承 tabs.tabBarStyle。
```

`screen.navigation.style = nil` 与 `screen.tabBarStyle = nil` 继承对应容器配置。显式设置空的 `ShellNavigationStyle()` 或 `ShellTabBarStyle()` 跳过 SDK 容器样式，使用宿主原始 / 系统外观。

页面样式是整份覆盖值，其中 font 或 color 为 nil 的字段保留 UIKit 值。需要只修改容器样式中的一个字段时，先复制容器样式，再修改字段并赋给页面。

修改页面状态后调用 `refreshScreenConfiguration()`；修改容器的 `navigationStyle` 或 `tabBarStyle` 会刷新当前页面。内容和导航栈不会因此重新创建。样式与图片 / 动图 / MP4 / HTML 背景共同应用，切换背景时不会清除字体和颜色。

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

更新发生在原有 `UITabBarItem` 上，保留标签控制器、当前选中项、各标签的导航栈和业务输入。ID 必须是初始化时唯一的 `ShellTab.id`；找不到 ID 或对应控制器已从容器移除时返回 false，不修改其他标签。

`tabItemConfiguration(for:)` 返回当前条目配置，可复制修改后再整体更新。配置是完整替换：`selectedIcon = nil` 表示选中时采用普通图标；`icon = nil` 清除普通图标。稳定 ID、tag 和可访问性标识不会随标题变化而变化。兼容属性 `ShellTab.symbol` 对自定义图片返回空字符串，新代码可读取 `ShellTab.item.icon`。

所有样式和更新入口均在 `@MainActor` 上使用，不修改全局 `UIAppearance`，也不访问私有栏位视图。

## Demo 与验证

Demo 首页“栏位字体与图标”可调整导航字号 / 颜色、标签字号 / 颜色，以及 SF Symbol、资源图和保留原色的 UIImage 图标。支持普通 / 选中图标对照、恢复系统配置和详情页输入状态检查。

实际执行数量、运行环境、截图及手机安装结果见 [验证记录](Implementation-Status.md)。旧版 OS 和 iPad / Duo 全部布局仍按 [测试规划](Demo-Test-Plan.md) 单独验收；公开 API 编译通过不等同于所有系统姿态都已运行。
