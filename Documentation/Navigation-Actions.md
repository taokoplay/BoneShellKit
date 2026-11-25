# 导航动作与自适应栏位

本文适用于 **v0.12.1**。导航动作强制显示策略自 v0.12.0 提供，iOS 26 导航共享玻璃、NavButton 返回恢复和自定义 confirmation 行为自 v0.12.1 提供，NavButton、Duo 侧栏样式、按钮材质及标题视图自 v0.11.0 提供，最低部署目标仍为 iOS 15，编译使用 Xcode 27.1。

## 一次声明，按容器环境呈现

`NavigationAction` 描述动作语义；`BoneNavigationController` 提供系统容器；UIKit 决定原生栏位的位置和轴向。业务页面根据当前状态声明动作，无需判断 Duo 设备型号。

| 环境 | 布局与溢出 |
| --- | --- |
| iOS 27+、导航解析为 `.system` | 全部唯一动作提交给原生分组；UIKit 按空间、优先级、可见性和轴向安排，`.always` 动作保留在栏位结构中 |
| iOS 27.1+ 原生导航 | 额外映射 `axisBehavior`；实际是否竖排仍由系统姿态与容器环境决定 |
| iOS 15–26 原生导航 | 保留 SDK 按可用宽度、字体、可见性与优先级选择按钮及 `UIMenu` 的兼容路径 |
| `.classic` 导航 | 保留 SDK 横向布局与宽度预算；经典模式继续禁用系统竖向栏位 |

`.automatic` / `.capsule` 在新版系统上使用原生导航，因此符合上表的原生条件。标签栏独立 dock 的适配不在本次导航能力范围内。

## 自定义导航动作

`ShellNavButton` 自定义的是**按钮而非整条导航栏**。`id`、菜单标题、无障碍名称、启用状态及回调仍由 `NavigationAction` 管理。未使用 `navButton:` 的动作保持原行为，标准项和自定义项可混排。

```swift
import UIKit
import BoneShellKit

@MainActor
final class EditScreen: BoneViewController {
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        let edit = NavigationAction(id: "edit", title: "编辑", navButton: .init(),
                                    icon: .systemSymbol("pencil")) { /* 编辑 */ }
        let share = NavigationAction(id: "share", title: "分享", navButton: .init(),
                                     icon: .systemSymbol("square.and.arrow.up")) { /* 分享 */ }
        let done = NavigationAction(id: "done", title: "完成", navButton: .init(
            normal: .init(size: .preferred(CGSize(width: 72, height: 44)), effect: .liquidGlass),
            iPhoneDuo: .init(size: .preferred(CGSize(width: 44, height: 72)), icon: .systemSymbol("checkmark"))
        ) { /* 完成 */ }
        screen.navigation.trailingModules = [
            .group(NavigationButtonGroup(id: "editing", actions: [edit, share], itemSpacing: 8, material: .systemGlass)),
            .button(done)
        ]
    }
}
```

- **尺寸**：默认按文字、图片的逻辑尺寸（pt）或自定义视图拟合；`size` 指按钮外框，`iconSize` 指图标，`contentInsets` 指内部留白。小图不必拉伸到点击区域大小。在分配的空间内尽可能提供 44 × 44 pt 的不重叠点击区域。标题字号不参与按钮测量。
- **轴向与内容**：`Style.icon` 可为横栏与 iPhone Duo 分别指定图标，`iPhoneDuo` 样式只在实际侧边栏承载时生效。`axisBehavior.horizontalOnly` 关闭自动侧边栏迁移，`verticalPreferred` 允许并优先侧边栏。
- **模块顺序与间距**：`leadingModules`、`trailingModules` 按声明顺序呈现。独立按钮使用 `.button`，多个按钮使用 `NavigationButtonGroup`；`itemSpacing` 控制组内间距，`NavigationConfiguration.moduleSpacing` 控制模块之间的期望间距。按钮组作为一个原子模块参与宽度预算、溢出和 Duo 位置计算。
- **材质**：组内按钮的按钮级 effect 自动解析为 `.none`，只使用 `NavigationButtonGroup.material`；独立按钮才使用自己的按钮材质。导航栏 `material` 仍负责整条导航栏背景。
- **自定义内容**：`ShellNavButton` 可提供尺寸、图标、iPhone Duo 样式和完整自定义 UIView。组内自定义内容不要再自行绘制第二层导航表面。
- **系统项与自定义项**：`navButton:` 的动作由 SDK 创建 `ShellNavButtonHost` 和 `ShellNavButtonCluster`，再把 cluster 作为 `UIBarButtonItem.customView`。SDK 不同时使用系统 item 的 `primaryAction`、标题或图标承载同一个自定义动作。宿主只需要提供 `NavigationAction.handler`。
- **确认动作**：`role: .confirmation` 仍参与原生优先级、固定位置和兼容宽度预算。自定义 confirmation 使用自定义按钮的文字与材质，不叠加 UIKit `.done` 的系统突出外观；未使用 `navButton:` 的 confirmation 继续使用系统 `.done` 样式。
- **系统玻璃**：`ShellMaterial.systemGlass` 保留 UIKit 的共享玻璃背景。不要通过 `hidesSharedBackground` 关闭玻璃，再在每个自定义按钮上重复绘制一层系统表面。
- **刷新与返回**：页面在 `viewWillAppear`、`viewDidAppear` 和布局变化时可能重新提交动作。SDK 按稳定 ID 复用 item、cluster 和按钮，并在 pop 完成后重新写入分组内容。宿主更新动作后仍需调用 `refreshScreenConfiguration()`。
- **iOS 15–26 宽度预算**：当 leading 没有动作时，兼容路径把可用侧向空间交给 trailing；当 trailing 没有动作时，把空间交给 leading。放不下的普通动作进入 `UIMenu`，确认动作按其角色优先保留。
- **整项 UIView**：可用 `.init(content: .custom(revision: 0, makeView: { MyView() }))` 替换按钮的全部视觉内容，工厂提供未挂载的视图。相同 ID 和内容版本复用，需更换内容时修改 `revision`。视觉内容不要再注册一套动作；栏上、辅助激活和溢出菜单均使用 `NavigationAction.handler`。

