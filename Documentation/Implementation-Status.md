---

# BoneShellKit 0.5 实现与验证记录

记录时间：2026-11-11T15:41:20.905267+08:00。当前交付：**0.5.0（Build 1）**。已安装并启动于已授权手机，随后独立查询确认进程存在。

### 本轮实现

增加 `ShellBarPresentation.system / .classic`，将栏位形态与真实系统版本、字体和材质区分。经典类型使用平直导航、普通返回 / 操作按钮、细分隔线和全宽底部标签，参考 iOS 26 以前的风格。SDK 默认 system；Demo 默认 classic，首页“栏位类型”可切换。

标签容器设置默认类型，导航可以继承或单独设置；页面以 `ScreenConfiguration.barPresentation` 覆盖当前管理的导航 / 标签。类型切换保留原生容器、控制器身份、导航栈和输入。字体 / 颜色、普通 / 选中图标、badge、更多目的地与独立 / 整体背景继续可用。

经典导航通过自有 UIView 显示内容并保留原生导航容器与手势；经典标签通过公开 API 停用原生标签呈现，使用至少 49 pt 内容高度的全宽底栏。SDK 分别跟踪导航顶部和底栏的安全区贡献，切回系统后移除自身贡献，不要求业务重复计算栏高。

接入与边界见 [系统与经典栏位](Bar-Presentation.md)，字体和背景分别见 [样式](Bar-Styling.md) 与 [背景](Backgrounds.md)。

### 最终执行结果

| 检查 | 环境 / 范围 | 结果 |
| --- | --- | --- |
| SDK / Demo 构建 | Xcode 27.1、Swift 5、iOS 15 部署目标 | 通过 |
| SDK 单元测试 | iPhone 13 Pro 模拟器，iOS 26.0；含新增 7 项类型检查 | 38 项通过 |
| Demo 集成测试 | 同上 | 17 项通过 |
| Demo UI 测试 | 同上；7 背景 + 4 类型 + 3 样式 + 4 基础 | 18 项通过 |
| 最终通过范围 | 库代码一致的单元 / 集成范围与最终 UI 范围 | **73 个唯一用例通过：55 单元 / 集成 + 18 UI；两个范围各自 0 失败** |
| 实际画面核对 | 经典 / 系统 / 经典整体背景截图 | 普通导航按钮、全宽底栏及原生类型恢复分别核对 |
| 真机包 | iOS generic destination、当前开发团队 | 0.5.0 构建成功，codesign strict 验证通过 |
| 手机交付 | 已授权设备 | 0.5.0 安装、启动成功，后续进程查询通过 |

两组结果分别留证，不把初次失败的完整运行写成单次全通过。库源码在这两组最终通过范围之间未改变；后续修正仅涉及 Demo 选择页避免在布局时覆盖用户选择，以及 UI 测试等待目标位置稳定 / 键盘不遮挡后再交互。最终 UI 已覆盖这些修正。

新增 SDK 检查覆盖默认值与页面覆盖、原生 alpha / 可访问性恢复、反复切换后的控制器 / 导航栈 / 输入保留、底栏全宽与安全区增量、经典按钮事件无重复、运行时条目更新、整体画布及字体复用、详情隐藏底栏，以及超过五个目的地的更多入口。

UI 实际验证 Demo 默认经典、切回系统后再恢复经典、输入页直接切换类型与切换标签后保留输入、经典整体背景，以及原生边缘返回手势。原有系统类型测试显式通过 `-system-bars` 启动；这些参数只选择 SDK 类型，不伪造真实 OS。

截图检查曾发现透明经典导航与正文重叠。新增布局断言确认后，SDK 增加逐页管理的顶部安全区贡献；最终检查要求安全区正文位于经典导航下方，且不存在重复导航占位。上述结果以修正后的最终源码和结果包为准。

### 范围与未执行矩阵

