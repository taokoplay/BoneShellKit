# BoneShellKit：iOS 自适应应用骨架 SDK 规划

状态：规划稿 v0.8，已建立 SDK 与 Demo；0.2 增加三处多媒体背景，0.3 增加栏位字体、颜色与标签图标；0.4 增加跨三处的整体背景画布，0.5 增加系统 / 经典栏位类型，0.6 增加选中图标颜色 / 原图策略。本文同时保留后续目标和拟定接口，不表示全部能力已经实现；当前实现与执行结果见 [验证记录](Implementation-Status.md)，实际接入入口见 [README](../README.md)。

## 1. 命名与定位

**推荐名称：BoneShellKit。** 中文定位：Bone 自适应应用骨架套件。

Shell 指应用的外层骨架：页面容器、导航、标题、操作、标签栏与内容安全区。名称能够覆盖版本兼容和多设备适配，又能与已有 BonePopoverKit 保持一致。

| 备选名称 | 适用定位 | 判断 |
| --- | --- | --- |
| BoneShellKit | 应用骨架、导航、标签、页面容器与适配 | 推荐，边界清楚 |
| BoneAdaptiveKit | 更广泛的布局与设备适配基础设施 | 可选，但不突出页面容器 |
| BoneUIKit | 通用 UI 组件全集 | 范围太大，容易与 Apple UIKit 混淆 |
| BoneBaseKit | 通用底层基础库 | 不容易从名字判断用途 |

本次未进行商标、域名或包名称占用检索，以上是技术命名建议。

一句话目标：**业务页面声明“展示什么、有哪些操作”，BoneShellKit 根据当前窗口空间、系统能力和配置，决定“栏位放哪里、如何布局、使用何种材质”。**

## 2. 支持基线与本次核验

建议第一版最低支持 **iOS / iPadOS 15**，以 **Xcode 27.1 或以上**编译，使用 Swift Package 分发。部署目标与编译 SDK 分开管理：支持 iOS 15 运行，不表示能够用旧版 Xcode 编译所有新适配代码。

SDK UI 对象显式使用 `@MainActor`；配置与布局结果优先使用值类型。SDK 可采用 Swift 6 语言模式，现有宿主可以保留 Swift 5 语言模式，由同一新工具链构建。此混合模式需在最小包阶段做集成编译验收。

当前已经核实：

- 本机工具链为 Xcode 27.1，Build 27A9275，安装有 iPhoneSimulator27.1 SDK。
- 当前 Shorthand 工程配置为 `IPHONEOS_DEPLOYMENT_TARGET = 15.0`、`SWIFT_VERSION = 5.0`、`TARGETED_DEVICE_FAMILY = 1`。
- 本地 UIKit SDK 与 Apple 在线文档均提供 iOS 26 的 `UIGlassEffect`，以及 iOS 27.1 的竖向栏位相关 API。
- 最小 Apple API 探针通过 `swiftc -typecheck`，目标为 `arm64-apple-ios15.0-simulator`。探针覆盖普通栏位 Appearance、iOS 16 分组与溢出、iOS 26 玻璃、iOS 27.1 栏位轴向与保留区域类型。
- 探针只证明所检查的 Apple API 名称、类型与 availability 保护可编译。SDK、Demo、自动化测试及真机安装的后续实际结果，以 [验证记录](Implementation-Status.md) 为准。

**宿主需主动开启 iPad / Universal 支持。** SDK 不修改 App 的设备族、场景声明和发布配置；仅导入 SDK 无法使当前 iPhone-only App 自动成为完整 iPad App。

## 3. 自动处理的范围

| 框架统一负责 | 页面提供的信息 |
| --- | --- |
| 系统版本分支、公开 API 兼容与降级 | 页面内容及业务事件 |
| 导航栏、标题、左右操作和工具栏的布局 | 标题、按钮语义、优先级与分组 |
| 标签栏、侧边栏及其安全区占位 | 顶层目的地与稳定标识 |
| 四边安全区、键盘避让及滚动视图边界协调 | 注册主滚动视图、选择内容延伸方式 |
| 栏位横向 / 竖向切换与操作溢出 | 自定义操作的紧凑表示和菜单表示 |
| 多栏容器的展开 / 折叠和状态保留 | 列表、详情、检查器等内容角色 |
| 主题、材质、无障碍与动效降级 | 个别页面或组件的覆盖配置 |
| 页面、导航和标签的独立媒体背景、预加载、缓存与可见播放预算 | 图片 / GIF / APNG / MP4 / HTML、海报、遮罩及回退色 |

“继承即可使用”适用于页面外层骨架。框架无法推断业务视图中任意固定 frame 应当如何重排，也无法自动决定哪些内容有业务上的主从关系。普通页面默认单栏；声明列表和详情后，才参与双栏适配。

## 4. 架构：薄基类 + 系统容器 + 策略组件

首版使用一个 Swift Package 和一个主要公开产品 `BoneShellKit`。内部按职责分目录，不急于拆成大量独立依赖。

