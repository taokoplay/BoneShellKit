# SDK 当前范围与后续规划

本文以 **v0.12.0 / Demo 0.12.0（Build 1）** 为当前接口范围。导航动作强制显示策略自 v0.12.0 提供，NavButton、导航标题视图和标签栏整项自定义视图自 v0.11.0 提供；导航图片、角色、轴向偏好及系统动作布局自 v0.10.0 提供；标签文字显示策略自 v0.9.0 提供。接入从 [README](../README.md) 开始，已执行范围见 [验证记录](Implementation-Status.md)。完整设计设想保留在 [归档草案](Archive/Design-Draft.md)，其中的拟定类型不属于当前公开 API。

导航动作的完整用法及兼容边界见 [导航动作与自适应](Navigation-Actions.md)。

## 1. 当前架构

BoneShellKit 是一个 UIKit 优先的 Swift Package，提供单一 `BoneShellKit` library，最低部署目标 iOS 15，使用 Swift 5 语言模式、tools version 5.9，无第三方依赖。当前源码含 UIKit 26 / 27.1 API，已验证工具链为 Xcode 27.1；部署目标不等于最低编译 SDK。

```text
宿主 UIWindowScene / UIWindow
└── BoneTabBarController（可选）
    ├── BoneNavigationController → BoneViewController
    └── BoneNavigationController → BoneViewController

页面声明：ScreenConfiguration + NavigationAction
目的地声明：ShellTab + ShellTabItemConfiguration
呈现：UIKit 原生栏位 / SDK 经典栏位 / 兼容胶囊 / 原生 dock
背景：独立区域或容器共享画布 → 图像缓存与动态播放预算
```

宿主创建根容器、提供业务数据和路由；SDK 不提供全局根控制器单例或业务路由系统。`BoneSplitViewController(primary:detail:)` 封装原生双栏，可用于宿主声明的列表 / 详情；选中项、编辑数据与同步仍由宿主管理。

实际源码集中于 `Sources/BoneShellKit/`，并有 `Backgrounds/`、`Classic/`、`Capsule/`、`Accessory/` 子目录；不存在草案中的 `Adapters/`、全局配置上下文或独立 SwiftUI 产品。

## 2. 已有公开接口