- 运行时测试环境为 iOS 26.0 模拟器；iOS 15 检查部署目标和 API availability，未执行真实 iOS 15–25 runtime。
- 经典类型是 SDK 的旧版风格，不是特定旧 OS 的逐像素复刻。系统菜单、键盘、Sheet 和内容材质仍按真实系统及各自配置呈现。
- iOS 27.1 的经典类型显式选择横向栏位；系统类型仍采用系统轴向适配。Duo 全姿态、iPad 宽 / 窄窗口、RTL、辅助字号与外接键盘完整矩阵尚未全部运行。
- 返回按钮和实际边缘返回已验证，完整交互返回取消及复杂自定义父容器仍需对应设备验收。
- 经典模式下的 `isTabBarHidden` 指原生标签呈现，不等于经典栏位不可见；自有只读诊断视图见 API 文档。
- 本轮没有执行 Instruments 帧率、峰值内存或耗电测量；UI 自动化关闭 UIKit 动画，不以执行时长证明转场性能。

### 证据与复现

打开 Demo 的共享 Scheme 或按 [README](../README.md) 重新生成工程。完整目标见 [测试规划](Demo-Test-Plan.md)。临时证据保留在执行会话目录，不纳入源码：

- 单元 / 集成：`bone-shell-classic-tests-final.xcresult` 中通过的 Unit test bundle；`bone-shell-classic-unit-summary-final.json`。
- 最终 UI：`bone-shell-classic-ui-final.xcresult`，18 通过 / 0 失败 / 0 跳过；`bone-shell-classic-ui-summary-final.json`。
- 成功截图：`bone-shell-classic-attachments-ready/`；对照页：`bone-shell-classic-visual-check.html`。
- 签名 / 设备 / 安装 / 启动 / 进程：`bone-shell-classic-signed-app-final.json`、`bone-shell-classic-phone-result.json` 及对应设备 JSON。
- 汇总：`bone-shell-classic-verification.json`；源码 / 工程规格 / 图标指纹：`a76f65386064487a19a4e2964e5c5006aaa10100ab8ef1f990c46fb068cd3672`。

---

## 历史：BoneShellKit 0.4 实现与验证记录

记录时间：2026-11-11T13:36:56.793896+08:00。当前交付：**0.4.0（Build 1）**；已签名安装并启动于 iPhone 13 Pro，随后独立查询确认进程存在。

### 本轮修正

此前 Demo 的“全部”把相同资源分别交给页面、导航、标签三个背景视图，导致各自裁切、独立播放，且播放预算为一个时其余区域显示静态表示。

0.4 增加 `ShellBackgroundComposition.unified`：以 `screen.background` 创建一个完整容器尺寸的画布，统一图像坐标、裁切和媒体时间。导航与标签的独立背景暂时停用；同配置 push / pop 复用画布与媒体，退出后恢复宿主表面。Demo 的“全部”改用整体模式，“分区”保留三个独立区域。字体、颜色、图标和原生导航行为继续保留。

接入与范围见 [背景文档](Backgrounds.md)，样式见 [栏位字体与图标](Bar-Styling.md)。

### 实际执行结果

| 检查 | 环境 / 范围 | 结果 |
| --- | --- | --- |
| SDK 与 Demo 构建 | Xcode 27.1、Swift 5、iOS 15 部署目标 | 通过 |
| SDK 单元测试 | iPhone 13 Pro 模拟器、iOS 26.0；12 基础、11 背景、4 样式、4 整体背景 | 31 项通过 |
| Demo 集成测试 | 同上；4 基础、5 背景、8 样式 | 17 项通过 |
| Demo UI 测试 | 同上；7 背景、3 样式、4 基础导航 / 标签 | 14 项通过 |
| 最终覆盖 | 两个不重叠的最终测试范围 | **62 个用例通过；48 单元 / 集成 + 14 UI** |
| 视觉与实例检查 | 全屏图像 / GIF 截图、分段色带像素、WKWebView 身份 | 三处同一画面；预算三个时整体仅一份播放；同资源 HTML 切页复用 |
| 真机签名 | iOS generic destination，当前开发团队 | 0.4.0 构建成功；codesign strict 验证通过 |
| 手机交付 | 已授权 iPhone 13 Pro | 0.4.0 安装、启动成功；之后再次查询确认进程存在 |