```text
业务页面 / 已有页面适配器
              │
              ▼
 ScreenConfiguration + NavigationAction + ShellTab
              │
              ▼
       BoneShellContext（每个 Scene）
              │
       ┌──────┼──────────┐
       ▼      ▼          ▼
   能力检测  布局解析    材质解析
       └──────┼──────────┘
              ▼
       ResolvedShellConfiguration
              │
       ┌──────┴─────────┐
       ▼                ▼
 系统容器与系统栏位    自定义栏位渲染器
       └──────┬─────────┘
              ▼
        统一内容布局区域
```

建议内部职责：

| 组件 | 职责 |
| --- | --- |
| CapabilityResolver | 系统 API、运行环境与容器能力检测 |
| ConfigurationResolver | 合并全局、Scene、容器、页面、组件配置 |
| LayoutResolver | 解析窗口空间、尺寸类别、安全区与内容角色 |
| ActionResolver | 操作分组、排序、可见性与溢出 |
| MaterialResolver | 原生玻璃、默认材质、经典外观、仿玻璃及降级 |
| Backgrounds | 三处背景的异步解码、尺寸桶缓存、首帧 / 海报、播放预算与离屏释放 |
| ContentLayoutCoordinator | 内容区域、附加占位、键盘和滚动边界 |
| NavigationCoordinator | 页面配置切换、返回手势和交互转场协调 |
| StateCoordinator | 标签选择、导航栈、双栏选中项和布局变化状态 |
| Diagnostics | 输出请求值、实际结果和降级原因，支持 Demo 检查 |

这些是内部职责边界，不要求每项都成为公共协议或单独模块。

### 推荐公开类型

| 类型 | 作用 |
| --- | --- |
| `BoneShell` | App 默认配置入口 |
| `BoneShellContext` | 每个 Scene 的配置与运行上下文 |
| `BoneViewController` | 供普通页面继承的薄基类 |
| `BoneNavigationController` | `UINavigationController` 的封装 |
| `BoneTabBarController` | `UITabBarController` 的封装 |
| `BoneSplitViewController` | `UISplitViewController` 的封装 |
| `ScreenConfiguration` | 页面级骨架声明 |
| `ShellBackgroundConfiguration` / `ShellBackgroundSource` | 独立配置页面、导航和标签的多媒体背景 |
| `ShellBackgroundCache` / `ShellBackgroundPlaybackBudget` | 预取、缓存诊断与每 Scene 动态播放数量 |
| `NavigationAction` | 操作、菜单与可见性声明 |
| `ShellTab` | 顶层目的地声明 |
| `ShellBarPresentation` | 选择系统原生或 26 以下风格的经典导航 / 标签呈现 |
| `ShellTextStyle` / `ShellNavigationStyle` / `ShellTabBarStyle` | 字体、字号、颜色、Dynamic Type 与状态样式 |
| `ShellTabIcon` / `ShellTabItemConfiguration` | 普通 / 选中图标及运行时条目更新 |
| `ShellLayoutContext` | 当前内容可用空间与布局环境 |
| `BoneButton` | 使用同一主题和材质策略的通用按钮，可在后续版本加入 |

已有页面通过 `ScreenShellAdapter` 接入，避免必须更换所有页面父类。SwiftUI 通过后续可选 `BoneShellSwiftUI` 产品桥接，不作为首版 UIKit 核心的依赖。

## 5. 容器组织

普通标签型应用默认采用：

```text
UIWindowScene
└── BoneTabBarController
    ├── BoneNavigationController → 首页 → 详情 → 编辑
    ├── BoneNavigationController → 分类 → 列表 → 详情
    └── BoneNavigationController → 设置 → 子设置
```

列表详情型页面可以在某个标签内使用 `BoneSplitViewController`。容器组织由应用声明，SDK 负责展开与折叠；不得同时让标签侧边栏和分栏侧边栏重复展示同一组顶层目的地。

每个标签维护独立导航栈。标签切换、窗口变化和材质调整不得重建业务控制器、丢失输入或重置滚动位置。

不采用全局唯一根控制器单例作为架构前提。全局入口只提供默认配置，各 Scene 持有独立上下文与页面状态。

## 6. 配置层级与自动模式

建议提供三个独立配置维度：

| 维度 | 主要选项 | 说明 |
| --- | --- | --- |
| 布局策略 | `automatic`、`singleColumn`、`splitWhenPossible` | 决定内容组织，双栏仍需声明内容角色 |
| 栏位渲染器 | `automatic`、`system`、`custom` | 决定谁绘制并管理栏位内容 |
| 材质策略 | 高版本策略 + 低版本策略 | 决定玻璃、默认材质或经典外观 |

标签展示另提供 `automatic`、`system`、`floating`、`sidebarWhenPossible`。配置为偏好，实际可用性由窗口空间与渲染器决定。

