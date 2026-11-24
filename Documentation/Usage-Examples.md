# SDK 方法说明

适用于 **v0.12.1**。导航动作、NavButton、Duo 侧栏样式、按钮材质、标题视图和标签栏整项自定义视图均包含在当前接口范围。导航动作强制显示策略自 v0.12.0 提供，iOS 26 共享玻璃和 NavButton 返回恢复自 v0.12.1 提供。下面按类型列出 SDK 的业务接入方法、参数、返回值和用途；可设置的属性见 [字段中文说明](API-Reference.md)。使用时导入 `UIKit`、`BoneShellKit`，并在主线程 / `@MainActor` 调用。

## 页面：BoneViewController

| 方法 | 参数 / 返回值 | 中文说明 |
| --- | --- | --- |
| `BoneViewController()` | 返回页面控制器 | 创建一个 SDK 页面，通常通过子类使用 |
| `configureScreen(_ screen: inout ScreenConfiguration)` | 可修改的页面配置，无返回值 | **子类重写**：设置导航标题、按钮、内容位置、键盘避让和背景 |
| `buildContent(in contentView: UIView)` | 业务内容容器，无返回值 | **子类重写**：在提供的视图中添加业务内容，SDK 对同一页面实例构建一次 |
| `refreshScreenConfiguration()` | 无参数、无返回值 | 页面状态变化后调用，重新应用配置，保留业务视图与导航栈 |
| `registerPrimaryScrollView(_ scrollView: UIScrollView)` | 主滚动视图，无返回值 | 注册列表或滚动视图，让 SDK 处理栏位避让、滚动内边距策略和底部渐隐 |

`configureScreen(_:)` 每次从默认配置重新生成，可能被多次调用；需要保留的设置应在此重复声明。业务内容只放在 `buildContent(in:)` 中创建。

## 导航容器：BoneNavigationController

| 方法 | 参数 / 返回值 | 中文说明 |
| --- | --- | --- |
| `BoneNavigationController(rootViewController:)` | 根页面 `UIViewController` → 导航容器 | 创建带导航栏的容器 |
| `pushViewController(_:animated:)` | 目标页面 `UIViewController`、是否动画 `Bool`；无返回值 | 打开下一页，沿用原生导航栈，并预取目标页背景 |
| `popViewController(animated:)` | 是否动画 `Bool` → `UIViewController?` | 返回上一页，返回被移出的页面；不能返回时为 `nil` |

## 标签容器：BoneTabBarController

| 方法 | 参数 / 返回值 | 中文说明 |
| --- | --- | --- |
| `BoneTabBarController(tabs:)` | `[ShellTab]` → 标签容器 | 创建标签栏；普通 root 自动包装成 SDK 导航容器，已有导航容器复用 |
| `tabItemConfiguration(for:)` | 标签 ID `String` → `ShellTabItemConfiguration?` | 读取标签当前配置；标签不存在或已移除时返回 `nil` |
| `updateTabItem(id:configuration:)` | 标签 ID `String`、完整条目配置 → `Bool` | 更新标题、图标和文字策略；成功返回 `true`，保留当前选中项、页面与导航栈 |

`ShellTab.id` 必须在同一容器中唯一。更新单个字段时，先读取配置、修改字段，再用 `updateTabItem` 写回。

## 分栏容器：BoneSplitViewController

| 方法 | 参数 / 返回值 | 中文说明 |
| --- | --- | --- |
| `BoneSplitViewController(primary:detail:)` | 主页面、详情页，均为 `UIViewController` → 分栏容器 | 创建双栏，普通页面自动包装为 SDK 导航容器；默认并排显示，折叠时保留详情列在顶部 |

主列表选中项、详情数据和详情替换由宿主管理，使用 UIKit 的列管理与导航接口。

## 配置对象的创建方法

初始化参数的默认值和中文含义见 [可设置字段](API-Reference.md)。

| 创建方法 | 中文说明 |
| --- | --- |
| `ScreenConfiguration()` | 创建页面默认配置，通常由 SDK 创建后传入页面配置方法 |
| `NavigationConfiguration()` | 创建导航默认配置 |
| `NavigationAction(id:title:symbol:priority:visibility:isEnabled:role:axisBehavior:handler:)` | 创建文字或 SF Symbol 动作；`visibility: .always` 可要求动作保留在导航栏；role / axisBehavior 自 v0.10.0 增加，有兼容默认值 |
| `NavigationAction(id:title:icon:priority:visibility:isEnabled:role:axisBehavior:handler:)` | v0.10.0+ 图片动作；`visibility` 自 v0.12.0+ 提供；icon 参数必传，可为 nil，ID / 标题 / 点击回调必填；完整示例见 [导航动作](Navigation-Actions.md) |
| `NavigationAction(id:title:navButton:icon:priority:visibility:isEnabled:role:axisBehavior:handler:)` | v0.11.0+ 创建可按横栏 / 侧栏分别呈现的 NavButton；SDK 使用 cluster 作为系统 item 的自定义承载，confirmation 保留语义优先级但使用自定义按钮外观；`visibility` 自 v0.12.0+ 提供 |
| `ShellTextStyle(font:color:scalesWithDynamicType:)` | 使用 UIFont 设置字体、文字颜色和动态字号 |
| `ShellTextStyle(size:weight:color:scalesWithDynamicType:)` | 使用字号与字重创建系统字体样式，字号必须有限且大于 0 |
| `ShellNavigationStyle(title:largeTitle:subtitle:buttons:)` | 创建导航栏各文字角色的样式 |
| `ShellTabBarStyle(normal:selected:normalIconColor:selectedIconColor:labelDisplayMode:)` | 创建标签栏普通态、选中态及文字显示样式 |
| `ShellTab(id:title:symbol:selectedIconMode:labelDisplayMode:root:)` | 使用 SF Symbol 创建标签；ID、标题、图标名称和 root 必填 |
| `ShellTab(id:title:icon:selectedIcon:selectedIconMode:labelDisplayMode:root:)` | 使用图标配置创建标签，可设置独立选中图；ID、标题、普通图标和 root 必填 |
| `ShellTab(id:item:root:)` | 从完整条目配置创建标签 |
| `ShellTabItemConfiguration(title:icon:selectedIcon:selectedIconMode:labelDisplayMode:)` | 创建用于更新标签的完整展示配置，标题必填 |
| `ShellTabBarAccessory(id:icon:title:position:isEnabled:accessibilityLabel:handler:)` | 创建标签栏附加按钮；ID、图标、位置和点击回调必填 |
| `ShellBackgroundConfiguration(source:poster:overlayColor:fallbackColor:contentMode:transitionDuration:)` | 创建背景配置，媒体来源必填 |
| `ShellMaterialResolution(requested:resolved:reason:)` | 创建材质结果描述；该初始化器本身不检测系统能力 |

