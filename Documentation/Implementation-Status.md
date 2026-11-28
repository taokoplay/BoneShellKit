# 当前实现与验证基线

当前 SDK 发布版本为 **v0.14.2**，Demo 为 0.14.0（Build 1）。模块级侧栏策略、统一的玻璃绘制与系统栏按钮布局修复在 v0.14.0 提供。iOS 26 导航共享玻璃、NavButton 自定义 cluster 承载、confirmation 外观、返回恢复和兼容宽度预算随 v0.12.1 发布。导航动作强制显示策略随 v0.12.0 发布，NavButton、自定义导航标题与整项自定义标签内容随 v0.11.0 发布。文字策略功能源码基线为 `bd7a7f6`，0.8 既有功能代码基线为 `9f758a1`。版本变化见 [更新记录](../CHANGELOG.md)。

## v0.14.2 导航图标默认圆形

- Xcode 27.1 编译。iPhone Duo / iOS 27.1 模拟器实测默认表面和点击区域在横栏与侧栏均为 48 × 48 pt，玻璃圆角为 24 pt。五种显式尺寸样本的布局与 v0.14.1 实测一致。
- iPhone 16 Pro / iOS 18.6 模拟器实测磨砂回退的默认按钮表面和点击区域为 44 × 44 pt，圆角为 22 pt。`NavButtonAppearanceTests` 与 `NavButtonLayoutTests` 共 20 项通过、1 项按系统版本跳过。间距、玻璃组和经典窄栏溢出三项失败用 v0.14.1 在同一模拟器复现，断言和值一致。
- Duo 的新增 UI 用例验证「详情」在实际横栏、侧栏均可点击并打开表单。该次验收使用模拟器覆盖这两种栏位。

## v0.14.1 自定义标题恢复

- Xcode 27.1，iPhone 16 Pro / iOS 18.6 与 iOS 26.0 模拟器运行 `NavigationTitleViewTests`，各 4 项通过。
- 在 `v0.14.0` 的 iOS 18.6 对照中，标题宿主脱离窗口后，导航项仍持有该宿主，但标题未能重新挂载。修复后断言原宿主和按钮回到同一窗口的导航栏，保留原菜单实例，按钮回调仍可触发。

## v0.14.0 发布检查

- 发布标签 `v0.14.0`；Demo `MARKETING_VERSION = 0.14.0`、`CFBundleVersion = 1`，产物 `CFBundleShortVersionString` 为 0.14.0、`MinimumOSVersion` 为 15.0。
- Xcode 27.1、iPhone Duo / iOS 27.1：`BoneShellDemoTests` 共 157 项（1 项按系统版本跳过）连续两次运行，失败集合与 v0.13.5 基线完全一致（8 项既有失败），无新增；两次运行的失败集合彼此相同。
- Duo UI 用例 4 项通过：横栏 72 × 44、侧栏两项竖排、材质三档；另 `NavigationAdaptiveUITests` 的侧栏旋转保留用例通过。
- 公开 API 中文文档扫描 `missing=0`；`git diff --check` 无尾随空白；仓库内 Markdown 相对链接 0 失效。
- 此处为编译、单元 / 集成测试与模拟器 UI 检查，不作为真机或 Duo 全姿态矩阵验收。

## 源码结构调整（v0.13.0 发布）

容器类型位于 `Sources/BoneShellKit/Containers/`，导航声明和兼容布局位于 `Sources/BoneShellKit/Navigation/`；公开类型、模块导入方式和宿主接入方式保持不变。源码分区和维护入口见 [源码结构说明](Source-Layout.md)。

## v0.12.1 导航修复与验证

- 自定义 NavButton 在系统导航中统一由 `ShellNavButtonCluster` 作为 `UIBarButtonItem.customView` 承载，系统 item 不再同时承载自定义动作的 `primaryAction`、标题和图标。
- 自定义 confirmation 保留确认语义和优先级，使用自定义按钮外观；普通 confirmation 继续使用 UIKit `.done`。
- iOS 15–26 兼容宽度预算在一侧没有 action 时把剩余空间交给另一侧。页面重新出现后重新提交按钮与分组，避免 push / pop 后出现空玻璃容器或按钮消失。
- iOS 26.0 模拟器上的 Demo push / pop 返回回归通过。BoneShellDemo 通用测试构建通过，iPhone 13 Pro / iOS 26.5 的真机构建、安装和启动通过；完整 Xcode 真机测试需要设备保持解锁。


## 材质表面统一（v0.14.0）