`automatic` 在容器建立时按容器配置与能力选择渲染器：默认优先系统；低版本明确要求仿玻璃而系统栏位无法兑现时，选择已验收的自定义实现。显式固定为 `system` 时，不可兑现的材质降级为系统默认，并返回原因。

页面 / 组件覆盖只能调整当前渲染器能支持的材质，不隐式更换整个容器的渲染器。若要求多个页面在原生玻璃与严格经典外观之间自由切换，应预先采用能满足两种材质的自定义容器策略，再切换其表面。渲染器本身的显式变更遵循第 11 节的容器级安全切换规则。

配置覆盖顺序为：

```text
SDK 默认 → App 默认 → Scene → 容器 → 页面 → 组件
                                      ↓
                        能力检查与无障碍约束
                                      ↓
                             实际解析结果
```

上层覆盖按字段合并，不能用一个新页面配置意外清空全部默认项。覆盖模型需区分“继承”“明确设置”和“恢复系统值”。减少透明度、减少动态效果等用户设置在解析末端生效，不能被业务强制覆盖。

### 自动决策流程

1. 从当前页面 / 容器读取 bounds、尺寸类别、四边安全区与所属 Scene，避免使用全局屏幕宽高。
2. 读取当前 OS 与可用公开 API；仅在 availability 分支内使用新能力。
3. 合并配置，并确认内容是否提供列表、详情等角色。
4. 解析单栏、多栏及标签展示偏好；空间不足时稳定收敛到可用布局。
5. 系统渲染模式下，让系统容器管理原生栏位轴向和占位；SDK 管理语义与配置。
6. 自定义模式下，由 SDK 结合安全区和可用保留区域管理栏位与占位。
7. 解析操作溢出和材质，生成可观察的实际结果。
8. 在布局变化和转场协调器中更新，保留控制器身份与业务状态。

不能只在启动时运行一次；窗口 resize、安全区变化、尺寸类别变化、用户辅助设置变化及页面转场都可能触发重新解析。合并同一帧内的更新，避免反复重建约束。

## 7. 普通 iPhone、iPhone Duo 与 iPad

**按可用空间和系统能力适配，不维护设备型号 / 分辨率白名单。** 尺寸类别负责主要布局分支，实际可用尺寸、组件最小空间与内容角色负责细化决策。`regular` 不等同于 iPad，也不代表一定适合双栏。

| 场景 | 自动模式建议行为 |
| --- | --- |
| 普通 iPhone 的紧凑窗口 | 单栏导航与系统标签展示；操作不足时进入溢出 |
| 普通 iPhone 横屏 | 按当前窗口和系统栏位行为调整，不强制当作 iPad |
| iPhone Duo 窄窗口 / 外屏 | 保持紧凑内容；采用系统在该姿态下提供的栏位布局 |
| iPhone Duo 宽窗口 / 内屏 | 有主从角色且空间足够时展开双栏；没有角色则保持合理宽度的单栏 |
| iPhone Duo 支持竖向栏位的姿态 | 系统容器自动管理侧边栏位；按钮提供图标、文本及轴向偏好 |
| iPad 的宽窗口 | 可使用标签侧边栏或列表详情双栏，遵循已声明的导航结构 |
| iPad 分屏 / 自由窗口的窄尺寸 | 折叠到紧凑布局，仍保留当前详情和返回路径 |
| 多窗口 | 每个 Scene 独立解析，不能共享“当前屏幕宽度”缓存 |

### iPhone Duo 专项

- 首版编译基线选择 Xcode 27.1，以包含当前公开的竖向栏位和保留区域 API；运行时仍做 `#available(iOS 27.1, *)` 保护。
- 默认使用 `UINavigationController`、`UITabBarController` 等容器提供的栏位。单独创建一个 `UITabBar` 放入自定义 Dock，不能等同于完整的容器级自动适配。
- UIKit 的 `axisBehavior` 和竖向栏位配置只在受支持版本使用；框架公开配置仍可由旧系统读取并降级。
- 每一条边的安全区分别处理；不能用左侧 inset 乘二计算可用宽度。
- 对超出常规内容安全区的自定义控件，使用公开保留区域信息进行避让，不猜测摄像头和折叠区域坐标。
- 原生竖向栏位默认保持系统行为。`preferredVerticalBarBehavior` 的退出属于稳定的界面设计选择，不随单页临时状态频繁切换。[R5]
- 不向业务层暴露“折叠多少度就搬一次按钮”这类默认策略；铰链驱动交互仅在有明确业务需求时另行扩展。

SDK 不承诺仅凭型号判断，让所有设备展示完全相同的栏位位置。系统自动模式保留平台的适配规则。

## 8. 导航栏、标题与多按钮

### 标题能力

支持普通标题、大标题、副标题、图标 / 标题组合及自定义标题视图。优先使用系统原生能力；旧版副标题可用受控的 `titleView` 实现，不反向修改系统私有子视图。