## 标题菜单与自定义按钮

可在 `configureScreen(_:)` 设置 `screen.navigation.titleView`，传入完整且可交互的 `UIView`。原生导航交给 `UINavigationItem.titleView` 承载，经典导航在返回键和两侧按钮之间布局。SDK 不向自定义标题叠加文字、副标题或大标题，也不代管按钮事件。

```swift
import UIKit
import BoneShellKit

@MainActor
final class SourcesController: BoneViewController {
    private lazy var sourceButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "全部来源"
        config.image = UIImage(systemName: "chevron.down")
        config.imagePlacement = .trailing
        config.imagePadding = 6
        let button = UIButton(configuration: config)
        button.showsMenuAsPrimaryAction = true
        button.menu = UIMenu(children: ["本地来源", "订阅来源"].map { name in
            UIAction(title: name) { [weak self] _ in
                self?.selectSource(name)
            }
        })
        return button
    }()

    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "来源" // 保留文字语义，例如下一级页面的返回标题。
        screen.navigation.titleView = sourceButton
    }

    private func selectSource(_ name: String) {
        sourceButton.configuration?.title = name
        refreshScreenConfiguration()
    }
}
```

- 每个页面持有独立的视图实例；首次提供时不要挂在其他父视图上，刷新时复用同一实例。通过内在尺寸、`sizeThatFits(_:)`、内部约束或初始宽度提供理想尺寸；实际大小以栏位空间为准。
- 标题内容自行处理触摸和无障碍。可以用 `UIButton.menu`，也可以用点击回调打开宿主自己的选源面板。返回键和两侧 `NavigationAction` 不受替换。
- 设回 `nil` 并刷新页面声明，恢复现有文字、副标题和 `usesLargeTitle`。只需要系统文字标题菜单时，iOS 16+ 的原生导航仍可使用 UIKit `navigationItem.titleMenuProvider`。
- 此接口替换的是内联标题。原生栏位的摆放由 UIKit 决定，不保证所有 iPad / Duo 竖栏姿态都有标题空间。

Demo：**示例 → 导航栏 → 标题内容 → 自定义**，点顶部标题选择来源。

## 图标与兼容接口

`symbol:` 初始化方式保持可用。新增 `icon:` 初始化方式，类型 `ShellNavigationIcon` 与 `ShellTabIcon` 共用实现：

- `.systemSymbol(String)`：系统符号。
- `.asset(String, bundle: Bundle)`：宿主或资源 Bundle 中的图片；普通资源图片默认采用模板着色，尊重显式资源渲染方式。
- `.image(UIImage)`：已有图片，保留其渲染模式；品牌原色可用 `.alwaysOriginal`。

`icon != nil` 时覆盖 `symbol`；显式图片无法解析时显示标题。将 `icon` 设回 `nil` 后恢复 `symbol`。标题始终保留用于菜单和无障碍，不应因栏上采用图标而清空。