- 判断裁剪的唯一入口是 `ShellMaterialRendering.clipsContent(_:)`：iOS 26+ 的 `.systemGlass` 返回 false，其余返回 true。`ShellGlassView`、`ShellNavButtonCluster` 的组表面、兼容胶囊栏、标签附加按钮都改用它，不再各自写 `#available` 判断。
- `ShellGlassView` 在取消裁剪时用 `UICornerConfiguration.uniformCorners(radius:)` 让效果层自己画出同一半径的轮廓；业务内容仍在 `contentView` 内按圆角裁剪。新增 `glassTintColor`，`.systemGlass` 映射到 `UIGlassEffect.tintColor`，磨砂回退把它作为叠加色。
- `ShellNavButtonHost` 不再自己管理 `UIVisualEffectView`，改为持有一个 `ShellGlassView`；`ShellNavButton.Effect` 变为 `.inherited` / `.none` / `.material(ShellMaterial)`，`liquidGlass` 名称删除。
- 修复一处层级缺陷：UIKit 在首次布局时把 `imageView` 插入索引 0，导致后加的表面视图盖住图标与文字（截图确认图标消失）。`layoutSubviews` 现在把表面移回最底层。
- 验证（Xcode 27.1、iPhone Duo / iOS 27.1）：`NavButtonAppearanceTests` 8 项、`NavButtonLayoutTests` 5 项、`CapsuleBarTests` 12 项、`BarStyleTests` 6 项通过；新增 `testGlassSurfaceCarriesTintAndSkipsClipping`。`BoneShellDemoUITests/NavButtonUITests/testMaterialsAndSizeOnBarRecordEachTapOnce`（无 / 系统默认 / 系统玻璃三档，Duo 横栏）通过，截图确认图标恢复、玻璃胶囊保留边缘高光。
- 按钮组表面保持“一整块覆盖整个模块”的绘制（与系统分组玻璃一致，组内无分隔线）。曾尝试用 `UIGlassContainerEffect` 给组内每枚按钮各配玻璃元素再合并：两枚胶囊仅相接时并集轮廓在接缝处凹陷约 9 pt（44 pt 高、8 pt 净距，几何已计算验证），改为重叠后重叠区因双重折射出现 8 pt 暗带，缩小重叠到 1 pt 又完全不合并。系统分组的观感本就是连续表面，因此撤回该实现，保留单一 `ShellGlassView`。
- 修复间距归一化的两处结构缺陷，两者共同造成「完成」胶囊越出自身槽位、看起来贴到按钮边上：① `ShellNavButtonCluster.layoutSubviews` 里 `groupSurface.frame` 完全不应用 `moduleVisualOffset`，组的胶囊根本不参与归一化，而独立按钮会整体平移，两类模块规则不一致；② 归一化把每个间隙多出的空间全部推给后继模块，偏移逐级累积（实测组 0 / 详情 −4 / 完成 −8 pt）。现在组表面与组内图标一起按偏移平移，剩余量在可见范围两侧均分。
- 修复模块视觉偏移只移动图形、不移动表面的缺陷：`normalizeNavigationModuleSpacing` 按模块可见边界归零间距时，自带表面的按钮会把图标挤出圆心（Duo 截图中「详情」箭头明显偏向圆左侧）。现在 `ShellNavButtonHost` 让表面、图标和标题一起偏移，`moduleVisualBounds` 在按钮自带表面时返回表面外框。
- 同一缺陷的另一半：`titleRect(forContentRect:)` 原先完全不参与偏移，文字按钮（如「完成」）会被推到表面之外、贴住一侧边缘。现在标题与图标共用 `offsetContent`，自绘表面时整体平移，透明按钮仍按槽位裁剪；表面尺寸改用实际 `bounds`，不再可能比系统给的槽位更宽。
- 像素核对（iPhone 18 Pro / iOS 27.0，402 pt 宽，组 + 详情 + 完成三个模块）：可见胶囊 146..250 / 258..302 / 310..382，间隙 8 / 8 pt，图标与文字中心相对各自胶囊中心偏差 ≤0.2 pt；系统返回键作为尺度参照（实测 42.7×43.7，理论 44×44）用于校正阈值测量偏差。Duo 侧栏 44×72 竖胶囊：图标中心 (21.8, 35.8) 对按钮中心 (22, 36)。
- Duo 侧栏 UI 用例曾因默认策略统一而回归：Demo 的 `-navbutton` / `-navbutton-vertical-capsule` 原先依赖 `navButton:` 初始化器默认的 `.verticalPreferred` 才进入侧轨，改为 `.system` 后系统把按钮留在顶部栏。SDK 默认值保持 `.system`，由 Demo 的这两个测试钩子显式声明「优先侧栏」（`initialSidebarIndex`）。
- 验证（Xcode 27.1）：`NavButtonAppearanceTests` 的 `testSurfaceMovesWithModuleOffsetSoTheGlyphStaysCentered`、`testTitleAndIconStayInsideTheirSurfaceAtEveryOffset` 与真实导航栏用例 `testEveryTitleAndGlyphStayCenteredInTheirSurfaceInsideARealBar`（含组/独立按钮、触发间距归一化）断言表面中心、标题中心、图标中心三者重合，标题在其 label 内居中且宽度完整；`NavButtonLayoutTests.testSystemGlassGroupIsOneContinuousSurfaceAcrossItsWholeModule` 断言组只有一块表面、覆盖整个模块、圆角等于厚度一半、组内按钮左右对称。iPad Pro 13-inch / iOS 26 与 iPhone 18 Pro / iOS 27.0 截图确认组轮廓是一条直线、无接缝，箭头居中。
- Duo 实测（Xcode 27.1，iPhone Duo / iOS 27.1，折叠外屏 466×678）：
  - 横栏（`-navbutton-horizontal-bar`）：只有「完成」留在栏上，按钮组与「详情」由 UIKit 收进原生「更多」菜单——这是系统对「优先侧栏」轴向在无竖向栏位时的处理。修复前该项与返回键互相压叠，且胶囊只有 44 pt 高（返回键 48 pt）。
  - 侧栏：返回 / 完成 / 详情竖向排列；按钮组进入侧轨后**不拆组**，由同一个承载视图整体竖排——实测两枚按钮同列（396,239）与（396,299），组表面为一枚竖胶囊。
  - 侧栏玻璃宽度统一：像素实测系统返回键玻璃 47.7 pt、槽位 44 pt，而它的无障碍 frame 只有 38 pt。最初按 AX frame 取 38，导致组比返回键窄 10 pt（即「侧栏宽度不一致」）。现在 SDK 绘制的玻璃一律按「槽位 + 4 pt」取宽并居中，实测返回键 / 完成 / 详情 / 按钮组全部为 47.7 pt、中心 x 均为 417.8。
  - 组内按钮几何：竖排时由组表面统一绘制的模块，每枚按钮是与组玻璃同宽的正方形（48 × 48），不加额外内边距，组高 = 48 × 数量 + 组内净距（两枚、净距 8 → 104）。图标仍按调用方 `iconSize`（Demo 20 × 20）绘制，不随按钮变大而拉伸。曾试过把按钮收到 40 pt 留 4 pt 边距，会让 icon 可用区域被强行收窄，与「图标大小由调用方控制」的意图相反，已改回正方形铺满。
  - 该几何实现时踩过两个坑：① `intrinsicContentSize` 若反向依赖运行时 `bounds`，会让布局自我触发；现在侧轨槽位用常量 44 而非实时 bounds。② `frame` 只收敛高度，不强行改宽（改宽会与系统量测互相触发）。
  - 侧轨按每项 44 pt 分配槽位，容量约 3 项：Demo 默认一侧有「组 + 详情 + 完成」三项，组竖排占两项高度后系统会把放不下的项移出侧轨。以 `-navbutton-single-group` 只保留按钮组时实测正常。