默认采用系统标题对齐。需要严格居中的自定义标题时，按两边实际预算分配可用空间，不能假设左右按钮等宽。按钮或文字变大时，标题可截断或移入内容头部，仍保留完整无障碍名称。

### 操作数据模型

每个 `NavigationAction` 至少提供：

- 稳定的 `id`、本地化标题、图标和无障碍描述。
- 语义角色：返回、关闭、主要操作、次要操作、破坏性操作。
- 布局偏好：`leading`、`trailing`、工具栏；内部使用方向语义，适配 RTL。
- 分组标识、可见性优先级、启用 / 加载 / 选中 / badge 状态。
- 触发行为或菜单；自定义视图还需提供紧凑表示和菜单表示。
- 可选轴向偏好：自动、仅横向、优先竖向；旧系统按可用布局降级。

左右两边均支持多按钮，数据模型不设固定个数。可见数量由空间决定，不能承诺任意多个按钮始终同时显示。

### 布局与溢出规则

1. 原生返回 / 关闭承担主要导航语义；push 页面优先保留系统返回按钮。
2. 页面附加 leading 操作时保留返回语义，不能无意替换系统返回项。
3. 高频主要操作优先显示；通常只保留一个不可轻易溢出的主要操作，避免大量 pinned 操作耗尽空间。
4. 同组操作一起布局；使用公开分组 API，避免负间距和固定空白占位。
5. 空间不足时，依次采用紧凑图标表示、收起低优先级组、移入溢出菜单；不压缩触控区域来塞入按钮。
6. 图标按钮保持完整标题，供 VoiceOver、菜单和系统的其他表示方式使用。触控目标默认至少 44 × 44pt。
7. 超长标题、大字体和竖向栏位均参与溢出计算；保留导航和重要提交操作的可达路径。
8. 极端小窗口无法容纳全部高优先级操作时，允许将业务操作移入可访问的菜单，并在诊断中说明；不绘制重叠控件，也不丢弃操作。

版本策略：

| 版本 | 实现依据 |
| --- | --- |
| iOS 15 | 公开左右按钮数组；SDK 预先筛选可见操作，并提供 `UIMenu` 溢出入口 |
| iOS 16–26 | 优先使用 item groups 和系统 overflow，额外操作并入 `additionalOverflowItems`，不再叠加第二个更多按钮 |
| iOS 27.0+ | 在支持位置映射公开的 `visibilityPriority` |
| iOS 27.1+ | 增加轴向偏好和竖向栏位压缩策略，保留系统溢出行为 |

同一侧不能混用互相覆盖的旧按钮数组与新 item groups。旧版预算计算只能使用公开尺寸和自定义表示的测量结果，采用保守预留；不读取系统私有栏位 frame。

## 9. 标签栏与自定义布局

标签声明包含稳定 `id`、标题、默认 / 选中图标、badge、内容控制器工厂和可见性规则。

支持系统式、浮动胶囊式与可用时的侧边栏式。系统模式依赖容器原生行为；品牌浮动 Dock 是独立的自定义模式，有自己的尺寸、选中态、键盘及无障碍处理。

自动模式优先使用系统栏位。有原生标签侧边栏能力时，可结合宽窗口与导航声明使用；旧系统如需侧边栏，使用分栏容器适配器，不调用不存在的新标签 API。顶层目的地过多时使用系统更多目的地 / 分组或侧边栏，不能无限压缩标签按钮。

助理入口、中央创建按钮等附加功能以可选 accessory 描述，不写死在标签控制器。当前项目的猫形助理、业务跳转和品牌图标由宿主注入。

固定底部位置是自定义模式的显式偏好。在原生自动模式下，不能承诺标签栏在所有设备和姿态都停留在底部。

### 0.3 已实现：字体、颜色与图标

`NavigationConfiguration.style` 与 `BoneNavigationController.navigationStyle` 设置标题、大标题、副标题及按钮的字体和颜色；标签通过 `ScreenConfiguration.tabBarStyle` / `BoneTabBarController.tabBarStyle` 设置普通与选中态的文字和图标颜色。UIFontMetrics 支持随字体类别缩放，也可以固定字号。

标签保留原有 `symbol:` 初始化，同时增加 SF Symbol、bundle 图片与 UIImage，以及独立选中图标。`updateTabItem(id:configuration:)` 更新原生条目，不重建控制器或导航栈。样式与媒体背景共同应用，清除后恢复宿主 / 系统外观。实际接口和边界见 [栏位字体与图标](Bar-Styling.md)。

### 0.5 已实现：系统与经典栏位类型

`ShellBarPresentation.system / .classic` 在保留原生容器、页面与导航栈的前提下切换栏位呈现。标签容器可设置默认类型，导航可继承或单独覆盖，页面以 `ScreenConfiguration.barPresentation` 覆盖当前管理的两处栏位。经典类型使用普通按钮、平直导航和全宽底部标签，继续支持字体 / 图标、更多入口、安全区域以及媒体背景。