| 入口 | 当前职责 |
| --- | --- |
| `BoneViewController` | `contentView`、页面配置、一次性内容构建、显式刷新、主滚动视图注册 |
| `ScreenConfiguration` / `NavigationConfiguration` | 页面内容边界、键盘避让、栏位覆盖、导航标题 / 操作 / 样式 / 背景、标签样式与背景 |
| `BoneNavigationController` | 原生导航栈、容器级模式 / 样式 / 背景、经典导航表面及安全区恢复 |
| `BoneTabBarController` / `ShellTab` | 目的地、独立导航栈、模式 / 样式 / 背景、条目更新和附加动作 |
| `ShellTabItemConfiguration` / `ShellTabIcon` / `ShellTabSelectedIconMode` | 标题、普通 / 选中图标、选中策略；支持[整项自定义视图](Bar-Presentation.md#普通标签的自定义视图) |
| `ShellTabBarAccessory` | 标签栏两侧动作，不参与目的地选中；可[提供完整展示视图](Bar-Presentation.md#自定义附加按钮) |
| `BoneSplitViewController` | 原生 `.doubleColumn` 分栏及主 / 详情导航包装 |
| `ShellTextStyle` / `ShellNavigationStyle` / `ShellTabBarStyle` | 文字和图标属性，支持按当前 traits 解析字体与颜色 |
| `ShellMaterial` / `ShellGlassView` | SDK 自有表面的材质选择与能力降级 |
| `ShellBackgroundConfiguration` / `ShellBackgroundView` | 图片、动图、视频、HTML、海报、叠加色、状态与生命周期 |
| `ShellBackgroundCache` / `ShellBackgroundPlaybackBudget` | 预取、缓存控制 / 统计、按 Scene 分配动态播放名额 |

`buildContent(in:)` 只构建一次。`refreshScreenConfiguration()` 会从新的默认配置重新调用 `configureScreen(_:)`，更新布局、栏位和背景；它不会重建业务内容。

## 3. 默认值与覆盖规则

| 设置 | SDK 默认 | Demo 行为 |
| --- | --- | --- |
| 标签栏 `barPresentation` | `.system` | 启动时设为 `.automatic` |
| 导航 `barPresentation` | `nil`，继承标签容器；独立导航使用 `.system` | 导航设置页可改为继承 / 系统 / 经典 |
| 页面 `barPresentation` | `nil`，继承容器 | 页面可显式覆盖当前管理的两处栏位 |
| 页面内容边界 | `.safeArea` | Demo 主列表已注册为主滚动视图 |
| `avoidsKeyboard` | `false` | 表单 / 详情页按需开启 |
| `floatingTabBarFadeHeight` | 80 pt，0 关闭 | 浮动胶囊下的列表展示渐隐 |
| 背景组合 | `.independent` | 背景页“全部”使用 `.unified`，“分区”使用独立背景 |
| 动态背景预算 | 每 Scene 1 个；进程统一上限可设为 0–3 | 背景页选择 1 或 3 个 |
| 页面样式 | `nil`，继承对应容器 | 设置页提供整份样式覆盖及恢复默认 |

当前没有 App → Scene → 容器 → 页面逐字段合并的通用配置层。页面样式是整份覆盖：`nil` 继承容器，显式空样式恢复宿主 / 系统值；要局部继承应先复制容器样式再修改字段。详见 [样式](Bar-Styling.md) 与 [背景的 nil / none 规则](Backgrounds.md#独立配置与默认值)。

### 0.9.0 新增：标签文字显示策略

以下 API **自 v0.9.0 提供，v0.8.0 不包含**：

| 接口 | 声明与默认值 |
| --- | --- |
| `ShellTabLabelDisplayMode` | `String`、`CaseIterable`、`Sendable` 枚举；`.always`、`.never`、`.selectedOnly`、`.unselectedOnly` |
| `ShellTabBarStyle.labelDisplayMode` | 非可选；初始化器新增参数，默认 `.always` |
| `ShellTabItemConfiguration.labelDisplayMode` | 可选；初始化器新增参数，默认 `nil`，继承当前生效样式 |
| `ShellTab` 两种初始化器 | 在 `root:` 前新增 `labelDisplayMode: ShellTabLabelDisplayMode? = nil` |

全栏使用 `tabs.tabBarStyle.labelDisplayMode = .selectedOnly`。页面 `screen.tabBarStyle` 继续整份覆盖，包含该字段；单个条目用 `configuration.labelDisplayMode` 覆盖当前样式，设回 `nil` 恢复继承。策略依据当前选中项决定栏上的可见文字；配置中的语义 `title` 保留，隐藏时提供无障碍名称并使图标居中。原生“更多”按钮跟随整栏策略，溢出目的地名称保留。实现覆盖原生、经典、兼容胶囊与原生 dock；文字策略单独验证，不纳入 0.8 的历史通过结论。示例见 [样式说明](Bar-Styling.md#标签文字显示策略)。

## 4. 栏位与操作的真实实现

`ShellBarPresentation` 的四种请求与运行系统分开：

| 请求 | iOS 26+ | iOS 15–25 |
| --- | --- | --- |
| `.automatic` | 原生胶囊标签、系统导航 | 经典标签、经典导航 |
| `.classic` | SDK 经典标签与导航 | SDK 经典标签与导航 |
| `.capsule` | 原生胶囊标签、系统导航 | SDK 胶囊标签、经典导航 |
| `.system` | UIKit 原生呈现 | UIKit 原生呈现 |

原生胶囊配置附加动作时，SDK 使用独立 `UITabBar` 与外侧圆按钮组成 dock；显式 `.system` 在 iOS 26+ 使用 `UITabAccessory` 槽位，旧系统使用拦截选择的原生 tab item。经典栏的动作位于栏内，兼容胶囊的动作位于外侧。附件默认是动作模型，也可以通过 `customContent` 提供整项自定义视图。

`NavigationAction` 保留原有字段，v0.10.0 新增 `icon`、`role`、`axisBehavior`，v0.11.0 新增可选 [NavButton](Navigation-Actions.md#自定义导航动作)，v0.12.0 新增 `visibility`。iOS 27+ 原生导航提交全部唯一动作（显式编组时共享承载项），系统负责溢出；经典及 iOS 15–26 使用宽度预算。重复 ID 取首个，按 ID 复用，刷新后调用最新的有效回调。尚未提供 `additionalOverflowItems` 声明、加载态、导航 badge 或任意菜单树接口。

SDK 渲染的标签目的地超过五个时显示前四个与“更多”，后续目的地由 action sheet 选择；原生 `.system` 交给 `UITabBarController`。当前没有 `UITabGroup` 或 SDK 目的地侧栏模型。

模式切换保留原生容器、控制器身份、导航栈、选中项和输入；经典栏的安全区贡献单独跟踪，退出或页面出栈时恢复。详见 [栏位模式](Bar-Presentation.md)。

## 5. 内容、背景与材质

- 固定内容默认遵循四边安全区。注册主滚动视图后，浮动标签栏允许视口延伸到底部，通过系统滚动内边距保证末项可达；SDK 不覆盖宿主的 `contentInset`。
- 底部渐隐作用于业务 `contentView` 的透明度遮罩，避开栏位控件；尊重宿主已有遮罩。键盘缩短视口或退出浮动模式后移除渐隐。
- 键盘避让使用 `UIKeyboardLayoutGuide`，明确不跟随未停靠键盘；iOS 15–16 有兼容分支。浮动 / 分离键盘、硬件键盘和编辑保护没有完整专项支持或验收承诺。
- 背景默认三处分区；`.unified` 需要非空页面背景，在当前容器中共享一份完整画布、时间线和动态播放名额。同配置切页可复用媒体；不同容器 / Scene 不共享播放器。
- 图像使用后台降采样、尺寸桶、请求合并和内存缓存；动态媒体受可见性、Scene、辅助设置、电量和名额约束。远程资源没有完整持久离线缓存能力。
- `ShellGlassView` 提供自动、系统默认、原生玻璃、仿玻璃、实色五种请求。材质作用于 SDK 管理的表面，不是系统菜单、键盘和整个 App 的统一换肤。

详细资源 API、内部缓存策略与验证边界见 [多媒体背景](Backgrounds.md)。

## 6. 当前限制与尚未实现的设计

| 项目 | 当前边界 / 后续工作 |
| --- | --- |
| 原生 dock | 非选中文字最终颜色受 UIKit 合成影响；原生栏位的滚动收起联动需单独适配 |
| 原生栏位轴向 | iOS 27.1 的经典模式禁用自动竖向栏位，其余转交系统；不是自定义轴向布局引擎 |
| App / Scene 配置 | 没有 `BoneShell.configure`、`BoneShellContext`、通用主题或分层配置解析器 |
| 旧页面与 SwiftUI | 没有 `ScreenShellAdapter` / 通用 adapter；没有 `BoneShellSwiftUI` 产品。复用现有 UIKit 导航容器不等于 adapter 已完成 |
| 导航动作扩展 | 已提供图片、动作角色、轴向偏好、系统分组、NavButton、自定义标题视图和相容按钮组内间距。加载 / 选中 / badge 和业务菜单树仍待设计 |
| 标签组织 | 无 SDK 侧栏、目的地分组、可见性规则或任意品牌布局 renderer API |
| 状态与编辑保护 | 保留既有控制器和输入；没有未保存编辑确认、受控离开协议或业务状态持久化 |
| iPad / Duo | 已有通用 bounds / safe-area / traits 与原生双栏；无 Duo 姿态、铰链、保留区域、双屏或专用栏位 API |
| 多 Scene | Demo 会为每个 Scene 建根容器，背景预算按 Scene 分组；完整多窗口隔离专项未执行 |
| 测试与性能 | 旧版 runtime、完整辅助字号 / RTL、浮动键盘、APNG 独立素材、远程资源端到端和 Instruments 测量仍待补齐 |

## 7. 后续实施与验收顺序

1. 补齐当前已声明能力的运行矩阵：iOS 15–25、iPad 宽 / 窄窗口、RTL、辅助设置与键盘，分别保存设备证据。
2. 对原生 dock 的系统颜色边界和滚动收起联动做专项适配，不用属性值或静态计数代替画面核对。
3. 单独设计 adapter、导航分组 / 菜单模型、目的地侧栏与编辑保护，再增加对应公开 API、Demo 和测试。
4. 有实际宿主需求后推进 App / Scene 分层配置、SwiftUI 桥接与 Duo 专项，保持与业务路由、数据库和其他 Bone SDK 的依赖边界。
5. 1.0 发布前，用真实运行矩阵、视觉证据与性能数据收敛支持声明。当前未对这些后续工作承诺工期。

[Demo 与测试说明](Demo-Test-Plan.md) 保留 D01–D15 场景追踪和 T01–T37 验收目标；规划 ID、现有 XCTest 方法数量和实际通过数量分别统计。历史设计细节见 [完整草案](Archive/Design-Draft.md)，历史版本执行记录见 [0.1–0.6 归档](Archive/Implementation-History.md)。