- 本轮修复的四个缺陷：
  - **间距归一化把溢出模块也算进去**：进入「更多」菜单的模块仍留在 item group 里，但已不在栏位可见范围。归一化按其幽灵位置求偏移，产生 −137 pt 的偏移，把可见模块推到返回键上、文字跑出按钮（AX 实测按钮在 194…266，其标题标签却在 57…121）。现在归一化只考虑真正落在栏内的模块，并给偏移加上「不超过一个模块宽度」的上限。
  - **表面高度与系统条目不一致**：按钮自绘玻璃时表面高度改为跟随系统条目可视高度（栏高 58 → 48，栏高 44 → 44），与返回键等高；槽位和点击区域不变。
  - **侧栏里的按钮组无法竖排**：UIKit 只在提交条目时量测自定义视图，104 pt 宽的横排模块挂上 44 pt 宽侧轨后不会重新量测。现在模块检测到自己在侧轨时把自身尺寸收敛为竖排尺寸（宽 = 槽位 44、高 = 按钮高度和 + 净距）并通知页面重新提交条目；组不拆分，`layoutSubviews` 按竖轴排布按钮，表面按侧栏系统按钮的 38 pt 宽度居中绘制。侧栏判定由「整块外框都在轨道内」改为「模块中心在轨道内」，否则比轨道更宽的组永远认不出自己在侧栏。曾尝试拆成逐项条目（可用但违背「组是原子模块」的语义），已改回整组竖排。