SDK 默认 system，Demo 0.5 默认 classic。实际 API、恢复规则、系统外观边界与示例见 [栏位类型](Bar-Presentation.md)。本节之后的通用渲染器 / 全局配置仍包含后续设计草案，不替代该已实现 API。

## 10. 液态玻璃策略

高版本与低版本分别配置，避免用一个 `glassEnabled` 混淆运行环境和降级行为。

| 策略 | iOS 26 及以上 | iOS 15–25 |
| --- | --- | --- |
| 推荐默认 | 原生系统玻璃与系统控件外观 | 系统默认外观 |
| 跨版本玻璃风格 | 原生系统玻璃 | SDK 仿玻璃 |
| 跨版本经典风格 | SDK 可控范围内的经典外观 | 系统默认或经典外观 |
| 自定义品牌风格 | 自定义栏位 / 表面，选择原生玻璃或经典材质 | 自定义栏位 / 表面，选择默认或仿玻璃 |

`modern` 建议提供 `systemGlass` / `classic`，`legacy` 提供 `systemDefault` / `frostedGlass`。同时支持导航栏、标签栏和具体按钮的材质覆盖。

### 原生玻璃

系统容器与系统控件优先采用默认外观，避免在已有玻璃上再覆盖一层模糊。自定义玻璃表面使用 `UIGlassEffect`；多个相关玻璃元素确有融合需求时使用 `UIGlassContainerEffect`。普通按钮优先采用系统玻璃按钮配置。[R1][R2]

不把所有业务卡片、列表行和整页背景都做成玻璃。玻璃主要服务于导航和操作层，正文区域保持清晰。

### 高版本关闭玻璃的准确边界

- 自己持有的 `UIGlassEffect` 视图和按钮配置可以切换为普通材质。
- 对公开 Appearance API 能控制的系统背景，设置不透明 / 经典背景；对适用的单个栏位按钮，可使用 `hidesSharedBackground` 等公开选项。
- `hidesSharedBackground` 只针对相应按钮背景，而且在含多个 item 的 `UIBarButtonItemGroup` 中会被忽略；不能当作全栏位开关。[R3]
- **若要求导航栏、标签栏与按钮整体呈现严格一致的经典外观，应显式选择 SDK 自定义栏位渲染器。** 不能把一次 Appearance 配置解释为所有原生玻璃和交互都被关闭。
- 经典模式只控制 SDK 所拥有的 UI；系统菜单、键盘、系统弹窗等仍遵循系统外观。
- `UIDesignRequiresCompatibility` 是 App 级临时兼容键，不是页面级或运行时切换 API；使用 iOS 27 / iPadOS 27 及以后 SDK 构建时系统会忽略它。SDK 的长期设计不依赖这个键。[R4]

### 低版本仿玻璃

使用公开 API 组合 `UIBlurEffect`、半透明 tint、轻量边缘高光、描边、阴影和按压反馈；提供强度与色调配置。此模式可以高仿视觉风格，但不承诺复刻系统的折射、融合和全部交互。

优先使用静态装饰与合适的实时模糊，首版不引入自定义折射 Shader 或逐帧屏幕截图。通过实际设备性能再决定是否增加更复杂效果。

### 无障碍与实际结果

减少透明度时优先清晰的实色 / 不透明背景；减少动态效果时移除装饰性位移、回弹和变形；提高对比度时调整正文与操作对比。系统组件由系统适配，自定义组件需显式响应设置变化。

解析器返回 `resolvedRenderer`、`resolvedMaterial` 和 `fallbackReason`。强制选择系统不支持的材质时，采用声明的 fallback 并给出诊断，不崩溃、不静默显示空白。

## 11. 系统渲染器与自定义渲染器的取舍

| 能力 | 系统渲染器 | 自定义渲染器 |
| --- | --- | --- |
| 系统玻璃、溢出和新设备原生栏位演进 | 优先获得平台支持 | 由 SDK 单独实现和维护 |
| 精确品牌尺寸与严格经典外观 | 受公开 API 边界约束 | 可精确控制 SDK 自有 UI |
| Duo 竖向布局与避让 | 容器负责原生行为 | 需保留区域、布局与手势专项验收 |
| 默认建议 | `automatic` 优先选择它 | 仅在明确配置或系统能力不足时选择 |

材质切换默认只更新表面。若配置要求变更系统 / 自定义栏位渲染器，作为容器级稳定设置处理，在转场结束后的安全点统一应用，不在交互返回过程中重建栏位或控制器。

自定义栏位仍保留系统导航 / 标签容器作为内容和状态基础，但隐藏对应的系统可见栏位，避免双重占位。其状态栏、安全区和原生竖向栏位是否退出，需要在最小原型中验证并形成固定策略；不通过每页反复开关 `preferredVerticalBarBehavior` 掩盖冲突。

如某种自定义组合尚未通过验收，则在诊断中标明并降级到已经支持的模式，不能同时宣称拥有完整原生自动行为和任意自定义布局。

## 12. 页面内容、键盘与生命周期