首轮完整运行的 UI 测试包 14 项全部通过；新单元测试曾直接调用生命周期，导致详情未完成正常加载。修正仅涉及测试驱动与等待，不改生产 / UI 源码；之后全部 48 项单元及集成测试通过。上述 62 是两个最终通过范围的唯一用例数，不把首轮失败记录算成单次全通过。

整体背景测试验证：不创建重复区域媒体、容器默认值停用与恢复、push / pop 画布身份保留、一个 HTML 与一个播放名额、同资源切页 WKWebView 复用、退出释放，以及整屏分段色带的实际像素与 bounds 变化。UI 覆盖图片、GIF、MP4、HTML、预算、返回、标签离开暂停、分区模式与原有字体 / 图标功能。

### 验证边界

- iOS 15 已检查部署目标与 API availability，未运行真实 iOS 15 runtime。iPad / Duo 全姿态、完整 RTL 和辅助设置矩阵仍未全部执行。
- UI 自动化运行于 iOS 26.0 模拟器；手机本轮验证签名、安装、启动和进程，没有把模拟器 UI 结果记为真机 UI 自动化。
- 同配置切页和返回已验证；完整交互返回取消、分栏及复杂自定义父容器矩阵仍需专项验收。
- 不透明业务内容会正常覆盖共享背景；系统玻璃前景保留 UIKit 的局部光学表现。
- 本轮未进行 Instruments 帧率、峰值内存与耗电测量。当前通过的是渲染连续性、生命周期、实例复用和功能回归。

### 复现与证据

构建、Package 接入和 Demo 入口见 [README](../README.md)，完整目标用例见 [测试规划](Demo-Test-Plan.md)。本轮临时证据保留在执行会话目录，不纳入仓库：

- 单元 / 集成：`bone-shell-unified-unit-tests-2.xcresult` 与 `bone-shell-unified-unit-summary.json`。
- UI：`bone-shell-unified-tests-1.xcresult` 中通过的 UI test bundle，以及 `bone-shell-unified-ui-summary.json`。
- 截图：`bone-shell-unified-ui-attachments/`、`bone-shell-unified-unit-attachments/`；核对页 `bone-shell-unified-visual-check.html`。
- 签名 / 安装 / 启动 / 进程：`bone-shell-unified-signed-app.json`、`bone-shell-unified-install.json`、`bone-shell-unified-launch.json`、`bone-shell-unified-processes.json`。
- 综合记录：`bone-shell-unified-verification.json`；36 份源码 / 规格 / 图标资源指纹：`e81f24bdc0c0579e95b742f03a253835b66ba07adcbefa2a0e79251fc99230bd`。

---

### 历史：BoneShellKit 0.3 实现与验证记录

记录时间：2026-11-11T12:44:44.350744+08:00。当前签名包：**0.3.0（Build 1）**。

SDK、Demo、文档和签名包已完成。手机连接处于断开状态，本轮 0.3.0 未安装；最近一次成功的手机安装为 0.2.0，见下方历史记录。

#### 0.3 新增能力

- `ShellTextStyle` 接受 UIFont 或字号 / 粗细、UIColor，以及 Dynamic Type / 固定字号策略。
- `ShellNavigationStyle` 分别设置普通标题、大标题、副标题和按钮文字；支持导航容器默认值、页面整份覆盖与恢复宿主 / 系统外观。
- `ShellTabBarStyle` 设置普通 / 选中态的字体、文字颜色和图标颜色，覆盖 stacked、inline、compact inline 布局及滚动边缘 Appearance。
- `ShellTabIcon` 支持 SF Symbol、bundle 资源图片与 UIImage；普通和选中图标可以分别提供，原有 `ShellTab(symbol:)` 调用保持可用。
- `updateTabItem(id:configuration:)` 更新既有条目，保留选中控制器、各标签导航栈、业务输入及稳定标识；未知 ID 不产生修改。
- 模板图标明确指定颜色时，SDK 按当前 traits 生成显示图像，兼容原生未选中图标未采用 tint 的情况；原色 UIImage 保留自身颜色。
- 标题和文字按钮使用实际字体测量，窄屏操作可进入原生更多菜单。样式与现有图片 / 动图 / MP4 / HTML 背景共同应用，不修改全局 UIAppearance。
- Demo 新增“栏位字体与图标”：字号、颜色、资源图 / 原色图、独立选中图标、恢复默认与详情输入保留。