- 真机、iPad 与 Duo 完整姿态矩阵仍未执行。

## 模块级侧栏策略（v0.14.0）

- `NavigationAction` 的动作级 `axisBehavior` 已移除，改为 `sidebarBehavior`；按钮组新增同名声明，`ShellNavButtonRun` 在收集模块时按「组优先、独立按钮取自身」解析一次，系统轴向映射和侧栏样式追踪都读取这一份结果。
- `.disabled` 使 `tracksNativePlacement` 为假，`ShellNavButtonCluster` 不再检测侧栏位置，`iPhoneDuo` 样式随之不再应用；`.preferred` / `.system` 保持既有 `isMountedInSideBar` 检测。
- 验证环境 Xcode 27.1、iPhone Duo / iOS 27.1 模拟器（`8E80DEE0-7F4D-4F53-B869-FE49733D17A1`）：`NavigationActionTests.testSidebarOverrideUpdatesAndReturnsToSystemOnSameItem` 与 `testGroupSidebarBehaviorOverridesMemberActions` 通过；`BarDemoIntegrationTests` 的 `nav.icon` / `nav.sidebar` 配置与重置用例通过。
- 同一环境下 `NavigationActionTests` 另有 8 项、`BarDemoIntegrationTests` 另有 3 项失败；以相同命令在改动前的 `HEAD` 上复跑得到完全相同的失败集合（起始 13/18 项、失败项与断言一致），因此不是本次改动引入。失败集合未修复，包含经典宽度预算、角色固定顺序、重复 ID 与 NavButton 组宽恢复；需单独排查。
- 未执行真机、iPad 或 Duo 完整内外屏 / 半折姿态矩阵；`.preferred` 的实际竖排仍以系统姿态为准。

## NavButton 与 Duo 侧栏