`BoneViewController` 提供受管理的 `contentView` 和内容 layout guide。页面在其中构建内容，默认不需要计算导航栏高度、标签栏高度或键盘高度。

建议页面内容策略：

- `safeArea`：交互内容位于容器解析后的安全区域。
- `underBars`：背景 / 滚动内容可延伸到栏位后，控件保留正确 inset。
- `immersive`：媒体等沉浸场景，明确声明需要的控件避让。

主滚动视图通过 `registerPrimaryScrollView` 注册。每个边缘只有一个 inset 管理者：保留系统已提供的 safe area / 自动 inset，SDK 只增加自己产生的额外占位，避免重复扣除。宿主原有附加 inset 不被覆盖；SDK 分别跟踪自己的占位贡献。

键盘避让默认使用公开键盘 layout guide，并处理硬件键盘、浮动键盘与当前窗口的实际遮挡。底部栏可声明随键盘隐藏、保留或跟随，不能统一把键盘高度加到所有页面。

框架观察布局、安全区、trait 和辅助功能变化，协调到同一布局周期。push / pop 时按目标页面解析外观；交互返回取消时恢复原页面配置。Appearance 按容器 / navigation item 设置，避免运行时修改全局 `UIAppearance` 影响其他窗口。

返回手势由导航协调器统一管理，普通页面不抢占 `interactivePopGestureRecognizer.delegate`。系统转场与手势保持默认；只有明确的未保存编辑保护等场景增加受控拦截。

### 0.2 已实现：三处多媒体背景

页面使用 `screen.background`、`screen.navigation.background`、`screen.tabBarBackground` 独立设置图片、GIF / APNG、MP4 和 HTML；导航 / 标签容器可提供默认值，页面显式 `.none` 可关闭继承背景。背景与材质分别配置，保留系统栏位与返回手势。

切页采用后台缩略解码、128 像素尺寸桶、重复请求合并、默认 48 MB 共享图像软缓存，以及转场前海报 / 首帧准备。动态播放默认每个 Scene 一个，上限可设为三个；页面出现后播放、离开时暂停，HTML 离屏释放。减少动态效果、减少透明度或低电量时采用静态表示。实际接口、限制与接入示例见 [多媒体背景](Backgrounds.md)。

上述为当前实现策略；FPS、峰值内存、耗电及多设备姿态仍需实际测量，不以策略声明替代性能验收。

## 13. 拟定接入示例

以下代码展示期望的使用体验，属于待实现的 API 草案，尚未编译。

### App 默认配置

```swift
import BoneShellKit

BoneShell.configure { configuration in
    configuration.layout = .automatic
    configuration.navigation.renderer = .automatic
    configuration.tabs.style = .automatic
    configuration.material = .init(
        modern: .systemGlass,
        legacy: .systemDefault
    )
}
```

Scene 创建自己的 `BoneShellContext`，传入根容器，默认继承 App 配置。不同 Scene 可以有不同外观和当前选中标签。

需要低版本仿玻璃时将 `legacy` 改成 `.frostedGlass`。若要求严格经典栏位，配置 `modern: .classic`，同时显式选择导航和标签的 `.custom` 渲染器。解析器需校验这类组合。

### 页面继承

```swift
import UIKit
import BoneShellKit

final class HomeViewController: BoneViewController {
    override func configureScreen(_ screen: inout ScreenConfiguration) {
        screen.content = .safeArea
        screen.navigation.title = .text("首页")
        screen.navigation.trailingActions = [
            .init(
                id: "search",
                title: "搜索",
                symbol: "magnifyingglass",
                priority: .standard,
                action: { [weak self] in self?.showSearch() }
            ),
            .init(
                id: "create",
                title: "新增",
                symbol: "plus",
                priority: .primary,
                action: { [weak self] in self?.showCreate() }
            )
        ]
    }

    override func buildContent(in contentView: UIView) {
        // 将业务视图约束到 contentView 或框架提供的内容 layout guide。
        // 如为滚动页面，在此注册主 scroll view。
    }

    private func showSearch() { /* 业务行为 */ }
    private func showCreate() { /* 业务行为 */ }
}
```

基类在内部调用 `configureScreen` 与 `buildContent`，并提供显式配置失效 / 刷新入口。页面不需要覆盖系统布局方法来重新摆放导航按钮；自定义业务内容需要时可通过 `layoutDidChange(_:)` 获取当前环境。

已有的 `UITableViewController`、第三方控制器等使用 adapter，不强迫修改其继承关系。

## 14. 建议工程结构

```text
BoneShellKit/
├── Package.swift
├── Sources/BoneShellKit/
│   ├── Configuration/
│   ├── Environment/
│   ├── Containers/
│   ├── Navigation/
│   ├── Tabs/
│   ├── ContentLayout/
│   ├── Materials/
│   ├── Adapters/
│   └── Diagnostics/
├── Tests/BoneShellKitTests/
├── Examples/BoneShellDemo/
│   ├── BoneShellDemo.xcodeproj/
│   ├── Sources/
│   ├── BoneShellDemoTests/
│   ├── BoneShellDemoUITests/
│   └── TestPlans/
└── Documentation/
    ├── SDK-Plan.md
    └── Demo-Test-Plan.md
```