```swift
import UIKit
import BoneShellKit

@MainActor
final class ActionsController: BoneViewController {
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.navigation.title = "编辑"
        let close = NavigationAction(id: "close", title: "关闭", symbol: "xmark",
                                     role: .cancellation) { [weak self] in
            self?.dismiss(animated: true)
        }
        let bookmark = NavigationAction(id: "bookmark", title: "收藏",
                                         icon: .asset("Bookmark", bundle: .main),
                                         priority: 10, axisBehavior: .verticalPreferred) { }
        let save = NavigationAction(id: "save", title: "保存", symbol: "checkmark",
                                    priority: 20, role: .confirmation) { }
        screen.navigation.leadingModules = [.button(close)]
        screen.navigation.trailingModules = [.button(bookmark), .button(save)]
    }
}
```

示例资源 `Bookmark` 和保存 / 收藏业务由宿主提供。修改页面状态后调用 `refreshScreenConfiguration()`，保留业务内容和导航栈。

## 角色、优先级、可见性和轴向

| 字段 | 值 | 行为 |
| --- | --- | --- |
| `role` | `.normal`（默认） | 保留 `leadingModules` / `trailingModules` 指定的位置 |
| `role` | `.cancellation` | 放在 leading，保留原生返回按钮 |
| `role` | `.confirmation` | 放在 trailing；iOS 27+ 原生布局固定首个确认动作，后续确认动作仍可溢出；兼容路径优先保留确认动作 |
| `priority` | 任意 `Int`，默认 `0` | 同角色下较大的值优先保留；原生映射为 `UIBarButtonItemVisibilityPriority`，不以此重排声明顺序 |
| `visibility` | `.automatic`（默认） | 允许兼容布局按空间与优先级将动作移入溢出菜单 |
| `visibility` | `.always` | 兼容布局保留动作；iOS 27+ trailing 动作放入 `pinnedTrailingGroup`，leading 动作使用最高可见性优先级 |
| `axisBehavior` | `.automatic`（默认） | 系统根据图标、文字及环境推断 |
| `axisBehavior` | `.horizontalOnly` | iOS 27.1+ 仅支持横向栏位；没有可用横向栏时不保证直接可见，可通过系统菜单访问 |
| `axisBehavior` | `.verticalPreferred` | iOS 27.1+ 允许横向及竖向，在两者均存在时优先竖向 |

轴向偏好在旧系统可声明但不会调用不可用的 UIKit API。优先竖向不是强制竖排；应同时提供合适图标和标题。图标与文字互相切换、或文字承载关键信息时，应选择稳定的横向行为。

原生动作采用单动作固定分组，保持可在系统菜单中访问。首个确认操作和 trailing 侧的 `.always` 动作放入 `pinnedTrailingGroup`，直接保留在栏位末端。leading 侧的 `.always` 动作使用最高可见性优先级。返回动作继续由系统导航栈管理。

## 状态、身份与诊断

同一页面中 ID 必须稳定且唯一；重复 ID 保留第一次声明。按 ID 复用 `UIBarButtonItem` 与原生分组。尺寸变化只更新布局；显式刷新后旧动作表示会执行同 ID 的最新有效回调，被禁用或移除的动作不会继续执行旧回调。

| 只读属性 | 含义 |
| --- | --- |
| `usesSystemNavigationActionLayout` | 是否处于 iOS 27+ 的原生动作布局路径；不表示当前栏位已经竖排 |
| `visibleActionIDs` | SDK 直接提交到栏位的候选 ID；系统布局下包含所有唯一动作，不能推断实际可见性 |
| `overflowActionIDs` | SDK 预先放入菜单的 ID；系统布局下为空，UIKit 自己折叠的动作不在此数组中 |

实际可见性、菜单可达性与触控范围需要通过运行中的 UI 验证。`toolbarVerticalEdge` 描述系统偏好边缘，也不是实际竖排状态标志。

## 范围与验收

v0.12.1 提供标准动作、强制显示策略、自定义图片、角色、轴向偏好、NavButton、自定义标题视图和 iOS 26 导航恢复行为。自定义 NavButton 的系统承载、confirmation 外观、共享玻璃和返回恢复规则见上文。加载 / badge 声明、菜单树和自定义经典竖向 renderer 仍未提供。

Demo“导航栏”页提供符号 / 本地图片 / UIImage 与自动 / 仅横向 / 优先侧边切换；“导航与多按钮”页用于观察优先级及实际溢出。已执行的设备、用例与截图分别记录在 [实现与验证记录](Implementation-Status.md)，不以 API 编译通过代替 Duo 全姿态验收。