`NavigationAction(navButton:)` 为单项指定尺寸、图标、内边距、整项 UIView 和按钮背景。同侧兼容项可按声明顺序编组，精确控制组内净距；组外位置和原生溢出仍由 UIKit 决定。接入示例见[自定义导航动作](Navigation-Actions.md#自定义导航动作)。
- `Style.icon` 支持轴向独立图标：普通样式可显示文字，Duo 竖胶囊可显示勾号；新增单元用例验证文字 / 图标切换和短标题在侧栏限宽下不省略。

| 完整定向回归基线（Xcode 27.1，`BoneShellDemo` Scheme） | 通过 | 按系统版本跳过 | 失败 |
| --- | ---: | ---: | ---: |
| iPhone / iOS 18.6 | 33 | 7 | 0 |
| iPhone / iOS 26.0 | 33 | 7 | 0 |
| iPhone Duo / iOS 27.1 | 41 | 0 | 0 |

- 普通 iPhone 验证三种背景、组内 0 / 8 / 16 pt 净距、换序、逐项溢出回调；SDK / 集成测试另覆盖窄栏、RTL、返回键、禁用、移除、复用、字号独立及恢复默认。两端跳过的 7 项为已有的 iOS 27 / 27.1 专属导航动作测试。
- Duo 同一「完成」动作实际测得：横栏 **72 × 40 pt**，侧栏沿用普通样式 **38 × 44 pt**，覆盖竖胶囊 **38 × 72 pt**。三个状态均在栏上点击并核对回执。实际打开两端材质图及 Duo 三种状态的截图，确认栏位限宽后短标题完整、不旋转。上述横栏由公开的竖栏禁用设置取得，不代表完整内外屏开合姿态矩阵。
- 此前完整定向结果包为 `NavButton-Verified-iOS18.xcresult`、`NavButton-Verified-iOS26.xcresult`、`NavButton-Verified-Duo.xcresult`。通用 iOS 设备构建通过，Demo 产物 `MinimumOSVersion` 为 `15.0`；接入示例通过 iOS 15 目标类型检查。未运行 iOS 15 或安装真机，发布验证以当前源码的聚焦复验和通用 iOS 构建为准。
- 当前最终源码的聚焦复验：`NavButton-CurrentUnit.xcresult` 的 NavButton 单元 / 集成测试通过，`NavButton-Current-Duo-Final.xcresult` 的 Duo 三条真实栏位用例通过，`NavButton-CurrentGeneric` 的 generic iOS 构建通过。普通 iPhone 的 UI 自动化在 iOS 18.6 / 26.0 均曾出现系统导航栏状态恢复或 XCUI snapshot 延迟，日志中有按钮已点击但状态树未及时刷新、以及偶发不可命中的情况；这部分保留为自动化环境波动，未将其记为稳定的完整 UI 通过。

## 自定义导航标题

`NavigationConfiguration.titleView` 在原生和经典导航中承载完整、可交互的 `UIView`。同一页面切换导航形态时复用视图；自定义期间不额外显示标准文字、副标题或大标题，清除后恢复。详见[接入说明](Navigation-Actions.md#标题菜单与自定义按钮)。

- Xcode 27.1，iPhone 17 Pro / iOS 26.0 与 iPhone 16 Pro / iOS 18.6：两端各 **35 项通过（32 项 SDK / 集成、3 项 UI）**、0 失败；7 项仅适用 iOS 27 / 27.1 的导航动作用例按版本跳过。
- 两种导航均实测点按标题、选择来源、更新标题和恢复文字。已打开并检查两端共 8 张原图，覆盖菜单和文字恢复；另有同实例切换、推入返回、替换视图及窄栏 LTR / RTL 布局断言。
- 结果包为 `nav-title-26-press.xcresult` 和 `nav-title-18-press.xcresult`。接入示例按 iOS 15 部署目标通过类型检查；未运行 iOS 15，也未验证 iPad / Duo 竖栏或安装本次导航版本到真机。

## 整项自定义标签内容

`ShellTabBarCustomContent` 为普通标签和附加动作提供完整 `UIView`。标准图文走原有路径，两种模式可混用；自定义项不生成默认图文、不转为静态图标。详见[接入说明](Bar-Presentation.md#普通标签的自定义视图)。

- iPhone 17 Pro / iOS 26.0：44 项 SDK 测试与 2 项 UI 测试通过。iPhone 16 Pro / iOS 18.6：20 项 SDK 测试与 2 项 UI 测试通过，4 项原生 dock 测试按版本跳过。两端定向执行，0 失败。
- 两端各检查三张实图：带文字和无文字的整项视图、切换选中项、主动恢复标准模式。用例另验证整个槽位的边界、状态通知、混用、卸载与系统承载。
- 两个公开示例通过 iOS 15 部署目标类型检查。未执行 iOS 15 运行时、真机或完整 iPad / Duo 姿态验证；未改动 Shorthand 或「用心读书」。

## 动态标签栏附件（首轮开发验证）

以下是整项自定义方案之前的研发记录，仅说明当时的图标内容方案，不代表当前 API 或当前静态行为。

- **iPhone 17 Pro / iOS 26.0 模拟器**：最终定向回归 40 项 SDK / Demo 测试和 2 项标签栏 UI 测试通过。覆盖复用、布局、禁用、隐藏 / 恢复、卸载释放、原生 dock 和系统槽位；系统收起与不可见的 trait 切换通过注入检查，不等同于真实滚动收起全流程。
- **iPhone 16 Pro / iOS 18.6 模拟器**：16 项 SDK 测试和 1 项动态附件 UI 测试通过，4 项原生 dock 测试按版本跳过。兼容胶囊运行真实动效，显式 `.system` 使用静态图标且不调用工厂。
- 已打开两端实际截图对照胶囊外侧、系统槽位、静态回退与移除后的状态。iOS 26.0 原生 dock 另外保留 4.12 秒、247 帧的模拟器录屏，按钮内区域有相位变化，覆盖 Demo 的 2.4 秒循环。录屏与截图不随 SDK 发行。
- 接入示例按 `arm64-apple-ios15.0-simulator` 通过类型检查，最低部署目标保持 iOS 15；没有运行 iOS 15 真机或模拟器。对应开发验证包未作为发行产物提交，未改动 Shorthand 项目或验证其头像的完整动画循环。

## 0.10.0 导航动作自适应

新增图片图标、取消 / 确认角色和轴向偏好。iOS 27+ 原生导航使用完整动作列表、固定分组、系统优先级与溢出；经典及旧系统保留 SDK 宽度预算。按 ID 复用按钮 / 分组，尺寸与 size class 变化保留原生菜单来源。详细行为与版本边界见 [导航动作与自适应](Navigation-Actions.md)。

- Xcode 27.1、iPhone Duo / iOS 27.1：最终源码的 **52 项 SDK 单元 / Demo 集成测试全部通过，0 失败、0 跳过**。包含动作模型、角色、轴向、图片回退、回调更新 / 释放、经典 / 系统切换、样式、导航栈及安全区。
- iPhone 16 Pro / iOS 18.6：相同 52 项单元 / 集成范围 **45 通过、7 因系统版本跳过、0 失败**，两项相关 UI 用例通过；原生 iOS 27 / 27.1 专属用例不以兼容路径替代。
- 修复实际回归发现的旧系统菜单不可变问题：刷新时替换 `UIAction` 表示，保留按钮身份；经典导航改用页面实际安全区计算 SDK 自身贡献，避免约 5.7 pt 的顶部遮挡，并保留宿主 inset。
- 新增 11 项 SDK、3 项 Demo 集成、2 项 UI 用例。Duo 两项 UI 最终分批通过：原生侧边栏 / 系统溢出、主要与菜单动作各执行一次、自定义图片打开详情、输入保存及朝向请求后状态保留。已打开截图确认实际栏位、模板图标与原色图片；完整内外屏开合、半折和分屏姿态矩阵仍未完成。
- 新增接入示例以 iOS 15 Simulator 为部署目标通过类型检查；文档链接 / 代码围栏及 `git diff --check` 另行核对。

本轮功能结果包包括 `Navigation-Duo-Complete.xcresult`、`Navigation-iPhone18-Complete.xcresult`、`Navigation-Duo-UI-Stable.xcresult`（采用其中通过的菜单用例）、`Navigation-Duo-Input-UI.xcresult` 与 `Navigation-iPhone18-UI-Final.xcresult`。原始结果、截图与逐文件校验保留本地，不随 SDK 发行；本页保留结果摘要。分批结果不描述为一次完整运行，也不与下方历史回归合并计数。本阶段未提供任意自定义 UIView、加载 / badge 或经典竖向 renderer。

上述功能回归执行时 Demo 为 0.9.0（Build 1）；v0.10.0 发布准备仅调整版本元数据、版本展示及文档，SDK 与测试源码保持通过回归的内容。发布构建独立核对，不将其描述为重新执行了全部功能用例。

v0.10.0 发布检查：从拟提交 Git 树导出干净副本，在 Xcode 27.1 上以 arm64 iOS Simulator 目标完成 `build-for-testing`，SDK、Demo 与正式测试目标全部构建通过；产物版本为 0.10.0（Build 1），最低系统为 iOS 15，Demo 与 UI Runner 的 codesign deep / strict 校验通过。发行树的 13 份 Markdown、121 处本地链接 / 锚点以及版本与测试接线检查通过。此处为编译与产物检查，不作为重新运行 UI 或真机验收。

## 0.8 既有实现

| 范围 | 已有能力 |
| --- | --- |
| 页面与原生容器 | 一次性构建内容、配置刷新、独立标签导航栈、原生双栏封装、安全区与按页键盘避让 |
| 栏位 | 自动 / 经典 / 胶囊 / 系统四种请求；导航实际为系统或经典；页面与容器覆盖、恢复及状态保留 |
| 样式与图标 | 导航四类文字、标签普通 / 选中态、Dynamic Type、SF Symbol / 本地图片 / UIImage、选中颜色 / 原图策略、按 ID 更新 |
| 附加动作 | 经典栏内、兼容胶囊外侧、原生 dock、显式系统槽位或旧系统 tab item；动作不改变选中项，回调替换与移除后释放 |
| 浮动内容 | 主滚动视图经过胶囊后方，保留宿主 inset；默认 80 pt 渐隐、可关闭、保留宿主 mask |
| 背景 | 三处分区或整体画布，图片 / GIF / APNG / MP4 / HTML，后台准备、缓存合并、预取与按 Scene 播放预算 |
| Demo | “示例 / 材质 / 关于”三个根标签；导航和标签设置拆页，背景、表单、返回 / sheet、分栏等真实入口 |

详细公开接口与未实现的设计见 [SDK 范围](SDK-Plan.md)；使用方式见 [README](../README.md)、[栏位模式](Bar-Presentation.md)、[样式](Bar-Styling.md) 和 [背景](Backgrounds.md)。

## 0.9.0 标签文字显示策略与验证

新增 `ShellTabLabelDisplayMode`（`.always / .never / .selectedOnly / .unselectedOnly`）、`ShellTabBarStyle.labelDisplayMode`（默认 `.always`）、条目与两种 `ShellTab` 初始化器上的可选覆盖（默认 `nil`）。页面样式整份覆盖包含该字段；文字隐藏时保留语义标题、无障碍名称和图标居中。此 API **自 v0.9.0 提供，v0.8.0 不包含**。

Demo 新增 `tabbar.labels` 四段开关，状态显示“文字：…”，reset 回到 `.always`。集成测试覆盖 picker、配置、单条目覆盖、旧设置与栈保留；UI 用例 `testLabelDisplayModesAcrossClassicNativeCapsuleAndDock` 保留经典 / 原生胶囊无附件 / 原生 dock 左右附件 × 四策略共 12 张截图，另留 3 张切到关于的截图。仅选中模式往返关于 / 示例并验证设置页、实际选中项及 AX 名称。

| 本次验证项 | 当前结果 |
| --- | --- |
| SDK / Demo 编译与单元 / 集成执行 | 97 通过 / 0 失败 / 0 跳过，包含新增 8 项 SDK 与 2 项 Demo 集成测试 |
| 标签栏及选中图标 UI 回归 | 6 项 `TabBarUITests` + 2 项 `TabSelectedIconUITests`，8 通过 / 0 失败 / 0 跳过 |
| 文字策略矩阵与实际截图 | 经典 / 原生胶囊 / 原生 dock × 四策略 12 张，另有切到关于 3 张，共 15 张最终运行原图已保留 |
| 视觉与几何 | 已打开原图与对比：文字显示符合策略、隐藏文字后图标居中、无文字裁切，切页后原生选中外观正确；经典 / 兼容胶囊另有真实 label 隐藏及中心点断言，既有 dock 附件对齐断言通过 |
| 发布包构建 | Demo 0.9.0（Build 1）generic iOS 重新构建通过，产物版本与 codesign deep / strict 校验通过；未将构建视为真机运行 |
| 本次开发包真机安装 | iPhone 13 Pro / iOS 26.5 覆盖安装并启动成功，安装记录、应用版本及运行进程分别核对；仅确认安装与启动，未执行真机四策略完整回归 |
| 文档检查 | 含更新记录的 10 份 Markdown、97 处本地链接 / 锚点、25 段 SDK Swift 示例、2 段包声明、2 段 Shell 命令通过；XcodeGen 重生成结果与测试工程一致 |
| 旧系统与辅助设置 | 兼容胶囊通过能力注入单元测试；实际 iOS 15–25、iPad / Duo、VoiceOver、RTL 及完整辅助字号矩阵未执行 |

文字策略功能回归在 **Xcode 27.1、iPhone 13 Pro / iOS 26.0** 上单次执行 **105 项（97 单元 / 集成 + 8 UI）全部通过**，结果包为 `bone-shell-label-final-regression.xcresult`；执行时 Demo 版本为 0.8.0（Build 1），功能源码已提交为 `bd7a7f6`。本地原图、栏位 / 切页对比及源文件校验保存在 `Documentation/Verification/Tab-Labels-Development/`。用例范围与定向参数见 [测试规划](Demo-Test-Plan.md#文字策略用例)。下列 109 个唯一用例仍为 0.8 分批历史基线，不与本次合并计数。

此前安装到真机的文字策略开发包版本为 **0.8.0（Build 1）**，包含当时尚未发布的新增功能，不能仅凭版本号将其等同于 `v0.8.0` 标签内容。v0.9.0 发布准备已将 Demo 版本调整为 0.9.0（Build 1）；Swift 源码与上述通过回归的版本保持一致，发布构建和签名另行核对，不将其描述为重新执行了全部 105 项。

## 0.8 既有功能验证（历史基线）

编译环境为 Xcode 27.1、Swift 5 模式、iOS 15 部署目标；模拟器为 **iPhone 13 Pro / iOS 26.0**。

| 检查 | 已执行范围 | 结果 |
| --- | --- | --- |
| SDK 单元 / Demo 集成 | 最终 dock 实现上的全部当前单元与集成用例 | 87 通过 / 0 失败 / 0 跳过 |
| 标签栏 UI | 5 项设置、连续附加按钮切换、标签可达性、列表下滚动和 14 pt 图片图标文字检查 | 5 通过 / 0 失败 / 0 跳过 |
| 其他 UI | 最近完整回归中的背景、基础导航 / 表单 / 材质 / sheet、导航设置、选中图标；后续 dock 修改不经过这些路径 | 17 通过 / 0 失败 / 0 跳过 |
| 真机目标构建 | generic iOS | 构建与 codesign deep / strict 校验通过 |
| 实际画面 | 原生 / dock 的 14 pt 图片图标、菜单展开、“无 → 左 → 右 → 左右 → 无”、列表在玻璃后方滚动 | 原图已打开比较；文字完整、无残留重复栏位，按钮与原生基线对齐 |

合计 **109 个唯一用例：87 单元 / 集成 + 22 UI**。这是分批结果，不能描述为最终源码一次完整运行 109 项全部通过。最新 92 项（87 + 5）结果包为 `bone-shell-commit-final-regression.xcresult`；其余 17 项取自 `bone-shell-commit-complete.xcresult` 的通过范围，旧标签 UI 失败范围由最新 5 项完整重跑覆盖，按测试 ID 去重。

历史 0.8 签名包曾安装并启动于 iPhone 13 Pro / iOS 26.5，应用版本与运行进程已分别查询确认。该安装发生在最终代码整理之前，不作为 `9f758a1` 的真机功能回归。

## 已知功能边界

- SDK 默认 `.system`，Demo 默认 `.automatic`；导航没有独立胶囊形态。原生 dock 由独立 `UITabBar` 与圆按钮组成，不具有容器原生栏位完整的滚动收起联动。
- iOS 26 原生 dock 的非选中文字颜色受 UIKit 玻璃合成影响；实际观察到传入蓝色后仍呈系统深色。属性传递、字号、完整行高和图标原色分别验证，不保证最终文字颜色的像素一致性。
- 键盘避让默认关闭，开启后使用键盘 layout guide，明确不跟随未停靠键盘。固定内容与主滚动内容采用不同的底部边界策略。
- 图像缓存成本是软限制，不是整个进程内存上限。HTML 失去播放名额或离屏后释放网页，回来会重载；同配置整体画布切页复用是特例。
- 没有通用 adapter、App / Scene 配置层、目的地侧栏 / 分组、导航分组 / 加载 / badge 声明、未保存编辑保护或 SwiftUI 桥接产品。

## 尚未完成的验收

| 范围 | 当前状态 |
| --- | --- |
| iOS 15–25 实际 runtime | 已在 iOS 18.6 执行导航相关回归；其他旧版 runtime 及完整功能矩阵仍未完成，能力注入不替代实际运行 |
| iPad / Duo、窗口变化与双栏折叠 | 原生容器与通用布局已接入；完整设备 / 姿态及状态矩阵未完成；无 Duo 保留区域或铰链专项 |
| 多 Scene、RTL、完整辅助字号 | 有 Scene 根容器与预算分组；完整专项未执行 |
| 返回与输入 | 返回按钮、部分实际边缘返回和停靠键盘有历史验证；完整交互返回取消、浮动 / 分离 / 硬件键盘矩阵未完成 |
| APNG 与网络资源 | APNG 有 ImageIO 路径但没有独立素材验收；远程资源端到端回归未执行 |
| Instruments | FPS、峰值内存与耗电尚未测量，不以测试耗时、缓存计数或策略常量代替性能数据 |

## 0.8 既有文档对齐检查（历史记录）

| 检查 | 结果 |
| --- | --- |
| 正式文档结构 | 7 份现行说明与 2 份归档；历史草案、旧安装 / 提交状态不作为当前接口依据 |
| 本地链接与锚点 | 9 份 Markdown、78 处仓库内链接 / 锚点通过，代码围栏完整 |
| 公开 API 示例 | 抽取现行文档 20 段 SDK Swift 示例，补充已注明由宿主提供的页面 / 回调 / 参数上下文后，以 iOS 15 Simulator 目标通过类型检查 |
| 包声明与命令 | 2 段 Package 依赖声明按 PackageDescription 5.9 通过类型检查；2 段 Shell 命令通过语法检查 |
| Demo 与目标编号 | 10 个实际目录入口与源码一致；D01–D15、T01–T37 连续完整 |
| 读者检查 | 构建基线、默认值、未实现范围、键盘 / 滚动、附件路径及验证来源 6 个问题可直接从现行说明回答，未发现阻塞 |

这些是当时的文档和示例静态检查，不验证示例素材是否存在，也不代表本地新增文字策略的 App 运行、UI 验收或示例类型检查。上述结果保留为 0.8 历史记录，本次增量结果记录在上方独立小节。

## 复现与材料

构建命令见 [README](../README.md)，现有入口、自动化范围与 T01–T37 目标见 [Demo 与测试说明](Demo-Test-Plan.md)。UI 修改需保留实际截图并打开检查，构建成功、无障碍树数量或中间 frame 断言不能单独证明画面正确。

本地 `Documentation/Verification/` 保存导出的原图、对比与逐用例清单；`.bone-project-wiki/` 保存协作记忆。它们及外部临时目录中的 xcresult / 日志不属于 SDK 源码提交，干净检出不应依赖这些材料才能构建。

旧版记录独立保留在 [0.1–0.6 历史验证](Archive/Implementation-History.md)，完整设计设想见 [归档草案](Archive/Design-Draft.md)。历史中的“本轮 / 当前 / 安装 / 提交状态”均以当时修订为准。