核心不依赖 Shorthand 的颜色、图片、数据库、业务路由或助理实现，也不引入第三方自动布局库作为必须依赖。

BonePopoverKit 保持独立。两者通过宿主桥接当前 Scene、主题与返回手势协调；弹窗的布局和状态仍由 BonePopoverKit 管理，避免互相依赖和双方同时修改手势 delegate。

## 15. 从现有工程提取的顺序

| 当前代码 | 可复用部分 | 迁移时需处理 |
| --- | --- | --- |
| `BoneBasicController` | 基础页面入口、标题 / 操作配置意图 | 将全局 Screen 尺寸、缓存栏高和手动 frame 迁为内容 guide；移除页面各自接管返回手势的方式 |
| `MainTabNavController` | 导航容器接入位置 | 从长期隐藏系统导航栏 + 全局 Appearance 转到按渲染器、按容器管理 |
| `MainTabViewController` | 标签选择、低 / 高版本分支和 Dock 经验 | 将标签模型、渲染、助理入口、品牌视图拆开；容器内独立创建的 `UITabBar` 不直接视为 Duo 适配基础 |
| `MiyaoDockGlassView` | 原生玻璃、旧版 blur / 边缘装饰实现经验 | 参数化品牌色，加入明确高版本关闭策略和统一无障碍解析 |
| `BonePopoverKit` | 已有 iOS 15+ Swift Package 与弹窗能力 | 保持独立，通过宿主做主题和手势协调 |

迁移步骤：

1. 先建立独立 Package 和 Demo，不直接替换正在开发的 App 根容器。
2. 在 Demo 验证系统导航、标签、内容 guide 与材质切换。
3. 选一个普通详情页和一个有多个导航按钮的编辑页试接入。
4. 验证返回、交互取消、键盘及弹窗后，再接入列表与首页。
5. 最后迁移品牌 Dock 和助理 accessory；宿主业务和品牌资源留在宿主。
6. 开启 Universal 后单独验收 iPad，再进行 Duo 各姿态与宽度验收。

上述为宿主迁移计划。当前已建立独立 SDK 与 Demo，尚未将 Shorthand 业务页面迁入 SDK。

## 16. 分阶段研发计划

| 阶段 | 交付 | 完成条件 |
| --- | --- | --- |
| 0.1：原生骨架 | Package、薄基类、系统导航 / 标签容器、配置合并、主滚动视图接入；独立 Demo 基础场景、SDK 单元测试及 Demo 集成 / UI 冒烟测试 | Demo 在 iOS 15 与新系统正确运行，基础导航、操作可达、标签状态保留及冒烟测试通过 |
| 0.2：多媒体背景 | 页面 / 导航 / 标签独立图片、动图、MP4、HTML；异步缓存、预取、播放预算、Demo 与回归 | 缓存复用、快速切换、返回恢复和离屏暂停通过实际测试，记录性能验证边界 |
| 0.3：栏位字体与图标 | 字号 / 字体 / 颜色、普通 / 选中态、Dynamic Type、图标替换、运行时更新与恢复 | 实际 Appearance 和屏幕显示正确，切页 / 标签 / 换图保留状态，背景功能回归通过 |
| 0.4：整体背景 | 一个容器画布覆盖导航 / 页面 / 标签，统一裁切与播放，同配置切页复用 | 单一画布 / 播放名额、整屏图像坐标、模式切换与返回恢复通过测试 |
| 后续：自适应验收 | 扩展多按钮与双栏，验证 iPad 窗口变化和 Duo 栏位适配 | 窄 / 宽切换不丢状态；竖向操作与安全区验收通过 |
| 0.5：栏位类型 | 系统 / 经典导航与标签、类型继承与恢复、旧版形态、默认经典 Demo | 类型切换保留状态，平直栏位 / 普通按钮、安全区与背景协作通过实际检查 |
| 后续：外观扩展 | 其他栏位、自定义品牌细节、通用按钮与完整设备矩阵 | 请求与实际模式可观测，所有声明组合通过运行验收 |
| 1.0：发布就绪 | Demo 完整场景与回归矩阵、文档、迁移指南、测试结果与性能基线 | 对外接口稳定，声明支持的设备 / 系统矩阵有验证记录 |

建议一名熟悉 UIKit 的工程师，按上述范围预留约 4–6 个工作周，作为初步排期；精确经典外观与自定义 Duo 栏位应先做技术原型，再修订工期。SwiftUI 桥接排在核心稳定之后。

首版不加入业务路由系统、网络层、数据库、账号权限、相机或铰链互动特效，保持页面骨架 SDK 的范围。

## 17. 后续验证矩阵与验收标准

