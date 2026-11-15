# 更新记录

已发布版本按 Git 标签记录。接入方式见 [README](README.md)，实际执行范围见 [验证记录](Documentation/Implementation-Status.md)。

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
