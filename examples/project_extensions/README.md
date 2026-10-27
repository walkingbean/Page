# 项目与扩展示例

复制本目录到可写位置，在 PAGE Editor 中选择为 Content Folder。打开 story.dtl 后 Play，或在 Project & Extensions 中 Run project。

- Host 单例监听两类原生信号，并提供计数和异步方法。
- DemoExtension 注册自定义事件、子系统、编辑器、立绘、动画和布局层。
- 在 Resources 选中 editor.tscn，点击 Open selected editor。编辑文本后用 Save editor 选择新的 .cfg 输出；Open native config 可重新打开。
- 选中脚本可 Edit selected source，使用查找、保存和外部修改保护。
- 可预览 main.gd 改名计划；主场景中的路径会随提交更新。
- Export native project 移交到新目录后，使用固定 Godot 4.7.1 导入并运行。示例自身不重复分发插件，移交时补齐固定 Dialogic 2.0-alpha-20。

目标预览使用独立资源及用户数据副本；运行结果不自动同步回源目录。自定义编辑器保存的 .cfg 是用户显式选择的原生文件。

移交目录首次在固定 Godot 中打开前，先执行 `godot --headless --editor --import --recovery-mode --path 移交目录`，再正常打开。此步骤先准备固定插件所需图标，不修改固定插件。保留原生 .import 和 .uid 文件。

示例的原生样式 styles/ProjectExample.tres 使用随包 Noto Sans CJK SC 显示中文角色名和对白，字体许可位于 fonts/LICENSE.txt。该配置随原生工程移交，不依赖 PAGE 应用界面的字体设置。