自定义标签使用 `ShellTabItemConfiguration(title:customContent:)`；自定义动作使用 `ShellTabBarAccessory(id:customContent:position:isEnabled:accessibilityLabel:handler:)`。两者都接收完整 `UIView`，不要求备用图标。参见[自定义标签](Bar-Presentation.md#普通标签的自定义视图)与[自定义附加按钮](Bar-Presentation.md#自定义附加按钮)。


## 背景视图：ShellBackgroundView

| 方法 | 参数 / 返回值 | 中文说明 |
| --- | --- | --- |
| `ShellBackgroundView(frame:)` | `CGRect = .zero` → 背景视图 | 创建不接收触摸的背景视图；省略 frame 可直接使用 `ShellBackgroundView()` |
| `apply(_ configuration: ShellBackgroundConfiguration?)` | 背景配置或 `nil`，无返回值 | 设置背景；传 `nil` 清除配置并释放媒体 |
| `setPlaybackActive(_ active: Bool)` | 是否允许播放，无返回值 | 激活或暂停动态背景；实际播放还受可见性、系统状态和播放名额限制 |
| `stopAndRelease()` | 无参数、无返回值 | 清除配置、停止播放并释放媒体，再次使用需重新应用配置 |

`BoneViewController` 自动管理背景生命周期。直接使用背景视图时，宿主负责在显示 / 离开时激活和暂停。

## 图片缓存：ShellBackgroundCache

以下均为静态方法。

| 方法 | 参数 / 返回值 | 中文说明 |
| --- | --- | --- |
| `prefetch(_:targetSize:scale:traits:)` | 背景配置、区域尺寸 `CGSize`、像素比例 `CGFloat`、外观 `UITraitCollection? = nil`；无返回值 | 预取图片、动图和海报；区域尺寸单位为 pt，不提前创建视频播放器或网页 |
| `removeAll()` | 无参数、无返回值 | 清空缓存并取消待完成请求，不移除视图已显示的图片 |
| `resetStatistics()` | 无参数、无返回值 | 重置请求、命中和解码累计计数，不取消任务、不清缓存 |

## 播放预算：ShellBackgroundPlaybackBudget

| 静态方法 | 参数 / 返回值 | 中文说明 |
| --- | --- | --- |
| `activeCount(in:)` | `UIWindowScene? = nil` → `Int` | 查询正在播放的背景数量；不传 Scene 时统计全部 Scene |

播放数量上限通过 `maximumActivePerScene` 属性设置，默认每个 Scene 为 1，支持 `0...3`。

## 材质视图：ShellGlassView

| 方法 | 参数 / 返回值 | 中文说明 |
| --- | --- | --- |
| `ShellGlassView(material:)` | `ShellMaterial = .automatic` → 材质视图 | 创建业务材质视图，子视图添加到其 `contentView` |
| `refreshMaterial()` | 无参数、无返回值 | 根据系统能力和无障碍设置重新应用材质；修改 `material` 时会自动刷新 |

## 辅助方法

| 类型与方法 | 参数 / 返回值 | 中文说明 |
| --- | --- | --- |
| `ShellMaterials.resolve(_:supportsSystemGlass:reduceTransparency:)` | 请求材质、是否支持原生玻璃、是否减少透明度 → `ShellMaterialResolution` | 计算实际使用的材质和降级原因 |
| `ShellBarPresentation.resolved(supportsNativeCapsule:)` | 是否支持原生胶囊 `Bool` → `ShellBarPresentation` | 将 `.automatic` 解析为胶囊或经典模式，显式模式保持请求值 |
| `ShellTabLabelDisplayMode.isVisible(isSelected:)` | 是否选中 `Bool` → `Bool` | 判断该策略在当前选中状态下是否显示文字 |
| `ShellActionLayout.visibleIDs(actions:maximumVisible:)` | 动作列表、最大数量 `Int` → `[String]` | 先保留 `visibility: .always` 的动作，再按优先级挑选其余操作 ID；保持原声明顺序 |

UIKit 的生命周期、布局方法和协议回调按 UIKit 规则使用；重写 SDK 页面或容器的生命周期时调用 `super`。`init(coder:)` 用于 UIKit 解档，日常代码接入使用上表的创建方法。
