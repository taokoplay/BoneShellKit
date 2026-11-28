# 更新记录

已发布版本按 Git 标签记录。接入方式见 [README](README.md)，实际执行范围见 [验证记录](Documentation/Implementation-Status.md)。

## 0.14.2

发布标签为 [v0.14.2](https://github.com/taokoplay/BoneShellKit/tree/v0.14.2)。

- 独立图标 NavButton 使用默认尺寸和留白并自绘表面时，按栏位绘制圆形。Duo 栏位空间充足时直径为 48 pt，空间不足时等比缩小。可显式声明 `.fitting`、`.preferred` 或内部留白来控制外形。
- 「导航栏」Demo 的「详情」动作展示默认圆形，同时覆盖横栏、Duo 侧栏和旧系统材质回退。

## 0.14.1

发布标签为 [v0.14.1](https://github.com/taokoplay/BoneShellKit/tree/v0.14.1)。

- 修复原生导航转场后自定义 `titleView` 偶发消失的问题。页面显示完成后，SDK 自动重新挂载脱离窗口的原标题视图，保留点击回调与菜单。

## 0.14.0

发布标签：[v0.14.0](https://github.com/taokoplay/BoneShellKit/tree/v0.14.0)。

### 破坏性变更

- `NavigationAction.axisBehavior` 与 `ShellNavigationActionAxisBehavior` 移除，改为模块级 `sidebarBehavior: ShellNavigationSidebarBehavior`（`.system` / `.disabled` / `.preferred`）。
  - 独立按钮用 `NavigationAction.sidebarBehavior`，按钮组用新增的 `NavigationButtonGroup.sidebarBehavior`；组声明优先，组内动作的同名声明被忽略。
  - 修复此前只读取组内首个动作、其余声明被静默忽略的问题。
  - `.disabled` 同时停止该模块的 iPhone Duo 侧栏样式解析与侧栏位置判断，`.preferred` 映射系统优先竖向；`.system` 为所有初始化器的新默认值（`navButton:` 版本原为 `.verticalPreferred`）。
- `ShellNavButton.Effect` 收敛为 `.inherited` / `.none` / `.material(ShellMaterial)`，删除 `.blur` 与 `.liquidGlass`。按钮表面与栏位共用 `ShellMaterials` 的解析与回退；旧系统写 `.material(.systemGlass)` 自动回退为磨砂。

### 新增

- `ShellNavButton.Style.tintColor`、`NavigationButtonGroup.tintColor` 与 `ShellGlassView.glassTintColor`：按钮表面的主题色与栏位 `ShellNavigationStyle.backgroundColor` 同源。
- `ShellMaterialRendering.clipsContent(_:)`：统一判断“系统玻璃是否需要宿主裁剪”，`ShellGlassView`、按钮组、独立 NavButton、兼容胶囊与标签附加按钮共用同一入口。
- `ShellNavButtonCluster` 在 iOS 26 且组材质解析为 `.systemGlass` 时使用 `UIGlassContainerEffect` 合并组内玻璃；**该实现因接缝凹陷与双重折射暗带已撤回**，组表面恢复为一整块 `ShellGlassView`。

### 变更

- 独立 NavButton 的表面改为复用 `ShellGlassView`，与按钮组、胶囊栏使用同一份绘制实现。
- SDK 自绘玻璃关闭 `UIGlassEffect.isInteractive`：表面层不参与命中测试，按压反馈由承载控件负责；标准图标 / 文字按钮补齐按压透明度反馈。
- 按钮自绘玻璃的表面高度跟随系统栏位条目（Duo 横栏 48 pt、普通 iPhone 44 pt），与返回键等高；槽位与点击区域不变。
- iPhone Duo 侧栏中，按钮组整体改为竖排：承载视图不拆分，组内按钮上下堆叠，组表面是一枚竖胶囊。
  - 侧栏内所有条目玻璃同宽：按「槽位 + 4 pt」（Duo 实测槽位 44 → 玻璃 47.7）居中绘制，组、独立按钮与系统返回键宽度一致。
  - 竖排时组表面绘制的模块，每枚按钮与组玻璃同宽且为正方形（48 × 48），不加额外内边距；图标大小完全由 `iconSize` / `contentInsets` 控制，组高 = 边长 × 数量 + 组内净距。独立按钮保持自身声明尺寸（例如 44 × 72）。
  - 侧轨按每项 44 pt 分配槽位且容量约 3 项：整组竖排占用相当于两项的高度，同侧动作更多时系统会把放不下的项移出侧轨。

### 修复

- 系统栏中按钮与相邻模块压叠：间距归一化此前把已进入「更多」菜单的模块也计入参考位置，产生越界偏移，把可见按钮推到相邻条目上、文字跑出按钮边界。现在只统计真正落在栏内的模块，并限制单次偏移幅度。
- 模块间距归一化的两处缺陷：按钮组的胶囊此前完全不应用模块偏移（不参与归一化），且多出的间隙全部推给后继模块导致偏移逐级累积，末位按钮的胶囊被推出自身槽位。现在组表面与组内图标一起平移，剩余量在两侧均分。
- 模块间距归零时表面、图标、标题三者错位：按钮表面现在跟随模块视觉偏移，`moduleVisualBounds` 按表面计算；`titleRect(forContentRect:)` 也应用同一偏移，文字按钮不再被推出表面贴住一侧边缘。表面尺寸改用实际布局到的 `bounds`。
- 系统玻璃不再被宿主裁剪，保留画到视图边界之外的边缘高光；回退材质仍用圆角遮罩。
- 修好 UIKit 在首次布局时把 `imageView` 插入索引 0、导致玻璃盖住图标与文字的层级问题。
- 侧栏判定由「整块外框在轨道内」改为「模块中心在轨道内」：比轨道更宽的组否则永远认不出自己在侧栏。
- 修复 Demo 输入页状态文字中的非法字符串转义，该问题导致 Demo 目标无法编译。

### Demo 与测试

- 「导航栏」页的方向选择改为 `nav.sidebar` 三档（系统默认 / 不启用 / 优先侧栏），同时作用于独立按钮和按钮组；按钮表面选择改为「无 / 系统默认 / 系统玻璃」。
- 新增 DEBUG 参数 `-navbutton-single-group`，只保留按钮组以核对侧栏竖排效果。
- `NavButtonUITests` 与 `NavigationAdaptiveUITests` 随侧栏与材质改动更新；新增侧栏竖排、玻璃宽度、系统条目等高与溢出模块不干扰的单元用例。
- Demo 版本升至 0.14.0（Build 1）。

## 0.13.5

发布标签：[v0.13.5](https://github.com/taokoplay/BoneShellKit/tree/v0.13.5)。

- 区分按钮组玻璃表面和独立按钮玻璃表面；独立 Liquid Glass 按钮关闭 UIKit 共享背景，支持 iPhone Duo 原生侧栏。
## 0.13.4

发布标签：[v0.13.4](https://github.com/taokoplay/BoneShellKit/tree/v0.13.4)。

- 修复模块间距校正移动按钮组内容导致独立图标裁剪或组内左右留白变化的问题。
## 0.13.3

发布标签：[v0.13.3](https://github.com/taokoplay/BoneShellKit/tree/v0.13.3)。

- 玻璃导航栏支持叠加主题颜色和透明度，同时保留系统玻璃及标题 / 按钮的不透明度。
- 统一兼容、经典和 iOS 27 原生导航中的模块可见边界间距，校正 UIKit 与按钮内边距产生的额外空间。

## 0.13.2

发布标签：[v0.13.2](https://github.com/taokoplay/BoneShellKit/tree/v0.13.2)。

- 修复 iOS 26 真机的 Liquid Glass 组材质内部 `UIVisualEffectView` 未同步圆角 mask，按钮组不再显示为直角矩形。
## 0.13.1

发布标签：[v0.13.1](https://github.com/taokoplay/BoneShellKit/tree/v0.13.1)。

- 修复经典导航栏自定义 `titleView` 被居中布局的问题，标题从 leading 控件之后开始布局并保留 RTL 支持。
- 修复 iOS 27 原生导航按钮组把 Liquid Glass 表面交给 UIKit 后圆角不稳定的问题，统一使用 SDK 的单层圆角组材质并关闭重复共享背景。
- 补充自定义标题左对齐和原生组圆角的回归断言。

## 0.13.0

发布标签：[v0.13.0](https://github.com/taokoplay/BoneShellKit/tree/v0.13.0)。

- 按职责拆分源码目录：容器类型移入 `Sources/BoneShellKit/Containers/`，导航声明和兼容布局移入 `Sources/BoneShellKit/Navigation/`。
- `BoneContainers.swift` 拆为导航容器、标签目的地、标签容器和分栏容器文件；`ScreenConfiguration.swift` 拆为导航动作、导航配置、页面配置和动作布局文件。
- 补充源码结构说明、类型维护入口和拆分后的验证规则；公开 API、模块导入方式和宿主接入方式保持不变。
- SDK 的 `public` / `open` 类型、属性、初始化器、方法及参数继续使用中文文档，并完成公开 API 文档扫描。

## 0.12.1

发布标签：[v0.12.1](https://github.com/taokoplay/BoneShellKit/tree/v0.12.1)。

- 修复 iOS 26 系统导航中共享 Liquid Glass 背景被自定义按钮路径关闭的问题。
- NavButton 在系统栏位中统一由 `ShellNavButtonCluster` 承载，避免导航栏重排或返回转场后出现空玻璃容器。
- 自定义 confirmation NavButton 保留确认语义和优先级，不再叠加 UIKit `.done` 外观，按钮文字和材质由自定义视图负责。
- 修复 iOS 15–26 兼容导航在 leading 为空时错误压缩 trailing action 的宽度预算，返回页面后重新提交导航分组和按钮内容。
- Demo 导航页支持全部栏位呈现和材质选择，并补充 NavButton confirmation、push / pop 恢复及材质配置回归。

## 0.12.0

发布标签：[v0.12.0](https://github.com/taokoplay/BoneShellKit/tree/v0.12.0)。

- `NavigationAction` 新增 `visibility`，支持 `.automatic` 和 `.always`。兼容布局会保留指定动作，iOS 27+ trailing 动作使用 pinned 分组。
- Navigation 配置改为有序 `leadingModules` / `trailingModules`；按钮组拥有明确的组材质和 `itemSpacing`，模块之间使用 `moduleSpacing`，移除旧的自动相邻 NavButton 编组入口。
- Demo、API 参考、导航接入说明和验证记录同步到 v0.12.0。最低部署目标保持 iOS 15。
- Demo 版本更新为 0.12.0（Build 1）。iOS 27.1 导航相关测试 31 项通过，iOS 18.6 兼容新增测试 3 项通过。

## 0.11.0

发布标签：[v0.11.0](https://github.com/taokoplay/BoneShellKit/tree/v0.11.0)。

- `NavigationAction(navButton:)` 支持按钮尺寸、按钮级材质、完整自定义 `UIView`、横栏与 Duo 侧栏分轴样式，以及相邻按钮组内净距。
- `Style.icon` 支持轴向独立图标。普通样式可以显示文字，侧栏样式可以显示勾号或其他系统图标。
- `NavigationConfiguration.titleView` 支持原生及经典导航的完整可交互 `UIView` 标题。
- 普通标签与附加动作支持完整 `UIView`，统一使用 `ShellTabBarCustomContent`。
- Demo、API 参考、导航接入说明和验证记录同步到 v0.11.0。最低部署目标保持 iOS 15。
## 0.10.0

发布标签：[v0.10.0](https://github.com/taokoplay/BoneShellKit/tree/v0.10.0)。

- `NavigationAction` 新增图片 `icon`、关闭 / 确认 `role`、`axisBehavior`，保留原有 symbol 初始化调用。
- iOS 27+ 原生导航完整提交唯一动作，使用系统分组、优先级及溢出；iOS 27.1+ 映射轴向偏好。经典与旧系统保留横向宽度预算。
- 按稳定 ID 复用按钮与原生分组；尺寸变化保留菜单来源，更新后使用最新有效回调，移除后释放回调。
- 修复旧系统中修改已安装菜单动作引发的异常；经典导航按页面真实安全区计算自身 inset，保留宿主贡献并避免顶部遮挡。
- Demo 增加图标来源与方向设置、恢复及集成 / UI 回归。使用与支持范围见 [导航动作与自适应](Documentation/Navigation-Actions.md)，实际执行结果另记于验证记录。
- 最低部署目标仍为 iOS 15，新增 API 保留兼容默认值；v0.9.1 不包含这些扩展。任意自定义 UIView、加载 / badge 声明及自定义经典竖向栏位仍在后续范围。
- 导航相关回归：Duo / iOS 27.1 的 52 项单元 / 集成全部通过；iPhone / iOS 18.6 的 45 项通过、7 项按版本跳过；两端各 2 项 UI 用例通过，Duo 为分批结果。完整姿态矩阵尚未验收，详见 [验证记录](Documentation/Implementation-Status.md)。
- Demo 版本更新为 0.10.0（Build 1）；功能回归、发布准备构建及历史基线分别记录。

## 0.9.1

发布标签：[v0.9.1](https://github.com/taokoplay/BoneShellKit/tree/v0.9.1)。

- 新增 [SDK 方法说明](Documentation/Usage-Examples.md)，按类型说明创建入口、参数、返回值及用途。
- 新增 [可设置字段与中文说明](Documentation/API-Reference.md)，集中列出字段类型、默认值、枚举值、只读结果及设置生效规则。
- 简化 README 最小接入示例，补齐方法与字段参考入口，远程依赖示例锁定 0.9.1。
- 本次仅更新文档；SDK、Demo 与测试的 Swift 源码保持 v0.9.0 的内容，Demo 版本仍为 0.9.0（Build 1）。

## 0.9.0

已发布标签：[v0.9.0](https://github.com/taokoplay/BoneShellKit/tree/v0.9.0)。

### 新增

- 新增 `ShellTabLabelDisplayMode`：`.always` 始终显示、`.never` 始终隐藏、`.selectedOnly` 仅选中项显示、`.unselectedOnly` 仅未选中项显示。
- `ShellTabBarStyle.labelDisplayMode` 提供整栏默认策略，默认 `.always`；页面 `screen.tabBarStyle` 仍按整份样式覆盖容器。
- `ShellTabItemConfiguration.labelDisplayMode` 与两种 `ShellTab` 初始化器支持单项覆盖，默认 `nil` 继承当前样式，设回 `nil` 恢复继承。
- 原生、经典、兼容胶囊及原生 dock 均接入文字策略。隐藏文字后保留配置中的语义标题、无障碍名称和宿主自定义名称，图标在条目内居中。
- Demo“示例 → 标签栏”新增“标签文字显示”四段开关，显示当前策略，恢复默认时回到 `.always`；切换策略保留内容实例、导航栈及已有设置。

### 修复

- 原生“更多”按钮跟随整栏文字策略，溢出列表仍保留各目的地名称。
- 原生 dock 在隐藏文字后继续同步目的地标识、无障碍名称和选中状态；等待 UIKit 完成本次选择事件后再刷新页面样式，避免连续切页时点击失效。
- 经典栏及兼容胶囊隐藏实际文字 label 并调整图标位置；图标单独显示时缩小选中背景。

### 兼容与验证

- 新参数均提供兼容默认值，现有调用继续有效。文字显示策略从 `v0.9.0` 开始提供，`v0.8.0` 不包含；接入时锁定准确标签。
- Xcode 27.1、iPhone 13 Pro / iOS 26.0 模拟器：97 项单元 / 集成与 8 项相关 UI 测试，单次 105 项通过，0 失败、0 跳过。
- 三种实际栏样式 × 四种策略的 12 张截图，以及 3 张切到关于的截图已打开核对；原图和对比材料仅保存在本地验证目录。
- 文字策略开发包已在 iPhone 13 Pro / iOS 26.5 安装、启动，并分别核对安装记录、应用版本与运行进程；该包的 Demo 版本为 0.8.0（Build 1）。0.9.0（Build 1）发布包已另行构建并通过产物版本与签名校验。安装结果不代表真机四策略完整回归。
- 旧系统兼容路径使用能力注入执行单元测试；实际 iOS 15–25、iPad / Duo、VoiceOver、RTL 及完整辅助字号矩阵尚未完成。

完整 API 与继承规则见 [标签文字显示策略](Documentation/Bar-Styling.md#标签文字显示策略)。

## 0.8.0

已发布标签：[v0.8.0](https://github.com/taokoplay/BoneShellKit/tree/v0.8.0)。

- 支持 `.automatic / .classic / .capsule / .system` 栏位请求，按系统能力选择原生或兼容呈现；导航栏提供系统与经典两种外观。
- 新增标签栏 leading / trailing 附加动作：经典栏内、兼容胶囊外侧、原生 dock，或显式系统模式的原生槽位 / 旧系统 tab item；动作不改变目的地选中项。
- 原生 dock 保留 UIKit 表面，测量可见几何并与两侧圆形按钮对齐；更新外观和选择时保留内容及导航状态。
- 浮动标签栏下的主滚动视图延伸到底边，保留宿主 inset 与 mask，默认 80 pt 渐隐，可设为 0 关闭。
- 标签图标支持自动、选中颜色、选中原图策略，以及字体、图标颜色、媒体背景和运行时条目更新。
- Demo 导航栏与标签栏设置拆页，文档区分已有能力、设计设想和实际验证范围。

0.8 验证结果为分批去重后的 109 个唯一用例，不能视为单次完整运行；方法与限制见 [0.8 历史验证](Documentation/Implementation-Status.md#08-既有功能验证历史基线)。更早实现记录见 [0.1–0.6 历史验证](Documentation/Archive/Implementation-History.md)。
