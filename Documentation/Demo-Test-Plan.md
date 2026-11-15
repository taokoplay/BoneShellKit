# Demo 入口与测试规划

既有能力基线：**0.8.0（Build 1），功能修订 `9f758a1`**。标签文字显示策略增量**未发布，仅当前本地开发源码，v0.8.0 不包含**；新增用例另行验证。本文件区分实际入口、现有自动化和后续验收目标；D01–D15、T01–T37 是规划追踪 ID，不是页面数或 XCTest 通过数量。执行结果见 [验证记录](Implementation-Status.md)。

## 1. 实际工程与入口

`Examples/BoneShellDemo/BoneShellDemo.xcodeproj` 是 UIKit Universal App，通过本地 `../..` 引用 SDK。共享 Scheme 为 `BoneShellDemo`，不依赖远程服务、账号或宿主业务工程；运行与重新生成命令见 [README](../README.md#运行-demo-与测试)。

底部三个根标签为“示例 / 材质 / 关于”，稳定 ID 分别为 `tab.examples`、`tab.materials`、`tab.about`。示例目录实际提供：

| 页面 | 入口 ID | 当前可操作内容 |
| --- | --- | --- |
| 导航与多按钮 | `scene.navigation` | 增减右侧操作、主操作与 SDK 更多菜单、切换导航材质、进入详情 |
| 背景与切页 | `scene.backgrounds` | 图片 / GIF / MP4 / HTML、五种作用区域、1 或 3 个动态名额、预取 / 清缓存切页、连续切换 |
| 导航栏 | `scene.navigation-bars` | 标题字号 / 颜色、副标题、大标题、按钮字号、继承 / 系统 / 经典、输入详情、恢复默认 |
| 标签栏 | `scene.tab-bars` | 字号 / 颜色、三种图标来源、选中策略、自动 / 经典 / 胶囊、左右附加动作、背景、恢复默认；本地未发布增量新增文字显示四种策略 |
| 窗口与安全区 | `scene.adaptive` | 当前窗口、内容区域、尺寸类别和安全区信息；不是 Duo 姿态模拟器 |
| 表单与键盘 | `scene.form` | 输入、保存、停靠键盘避让 |
| 标签状态保留 | `scene.state` | 输入后切换标签再返回，观察输入和当前栈 |
| 返回与弹出页面 | `scene.transitions` | 详情 push、原生返回、系统 sheet 与关闭 |
| 玻璃材质对照 | `scene.material` | 自动 / 原生玻璃 / 仿玻璃 / 实色的 SDK 表面与实际解析信息 |
| 列表与详情分栏 | `scene.split` | 全屏打开原生双栏演示，由 UIKit 按空间展示；完整折叠 / resize 矩阵待验收 |

导航和标签设置已拆为两页，旧“栏位字体与图标”“栏位类型”独立入口已移除。导航页恢复为继承标签模式；标签页恢复 `.automatic`，清除附加动作和页面背景。目录部分页尾提示仍沿用早期规划文字，当前经典 / 兼容胶囊能力以 [SDK 范围](SDK-Plan.md) 为准。

本地开发的文字开关 ID 为 `tabbar.labels`，四段标题为“始终显示 / 始终隐藏 / 仅选中 / 仅未选中”，依次对应 `.always / .never / .selectedOnly / .unselectedOnly`。状态含“文字：…”，reset 恢复 `.always`；改变策略时保留字号、颜色、图标、选中图标策略、形态、附件、背景、原有根控制器与导航栈。

## 2. 启动参数

可在 Xcode Scheme 的 Run Arguments 设置下列参数：

| 参数 | 实际作用 |
| --- | --- |
| 无模式参数 | 请求 `.automatic` |
| `-classic-bars` | 请求经典模式 |
| `-capsule-bars` | 请求胶囊模式 |
| `-system-bars` | 请求 UIKit 原生模式；标签设置页的模式 picker 本身只有自动 / 经典 / 胶囊 |
| `-tabs-accessory leading` / `trailing` / `both` | 启动时展示附件组合；这些启动附件的 handler 为空，只用于外形检查 |
| `-ui-testing` | 关闭 UIView 动画；不伪造系统版本、能力或测试结果 |

模式参数冲突时按 classic → capsule → system 顺序选择。需要验证点击回执时，进入“标签栏”页使用该页的附加动作设置；旧系统路径需实际 runtime 或测试能力注入分别记录。

## 3. D01–D15 场景状态

| ID | 追踪范围 | 0.8 当前状态 |
| --- | --- | --- |
| D01 | 最小页面接入 | 已有页面基类、内容区域与示例；README 提供公开 API 示例 |
| D02 | 导航与多按钮 | 已有标题、左右动作、整数优先级、禁用与 SDK 更多菜单；分组 / 加载 / badge / 菜单树仍规划 |
| D03 | 标签与独立导航栈 | 系统 / 经典 / 胶囊、独立栈与状态保留已实现；SDK 侧栏 / 分组模型未实现 |
| D04 | 列表详情自适应 | 原生双栏 Demo 已有；完整展开 / 折叠和状态专项待执行 |
| D05 | 材质对照 | SDK 自有表面及能力降级已有；任意品牌 renderer 与完整系统换肤不在当前接口中 |
| D06 | 安全区与键盘 | 安全区、浮动栏下滚动和按页停靠键盘避让已有；完整键盘 / resize 矩阵待执行 |
| D07 | 返回、转场与编辑保护 | push / pop、sheet、输入保留已有；未保存编辑保护未实现，交互取消专项待补齐 |
| D08 | 无障碍与本地化 | 有动态字体、材质降级和控件标识；VoiceOver、RTL、完整辅助设置实机矩阵待执行 |
| D09 | 多窗口 | 每 Scene 建根容器、媒体预算分组已有；同时运行多个 Scene 的隔离专项未执行 |
| D10 | 既有页面 adapter | 未实现通用 adapter；复用已有 UIKit 控制器不等于 adapter 完成 |
| D11 | 多媒体背景 | 独立 / 整体、缓存、预算、切页已有；APNG 独立素材和远程端到端未验收 |
| D12 | 导航栏设置 | 已独立成页，集中导航文字、按钮及模式 |
| D13 | 栏位类型 | 合并在 D12 / D15 的设置内，四种 SDK 模式已有 |
| D14 | 标签附加动作 | 合并在 D15，各栏位模式及系统槽位 / 旧 tab item 承载已有 |
| D15 | 标签栏设置 | 已独立成页，集中样式、图标、模式、附件及背景 |

## 4. 正式测试接线与范围

| 层级 | 源码 / 目标 | 当前覆盖 |
| --- | --- | --- |
| SDK 单元 | `Tests/BoneShellKitTests/`，9 份测试源；Package test target `BoneShellKitTests` | 配置 / 材质解析、动作去重与优先级、样式与图像像素、文字显示策略、四模式、附件、底部渐隐、缓存 / 预算、整体画布 |
| Demo 集成 | `Examples/BoneShellDemo/Tests/`，3 份测试源 | 公开 API 接入真实容器、设置生效、输入与内容身份、背景与条目保留 |
| Demo UI | `Examples/BoneShellDemo/UITests/`，5 份测试源 | 背景、基础导航 / 表单 / sheet / 材质、导航设置、标签设置与附加动作、选中图标 |
| 视觉 / 设备 | 实际截图、真机运行、后续 Instruments | 裁切、重叠、原生玻璃、位置 / 间距 / 投影、姿态、辅助设置与性能 |

Demo 的 `BoneShellDemoTests` 同时编译上述 SDK 和 Demo 集成源；`BoneShellDemoUITests` 编译 UI 源，共享 Scheme 已包含这两个目标。现有测试不依赖独立的 `.xctestplan` 文件；`DemoSmoke.xctestplan`、`DemoRegression.xctestplan` 尚未创建。

将相应选择参数追加到 README 的 `xcodebuild test` 命令即可缩小范围：

- 单元 / 集成：`-only-testing:BoneShellDemoTests`
- 全部 UI：`-only-testing:BoneShellDemoUITests`
- 标签栏 UI：`-only-testing:BoneShellDemoUITests/TabBarUITests`
- 单用例：`-only-testing:BoneShellDemoUITests/TabBarUITests/testCapsuleAccessoriesMakeASingleDockRow`

文件数量、测试方法数量和历史执行通过数量分别统计。能力注入可检查旧版分支，不能替代真实旧版 runtime；测试中的条件 skip 必须按实际结果记录。

### 本地开发的文字策略用例

以下测试源码随未发布增量加入，不能引用 0.8 的历史通过数作为这些用例的执行结果：

| XCTest 方法 | 检查范围 |
| --- | --- |
| `TabLabelDisplayTests`（8 项） | 四策略与兼容默认值、原生选中态、单项覆盖及自定义 AX、经典 / 兼容胶囊隐藏真实 label 和图标居中、dock 模型身份、页面覆盖恢复、原生及经典“更多”名称 |
| `BarDemoIntegrationTests.testTabLabelPickerAppliesAllModesWithoutRebuildingRoots` | `tabbar.labels` ID、四段文案 / 映射、页面和容器配置、状态文字、语义标题、条目继承、内容与根控制器身份 |
| `BarDemoIntegrationTests.testTabSelectedOnlyLabelsPreserveSettingsAndNavigationAfterTabSwitch` | 仅选中策略、单条目覆盖、关于 → 示例后设置页和导航栈、旧设置、选中项与无障碍名称保留 |
| `BarDemoIntegrationTests.testTabPresentationAndResetRestoreDefaults` | 既有 reset 用例扩展：文字策略、页面 / 容器样式、picker、状态恢复 `.always` |
| `TabBarUITests.testLabelDisplayModesAcrossClassicNativeCapsuleAndDock` | iOS 26+ 上经典、原生胶囊无附件、原生 dock 左右附件 × 四种文字策略；仅选中时往返关于 / 示例，检查设置页、选中项与 AX 名称，再验证 reset |

UI 矩阵新增一个 case，保留 **12 张策略全屏截图与 3 张切到关于的截图**。策略附件名为 `Tab labels <classic/native-capsule/native-dock> <always/never/selectedOnly/unselectedOnly>`，切页附件追加 `selectedOnly about`，均为 `.keepAlways`；iOS 26 以下明确 skip，不能记作原生路径通过。定向参数为 `-only-testing:BoneShellDemoUITests/TabBarUITests/testLabelDisplayModesAcrossClassicNativeCapsuleAndDock`。AX 名称必须保留，不能据自动化树中的文字名称判断视觉隐藏；需打开原图核对文字、图标居中、裁切及选中外观，并与几何断言分别记录。执行、导图与视觉结论见 [本地验证记录](Implementation-Status.md#本地开发增量标签文字显示策略)。

## 5. T01–T37 验收目标与现状

下表保留目标追踪。“已有覆盖”表示存在对应正式检查，不代表整行目标或全部设备矩阵已验收；实际通过环境与数量统一见 [验证记录](Implementation-Status.md)。

| ID | 验收目标 | 当前覆盖 / 待补范围 |
| --- | --- | --- |
| T01 | D01 最小接入 | 已有标题、动作、内容和配置刷新检查 |
| T02 | D02 操作溢出 | 已测 SDK 宽度 / 优先级选择与更多菜单动作恰好执行一次；没有系统 item groups 分支 |
| T03 | D02 长标题与字号 | 已有大字号动作预算与部分实际画面；极端字体 / 窗口矩阵待补 |
| T04 | D02 返回与 leading 动作 | 已有保留返回语义和详情检查；完整手势矩阵待补 |
| T05 | D03 标签切换 | 已有各标签导航栈、输入、选中项与内容身份保留检查 |
| T06 | D04 双栏变化 | 有原生 Demo；完整展开 / 折叠、编辑状态与 resize 专项待执行 |
| T07 | D05 高版本材质 | 已测 SDK 表面请求 / 解析和点击；系统菜单与键盘仍归 UIKit |
| T08 | D05 低版本材质 | 已有能力注入解析；实际 iOS 15–25 runtime 待运行 |
| T09 | D05 降级诊断 | 已有 systemGlass 不可用及减少透明度解析；没有通用 renderer 无效组合协议 |
| T10 | D06 输入与安全区 | 已有停靠键盘、内容边界检查；浮动 / 分离 / 硬件键盘矩阵待补 |
| T11 | D07 交互返回取消 | 返回和部分实际边缘返回有历史结果；完整取消专项未完成 |
| T12 | D08 无障碍与 RTL | 有字体 / 材质解析及控件标识；完整系统设置与 RTL / VoiceOver 实机专项待补 |
| T13 | D09 Scene 隔离 | 根容器与媒体分组已有；多窗口同时编辑和切换的专项未执行 |
| T14 | D10 adapter 接入 | API 和 Demo 均未实现 |
| T15 | D11 独立背景 | 已测三处配置、显式 none 覆盖和内容实例保留 |
| T16 | D11 缓存与切页 | 已测请求合并、命中、清理、文件 / 外观失效与返回恢复 |
| T17 | D11 动图与预算 | 已测首帧准备、预算 3 降 1、离开标签停止；不等于 APNG 独立验收 |
| T18 | D11 视频与 HTML | 已测本地 MP4 / HTML、原生栏位背景和内容交互；远程资源待补 |
| T19 | D11 快速切换与失败 | 已测最新资源、过期结果隔离与损坏资源回退 |
| T20 | D11 性能 | 尚未执行 Instruments FPS、峰值内存、耗电测量 |
| T21 | D12 导航文字 | 已有字体属性、文字操作与部分标题截图检查 |
| T22 | D15 标签文字与图标 | 已测三种 Appearance 布局属性与当前实际画面；所有原生布局实机矩阵待补，dock 非选中文字颜色有系统边界 |
| T23 | D12 / D15 继承与恢复 | 已测 nil 继承、空样式、按钮 tint 恢复与背景协作 |
| T24 | D12 / D15 动态更新 | 已测动态字体解析和更新后状态；最大辅助字号矩阵待补 |
| T25 | D11 整体画布 | 已测共享坐标、单一名额、同配置切页媒体实例复用及退出恢复 |
| T26 | D13 模式继承 | 已测 SDK 默认 system、容器继承和页面覆盖 / 清除；Demo 单独默认 automatic |
| T27 | D13 经典布局 | 已测全宽底栏、普通按钮、安全区增量及页面出栈恢复 |
| T28 | D13 动作 / 换图 / 更多 | 已测事件、图标与更多入口；更多目的地完整 UI 流程可继续扩展 |
| T29 | D13 状态与返回 | 已测反复切换、输入、栈和选中项；完整手势取消另列 T11 |
| T30 | D13 背景与兼容 | 已有整体背景和模式协作；旧 runtime 与全设备矩阵待补 |
| T31 | D15 选中图标 | 已测颜色轮廓、原图像素、透明区域、回退和运行时状态 |
| T32 | D13 自动 / 显式模式 | 已测能力解析及当前系统 UI；启动参数不伪造系统能力 |
| T33 | D13 胶囊几何 | 已测当前运行环境的内缩、尺寸、命中、选中及安全区；兼容路径使用能力注入 |
| T34 | D13 下滚动与渐隐 | 已测视口到底边、保留 inset / mask、渐隐开关、经典恢复及实际滚动截图 |
| T35 | D15 dock 几何与文字 | 已测原生基线、圆按钮等高、12 pt 间距、投影，以及图片图标 / 14 pt 文字完整性 |
| T36 | D15 附件承载 | 已测 26+ dock / 系统槽位及旧 tab item 注入路径 |
| T37 | D15 连续切换与恢复 | 已测五种连续状态、唯一标签标识、动作单次回调、回调替换、释放与栈 / 选中项保留 |

T22 的历史覆盖不包含本地新增的 `labelDisplayMode`。本次文字策略集成 / UI 用例与截图矩阵已独立验证并记录于 [本地验证结果](Implementation-Status.md#本地开发增量标签文字显示策略)。

## 6. 待运行矩阵与交付规则

| 运行环境 / 专项 | 目标 |
| --- | --- |
| iOS 15–25 实际 runtime | 验证旧版布局、材质、键盘和返回；不虚构 iOS 16 系统分组实现 |
| iOS / iPadOS 26 | 原生玻璃、四模式、附件、辅助设置与当前颜色边界 |
| iOS / iPadOS 27.1 | 实际轴向行为回归；Duo 另立姿态与保留区域专项，不以 API 编译代替 |
| iPad 宽 / 窄窗口及动态 resize | 原生双栏、当前详情 / 输入和四边安全区 |
| 多 Scene、RTL、VoiceOver 与辅助字号 | 隔离、阅读 / 操作顺序与文字可达 |
| 资源与性能 | APNG 独立素材、远程资源、真实低电量 / 辅助设置和 Instruments |

每次执行记录源码修订、工具链、实际 OS / 设备、初始配置、模式和通过 / 失败 / 跳过范围。界面改动除行为回归外，必须导出实际屏幕、保留原图和不同状态对比，并打开检查裁切、栏位数量、间距、投影、切换残留与点击；不能只用构建成功、无障碍计数或中间 frame 断言判定画面正确。

结果包与截图输出到独立临时 / 验证目录，不随 SDK 源码提交。1.0 发布前应将支持声明收敛到有实际运行和视觉证据的范围；规划验收未完成时明确标注，不扩展当前的通过结论。