独立 Demo 是 SDK 的同步交付项，从 0.1 起使用本地 Package 与公开接口演示真实功能。详细要求见 [Demo 与测试方案](Demo-Test-Plan.md)，包含 13 个交互场景、31 个核心用例、测试工程组织、冒烟 / 回归测试及结果留证。

SDK 单元测试、Demo 集成测试、Demo UI 测试和视觉 / 设备验收分别记录；Demo Scheme 的测试结果不能代替全部 Package 单元测试。

以下为研发时应执行的验收，未在本次规划中运行。按关键组合覆盖，不要求所有维度做完整笛卡尔积。

| 维度 | 必测组合 |
| --- | --- |
| 系统 | iOS 15 最低版本、16 分组 / 溢出分支、18 标签侧边栏分支、26 玻璃分支、27.1 Duo 分支 |
| 设备 / 窗口 | 小屏 iPhone、普通大屏 iPhone、iPad 宽 / 窄窗口、Duo 内 / 外屏及支持的姿态 |
| 文本 | 0 / 1 / 多个按钮、超长标题、中文 / 英文 / RTL、最大辅助字号 |
| 交互 | 独立标签导航栈、push / pop、滑动返回完成 / 取消、sheet 关闭、未保存编辑保护 |
| 输入 | 软键盘、硬件键盘、浮动键盘、输入过程中 resize |
| 材质 | 高版本原生玻璃 / 经典、低版本默认 / 仿玻璃、无障碍降级 |
| 背景 | 三个区域、图片 / GIF / APNG / MP4 / HTML、缓存冷 / 热切换、播放预算、低电量、离屏释放 |
| 状态 | 展开 / 折叠、页面滚动位置、编辑文本、选中项、多个 Scene |

自动化测试聚焦配置合并、能力降级、动作保留、溢出分组及状态映射；UI 测试验证导航和布局切换中的用户行为。截图与设备运行验证用于确认实际位置、重叠、对比度和玻璃表现。

发布验收标准：

- 正常页面无需编写栏位高度或系统版本判断，只声明标题、操作和内容。
- 任意受支持窗口变化不出现导航 / 标签重叠、重复 inset 或控制器重建。
- 空间不足时全部业务操作仍有可访问入口，返回和关闭路径可用。
- 交互返回取消后页面外观与业务状态一致。
- 低版本不访问新 API，高版本经典模式不依赖临时兼容键。
- 系统 / 自定义渲染器的支持边界有文档，实际降级原因可以检查。
- 默认选择系统容器；不使用私有类名、KVC、系统视图层级探测或全局方法交换修饰栏位。
- 原生玻璃与仿玻璃均能响应无障碍设置；性能以设备运行与 Instruments 记录为准。

## 18. 本次结论与待落地事项

可以实现这套 SDK，推荐采用 BoneShellKit 作为名称，以 iOS 15+、UIKit 优先、系统容器默认作为起点。将“布局自适应”“栏位渲染”“材质选择”分别配置，是满足自动兼容与可自定义的关键。

0.1 验证版已实现最小原生骨架、Demo 与核心测试，并完成真机安装；0.2 接入三处多媒体背景及缓存 / 播放生命周期控制，0.3 增加栏位字体 / 颜色与标签图标配置。0.5 已接入系统 / 经典导航和标签切换；Duo 全姿态协作、其他栏位和完整适配矩阵仍需专项验收；当前范围及已执行结果见 [验证记录](Implementation-Status.md)。

## 19. 技术依据

### Apple 官方资料

- [R1：Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)：原生控件采用方式、布局与无障碍建议。
- [R2：UIGlassEffect](https://developer.apple.com/documentation/uikit/uiglasseffect)：原生玻璃，iOS 26.0 起提供。
- [R3：hidesSharedBackground](https://developer.apple.com/documentation/uikit/uibarbuttonitem/hidessharedbackground)：栏位按钮共享背景的作用范围与分组限制。
- [R4：UIDesignRequiresCompatibility](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility)：临时兼容用途及新 SDK 下忽略该键的说明。
- [R5：preferredVerticalBarBehavior](https://developer.apple.com/documentation/uikit/uiviewcontroller/preferredverticalbarbehavior)：iOS 27.1 的竖向栏位行为与稳定退出原则。
- [R6：axisBehavior](https://developer.apple.com/documentation/uikit/uibarbuttonitem/axisbehavior-swift.property)：iOS 27.1 栏位按钮轴向行为。
- [R7：additionalOverflowItems](https://developer.apple.com/documentation/uikit/uinavigationitem/additionaloverflowitems)：iOS 16 起的系统溢出菜单接入点。

以上页面已通过 Apple 官方文档数据接口读取。常规网页搜索因本地鉴权服务未启动而未使用结果，不影响上述直连资料核验。

### 设计来源

本方案总结已有 UIKit 页面骨架、容器和材质实现中的公共需求。本仓库只包含独立 SDK、Demo 与正式测试，不依赖宿主业务工程或历史构建产物。