接入入口见 [栏位字体、颜色与图标](Bar-Styling.md)；原有多媒体背景见 [背景文档](Backgrounds.md)。

#### 最终执行结果

| 检查 | 实际环境 / 范围 | 结果 |
| --- | --- | --- |
| SDK 与 Demo 编译 | Xcode 27.1、Swift 5、iOS 15 部署目标 | 通过 |
| SDK 单元测试 | iPhone 13 Pro 模拟器、iOS 26.0；12 基础规则 + 11 背景 + 4 样式 | 27 项通过 |
| Demo 集成测试 | 同上；4 基础 + 4 背景 + 8 样式 | 16 项通过 |
| 导航与样式 UI 回归 | 同上；4 基础导航 / 标签 / 材质 + 3 样式 | 7 项通过 |
| 最终结果包汇总 | `bone-shell-style-tests-final.xcresult` | **50 通过，0 失败，0 跳过** |
| 实际截图核对 | 模板颜色、原色图、字体与复位 / 输入 | 模板普通蓝色 / 选中橙色及原色图的显示分别核对 |
| iOS 真机签名包构建 | generic iOS destination，当前开发团队 | 0.3.0 构建成功；codesign strict 验证通过 |
| 手机授权配置 | 签名包 embedded.mobileprovision | 包含已授权 iPhone |
| 手机安装 | 已配对 iPhone 13 Pro | 连接不可用，安装返回 CoreDevice 4016；0.3.0 未安装 |

最终选择运行全部 SDK / 集成测试，以及 `BarStyleUITests` 和 `BoneShellDemoUITests`。最终代码没有重跑六项 `BackgroundUITests`，不把它们计入上述 50 项。图标渲染修正之前的一轮完整结果为 55 通过；该结果属于先前源码，不作为最终源码的完整回归结果。

新增检查覆盖 Dynamic Type 与固定字体、实际字体属性、三种标签布局、页面继承 / 空样式恢复、背景叠加、文字操作溢出、按钮颜色 push / pop 恢复、图标正常 / 选中资源、更新后控制器与输入保留，以及模板与原色图的输出像素。 SF Symbol 的透明边缘另有像素断言。目录新增场景后，基础 UI 导航 helper 调整为先将整行滚到标签栏上方，再点击；原有业务断言保留，最终四项基础 UI 回归全部通过。

#### 当前边界与安装阻塞

- 运行测试使用 iOS 26.0 模拟器。iOS 15 是部署和 availability 编译检查，没有执行真实 iOS 15 runtime；iPad / Duo 全部姿态、完整 RTL、最大辅助字号和深浅色设备矩阵尚未运行。
- 字号不会强制增加原生栏位高度；截断、折叠与紧凑显示仍由系统决定。系统更多菜单文字和玻璃返回图标保留 UIKit 自身的表现。
- 字体与颜色更新保留内容实例。页面样式是整份覆盖值，nil 字段保留 UIKit 值；需要局部继承时先复制容器样式再修改。
- 模板图标的显式颜色按当前 traits 生成图像，SF Symbol 使用适合标签栏的 25 pt 图形；原色 UIImage 不参与重着色。图标采用本地资源，远程下载由宿主负责。
- 本轮未进行 Instruments 帧率、峰值内存或耗电测量；UI 自动化关闭 UIKit 转场动画，测试耗时不代表真实转场性能。
- 手机安装的唯一阻塞是连接：设备列表显示 unavailable / disconnected，直接安装返回 CoreDevice 4016。本轮没有成功安装、启动或查询 0.3.0 手机进程；已有签名包可在设备重新可连接后继续安装。

#### 复现与证据

打开 `Examples/BoneShellDemo/BoneShellDemo.xcodeproj` 的 `BoneShellDemo` Scheme，首页进入“栏位字体与图标”。命令入口见 [README](../README.md)，完整目标见 [测试规划](Demo-Test-Plan.md)。

最终证据保留在会话临时目录，未加入源码：

