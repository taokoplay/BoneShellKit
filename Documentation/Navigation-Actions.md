# 导航动作与自适应栏位

本文适用于 **v0.10.0**。导航图片图标、动作角色、轴向偏好及系统动作布局自此版本提供，固定版本 v0.9.1 不包含。最低部署目标仍为 iOS 15，编译使用 Xcode 27.1。

## 一次声明，按容器环境呈现

`NavigationAction` 描述动作语义；`BoneNavigationController` 提供系统容器；UIKit 决定原生栏位的位置和轴向。业务页面根据当前状态声明动作，无需判断 Duo 设备型号。

| 环境 | 布局与溢出 |
| --- | --- |
| iOS 27+、导航解析为 `.system` | 全部唯一动作提交给原生分组；UIKit 按空间、优先级和轴向安排，使用系统溢出菜单 |
| iOS 27.1+ 原生导航 | 额外映射 `axisBehavior`；实际是否竖排仍由系统姿态与容器环境决定 |
| iOS 15–26 原生导航 | 保留 SDK 按可用宽度、字体与优先级选择按钮及 `UIMenu` 的兼容路径 |
| `.classic` 导航 | 保留 SDK 横向布局与宽度预算；经典模式继续禁用系统竖向栏位 |

`.automatic` / `.capsule` 在新版系统上使用原生导航，因此符合上表的原生条件。标签栏独立 dock 的适配不在本次导航能力范围内。

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
        screen.navigation.leadingActions = [
            NavigationAction(id: "close", title: "关闭", symbol: "xmark",
                             role: .cancellation) { [weak self] in
                self?.dismiss(animated: true)
            }
        ]
        screen.navigation.trailingActions = [
            NavigationAction(id: "bookmark", title: "收藏",
                             icon: .asset("Bookmark", bundle: .main),
                             priority: 10, axisBehavior: .verticalPreferred) { },
            NavigationAction(id: "save", title: "保存", symbol: "checkmark",
                             priority: 20, role: .confirmation) { }
        ]
    }
}
```

示例资源 `Bookmark` 和保存 / 收藏业务由宿主提供。修改页面状态后调用 `refreshScreenConfiguration()`，保留业务内容和导航栈。

## 角色、优先级和轴向

| 字段 | 值 | 行为 |
| --- | --- | --- |
| `role` | `.normal`（默认） | 保留 `leadingActions` / `trailingActions` 指定的位置 |
| `role` | `.cancellation` | 放在 leading，保留原生返回按钮 |
| `role` | `.confirmation` | 放在 trailing；iOS 27+ 原生布局固定首个确认动作，后续确认动作仍可溢出；兼容路径优先保留确认动作 |
| `priority` | 任意 `Int`，默认 `0` | 同角色下较大的值优先保留；原生映射为 `UIBarButtonItemVisibilityPriority`，不以此重排声明顺序 |
| `axisBehavior` | `.automatic`（默认） | 系统根据图标、文字及环境推断 |
| `axisBehavior` | `.horizontalOnly` | iOS 27.1+ 仅支持横向栏位；没有可用横向栏时不保证直接可见，可通过系统菜单访问 |
| `axisBehavior` | `.verticalPreferred` | iOS 27.1+ 允许横向及竖向，在两者均存在时优先竖向 |

轴向偏好在旧系统可声明但不会调用不可用的 UIKit API。优先竖向不是强制竖排；应同时提供合适图标和标题。图标与文字互相切换、或文字承载关键信息时，应选择稳定的横向行为。

原生动作采用单动作固定分组，保持可在系统菜单中访问。首个确认操作单独放入 `pinnedTrailingGroup`，避免将多个操作固定在不可溢出的同一组。返回动作继续由系统导航栈管理。

## 状态、身份与诊断

同一页面中 ID 必须稳定且唯一；重复 ID 保留第一次声明。按 ID 复用 `UIBarButtonItem` 与原生分组。尺寸变化只更新布局；显式刷新后旧动作表示会执行同 ID 的最新有效回调，被禁用或移除的动作不会继续执行旧回调。

| 只读属性 | 含义 |
| --- | --- |
| `usesSystemNavigationActionLayout` | 是否处于 iOS 27+ 的原生动作布局路径；不表示当前栏位已经竖排 |
| `visibleActionIDs` | SDK 直接提交到栏位的候选 ID；系统布局下包含所有唯一动作，不能推断实际可见性 |
| `overflowActionIDs` | SDK 预先放入菜单的 ID；系统布局下为空，UIKit 自己折叠的动作不在此数组中 |

实际可见性、菜单可达性与触控范围需要通过运行中的 UI 验证。`toolbarVerticalEdge` 描述系统偏好边缘，也不是实际竖排状态标志。

## 范围与验收

本阶段提供标准动作、自定义图片、角色及轴向偏好。任意自定义 UIView、加载 / badge 声明、菜单树和自定义经典竖向 renderer 仍未提供。

Demo“导航栏”页提供符号 / 本地图片 / UIImage 与自动 / 仅横向 / 优先侧边切换；“导航与多按钮”页用于观察优先级及实际溢出。已执行的设备、用例与截图分别记录在 [实现与验证记录](Implementation-Status.md)，不以 API 编译通过代替 Duo 全姿态验收。