- 结果包：`bone-shell-style-tests-final.xcresult`；汇总：`bone-shell-style-test-summary-final.json`。
- 成功截图：`bone-shell-style-attachments-verified/`；核对页：`bone-shell-style-visual-check.html`。
- 最终签名：`bone-shell-style-signed-app-final.json`；手机状态：`bone-shell-style-devices-final.json`；失败安装：`bone-shell-style-install.json`。
- 综合证据：`bone-shell-style-final-verification.json`。
- 34 份源码、工程规格与图标资源的 SHA-256 指纹：`154f1088fd89b729c137e021504441ebe552be983d3ec5892ec05b66ceeb3804`；清单：`bone-shell-style-source-final.json`。

---

#### 历史：BoneShellKit 0.2 实现与验证记录

记录时间：2026-11-11T11:26:57.901262+08:00。安装包版本：**0.2.0（Build 1）**。本轮交付无阻塞。

##### 已实现

- Swift Package，最低部署目标 iOS 15，Swift tools 5.9 / Swift 5 语言模式，无第三方依赖。
- 薄页面基类与原生导航、标签、列表详情分栏容器；配置更新保留业务内容实例、原生返回与独立标签导航栈。
- 带稳定 ID 和优先级的导航操作、更多菜单、安全区域、停靠键盘避让与新旧版材质降级。
- 页面、导航栏、标签栏三处独立多媒体背景：图片、GIF / APNG、MP4、HTML；支持海报、遮罩、裁切、底色、状态与诊断。
- 图片 / 首帧后台缩略解码、128 像素尺寸桶、重复请求合并、文件版本与外观缓存键、默认 48 MB 共享图片软缓存。
- 切页预取图片与海报；页面出现后动态播放、离开时暂停；每 Scene 默认一个动态名额，可设为 0–3，页面 / 导航 / 标签依次优先。
- 静音循环 MP4，HTML 获得名额后才创建，离屏即停止并释放；内存警告、低电量和辅助设置采用对应的释放或静态策略。
- 离线 Demo 素材与“背景与切页”场景，可切换资源、区域、播放名额，比较预加载 / 清缓存切页并连续切换 8 次。

背景接入及实际限制见 [多媒体背景](Backgrounds.md)。

##### 实际执行结果

| 检查 | 环境 | 结果 |
| --- | --- | --- |
| 背景引擎及其测试独立类型检查 | Xcode 27.1 SDK，Swift 5，iOS 15 Simulator 部署目标，warnings-as-errors | 通过，零警告 / 错误 |
| SDK 基础规则测试 | iPhone 13 Pro 模拟器，iOS 26.0 | 12 项通过 |
| SDK 背景引擎测试 | 同上 | 11 项通过 |
| Demo 集成测试 | 同上 | 8 项通过，其中背景集成 4 项 |
| Demo UI 测试 | 同上 | 10 项通过，其中背景 UI 6 项 |
| 最终 XCTest 结果包汇总 | `xcresulttool get test-results summary` | **41 通过，0 失败，0 跳过** |
| 媒体与栏位截图核对 | 最终 UI 测试保留的四张成功截图 | 三处图片 / 动图、独立导航 HTML、标签 MP4；导航标题与按钮可见 |
| 真机构建与签名 | Xcode 27.1，当前开发团队 | 0.2.0 构建成功，codesign strict 验证通过 |
| 安装与启动 | 连接的 iPhone 13 Pro，iOS 26.5 | 0.2.0 已安装并启动；随后独立查询确认进程存在 |
| 源码一致性与清理 | 测试 / 签名后逐项比对源码指纹 | 26 份源码与工程规格保持一致；仅关闭本次专用测试模拟器 |

最终测试覆盖缓存合并 / 命中 / 清理、清除在途请求后不复用旧任务、文件与外观失效、损坏图片回退、旧加载结果隔离、尺寸桶复用、GIF 首帧预取、离屏 HTML、弱引用释放，以及三处配置和内容身份保持。

UI 回归验证三处图片和返回恢复、GIF 标签切换后暂停、动态名额从三个降为一个、独立导航 HTML 与标签 MP4、快速切换最终资源和 HTML 背景下的内容交互；原有材质、主操作 / 更多菜单、Sheet 和标签输入 / 导航栈保留也全部通过。

背景使用系统栏位后方的独立视图，避免进入原生栏位内部后遮住前景。除了可访问性和媒体状态断言，新增针对 Demo 浅色素材的导航标题像素检查，并人工查看成功截图，确认标题、返回和下一页按钮实际显示。

##### 已实施的性能策略与测量边界

静态图片最长边 2048 像素，动图 1024 像素；原始图片 / 动图分别限制 64 MP / 16 MP，文件 / 下载最多 32 MB。动图按需解码，不创建完整帧数组，帧缓存最多三帧、成本限制 12 MB；超过 600 帧时保留静态首帧并报告原因。图片准备队列最多两个并发任务。

48 MB 是共享 NSCache 的成本软限制，不包含可见图片、AVPlayer 或 WebKit 进程全部占用。MP4 暂停后可保留播放器与静态画面以便返回；HTML 离屏释放，回到页面重新加载。远程 MP4 与 HTML 不承诺完整离线缓存。

本轮验证的是功能、缓存复用与生命周期，没有执行 Instruments 的 FPS、峰值内存或耗电测量。UI 自动化启动时关闭 UIKit 转场动画以稳定行为检查，因此不能用其运行时长证明真实转场流畅度。

##### 当前验证边界

- iOS 15 已检查部署目标与 API availability，未在真实 iOS 15 runtime 上运行。
- UI 自动化实际运行于 iOS 26.0 模拟器；手机确认签名、安装、启动与后续进程存在，没有把模拟器 UI 结果记成真机 UI 自动化。
- iPad / Duo 全部姿态、原生竖向栏位、完整多 Scene、辅助字号、RTL 和真实低电量 / 辅助设置设备矩阵尚未全部运行。
- GIF 有本地 Demo 和自动化；APNG 走 ImageIO 多帧路径，本轮未使用单独 APNG 素材运行验收。远程网络资源的端到端测试未执行。
- 完整自定义栏位渲染器、严格经典外观、全局 / Scene 分层配置和完整 adapter 仍属后续研发范围。
- 键盘避让当前覆盖停靠键盘；浮动 / 分离键盘和交互返回取消的完整设备矩阵仍需专项验收。
- 原生透明 Appearance 只控制公开 API 范围，浮动栏位裁切与系统按钮玻璃仍由系统决定。

这些是尚未执行的扩展验收，不阻塞本轮多媒体背景与 Demo 交付。

##### 复现与证据

打开 `Examples/BoneShellDemo/BoneShellDemo.xcodeproj` 的 `BoneShellDemo` Scheme，首页选择“背景与切页”。构建和测试命令见 [README](../README.md)，完整目标矩阵见 [测试规划](Demo-Test-Plan.md)。

本轮证据保留在会话临时目录，未放入源码：

- 最终结果包：`bone-shell-background-tests-2.xcresult`。
- 汇总：`bone-shell-background-test-summary-2.json`。
- 成功截图与清单：`bone-shell-background-attachments-2/`；四图核对页：`bone-shell-background-visual-check.html`。
- 真机签名 / 安装 / 启动 / 进程：`bone-shell-background-signed-app.json`、`bone-shell-background-install.json`、`bone-shell-background-launch.json`、`bone-shell-background-processes.json`。
- 汇总交付证据：`bone-shell-background-final-verification.json`。
- 26 份源码与工程规格的 SHA-256 指纹：`b93cbd5a9b518d3d8a5a2dc6d3d277cd30f5712ef29532a6654fcf2593041112`，逐文件清单：`bone-shell-background-final-source.json`。

##### 0.1 历史基线

0.1.0（Build 1）在 2026-11-11 已完成基础骨架与 Demo；iOS 26.0 模拟器 20 项测试通过（12 规则、4 集成、4 UI），并安装启动于同一 iPhone 13 Pro（iOS 26.5）。其结果包为 `bone-shell-tests-2.xcresult`，汇总为 `bone-shell-test-summary.json`。当时 15 份源码与工程规格指纹为 `5120006091fc6fa79282983317bda39629d003f1f2a9ac9fbaffb7da4dd51d28`。本轮结果以上方 0.2 记录为准。
