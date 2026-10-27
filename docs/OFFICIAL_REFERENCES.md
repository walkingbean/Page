# PAGE Editor 0.7.0 官方资料

本版兼容目标固定为 Godot 4.7.1 / Dialogic 2.0-alpha-20。开发细节对照指定版本源码；在线文档用于补充与核对，不自动改变兼容目标。

| 官方资料 | 对应事项 |
|---|---|
| [Godot 4.7 导出工程](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html) | 标准版、导出模板和实际可执行程序 |
| [Godot 4.7 Windows 导出属性](https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformwindows.html) | 图标、modify_resources、产品名、文件描述和数字版本 |
| [Godot 4.7 Windows 应用图标](https://docs.godotengine.org/en/4.7/tutorials/export/changing_application_icon_for_windows.html) | EXE 资源与图标生成 |
| [Godot ConfigFile](https://docs.godotengine.org/en/4.7/classes/class_configfile.html) | 集中产品配置的 INI / Variant 表达 |
| [Godot 文件路径](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html) | 应用 res://、内容目录与 user:// 的区分 |
| [Dialogic 变量](https://docs.dialogic.pro/variables.html) | 标量初值、字面量赋值、文本引用及后续变量能力 |
| [Godot 4.7 ProjectSettings](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html) | project.godot 中的原生项目设置 |
| [Dialogic 文本](https://docs.dialogic.pro/writing-texts.html) | 文本替换与后续效果处理 |
| [Dialogic 时间线语法](https://docs.dialogic.pro/timeline-text-syntax.html) | .dtl 文本、角色引用与注释 |
| [Dialogic 角色与立绘](https://docs.dialogic.pro/characters-and-portraits.html) | .dch、显示名称、默认立绘与资源 |
| [Dialogic 角色事件](https://docs.dialogic.pro/event-character.html) | join / leave 和位置参数 |
| [Dialogic 引用管理](https://docs.dialogic.pro/reference-manager.html) | 角色身份、文件引用与资源依赖 |

源码关注位置：Dialogic 的 CharacterResourceLoader / Saver、DialogicResourceUtil、Text / Character 事件与 Portraits 子系统；Godot 的项目配置、资源导出和 Windows 平台导出器。产品配置只影响 PAGE Editor 的应用身份，保留第三方 API 和资源语义。

## 字面量语义核对资料

- https://docs.dialogic.pro/variables.html
- https://docs.dialogic.pro/timeline-text-syntax.html
- https://docs.dialogic.pro/classes/class_dialogicvariableevent.html
- https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_basics.html
- https://docs.godotengine.org/en/stable/classes/class_expression.html

网络文档用于辅助；行为以随包 Alpha 20 event_variable.gd、subsystem_variables.gd、subsystem_expression.gd 与 Godot 4.7.1 真实执行为准。特别核对字符串去引号、字符串内预处理、字面值名称遮蔽以及动态 SET 类型。未修改第三方插件源码。

## 0.0.4 表达式核对

- [Godot 4.7 Expression](https://docs.godotengine.org/en/4.7/classes/class_expression.html)
- [Godot 4.7 表达式求值](https://docs.godotengine.org/en/4.7/tutorials/scripting/evaluating_expressions.html)
- [Dialogic 变量](https://docs.dialogic.pro/variables.html)
- [Dialogic VariableEvent](https://docs.dialogic.pro/classes/class_dialogicvariableevent.html)
- [Dialogic 文本](https://docs.dialogic.pro/writing-texts.html)
- [Godot 4.7.1 官方发行](https://godotengine.org/download/archive/4.7.1-stable/)

本版核对实际引擎 core/math/expression.cpp 的运算优先级、左结合和 eager 操作数求值；核对固定插件 get_variable 的先查变量再求值、execute_string 的预处理和全串替换顺序、VariableEvent 的类型分类及 SET 动态类型、parse_variables 的原始匹配列表与全串替换。类文档页面可能标注其他 Alpha 版本，差异以提供的 Alpha 20 源码及实际执行为准。未修改第三方插件代码。

## 0.0.5 单层条件核对

本次检索日期：2026-10-24（UTC+8）。

- [Dialogic 时间线语法](https://docs.dialogic.pro/timeline-text-syntax.html)：if / elif / else 与缩进。
- [Dialogic ConditionEvent](https://docs.dialogic.pro/classes/class_dialogicconditionevent.html)：condition_type 和 condition。
- [Dialogic 变量与条件](https://docs.dialogic.pro/variables.html)：条件表达式及真值转换。
- [Godot Expression](https://docs.godotengine.org/en/stable/classes/class_expression.html)：parse、execute 与错误检查。

以资料库中固定版本源码为准，核对 Modules/Condition/event_condition.gd、Modules/Core/event_end_branch.gd、Modules/Core/subsystem_expression.gd、Resources/timeline.gd 与 Resources/event.gd；引擎核对 core/math/expression.cpp 和 Variant 真值规则。在线文档不保证描述 Alpha 20 的全部边界，实际验证使用指定原生参考工程。

重点差异：条件直接 execute_string，不使用 VAR 的裸名直查；未命中分支跳至内部 EndBranch；匹配后其余兄弟分支跳过；空分支与文件结尾的 EndBranch 生成以原生 parser 实际结果为准。Alpha 20 在空格缩进 EOF 按字符数补 EndBranch。本版对照原生事件顺序和真实播放，不修改插件实现。


## 0.1.0 嵌套条件与条件文本核对（2026-10-25）

- https://docs.dialogic.pro/timeline-text-syntax.html ：原生 if / elif / else 与缩进；本版以固定 Alpha 20 的 timeline.gd 实际解析为准。
- https://docs.dialogic.pro/text-modifiers.html ：条件文本 `[if {Expression} 真文本/假文本]` 与可省略假文本。
- https://docs.dialogic.pro/variables.html ：变量、表达式、条件引用；本版仅实现已声明的标量范围。
- https://docs.godotengine.org/en/stable/classes/class_expression.html ：Expression.parse/execute 和错误读取。
- addons/dialogic/Resources/timeline.gd：缩进回退和空分支生成 EndBranch，EOF 按缩进字符数补齐；没有改动该原生行为。
- Modules/Core/subsystem_expression.gd：原始正则匹配列表、全局替换、strip_edges 与空文本相邻空格处理。
- Modules/Core/index.gd 与 Modules/Text/subsystem_text.gd：条件修饰符 order 20，变量 order 30。未选择分支不进行变量插值；条件表达式本身仍按匹配列表逐一求值。
- Modules/Core/event_end_branch.gd：嵌套分支跳出与 elif/else 跳过。参考工程双向比对用于验证实际行为。

官方在线文档可能已更新；交付与比对固定于资料库提供的 Godot 4.7.1 / Dialogic 2.0-alpha-20 源码，不用新版语法替换固定版本。

## 0.2.0 选项与流程核对（2026-10-25）

- [Dialogic Jump、Label、Return](https://docs.dialogic.pro/jump-event.html)：无目标 Jump 重启当前时间线，Jump/Return 使用调用栈。
- [Dialogic 原生时间线语法](https://docs.dialogic.pro/timeline-text-syntax.html)：选项缩进、条件及跨时间线标识。
- [Dialogic Choices 子系统](https://docs.dialogic.pro/classes/subsystem_choices.html)：条件隐藏、禁用、显示按钮、选择和无有效选项的处理。
- [Godot 导出工程](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)：导出模板、导出预设、命令行导出与资源包含/排除。

具体以固定源码 Modules/Choice/event_choice.gd、subsystem_choices.gd、node_choice_button.gd、Modules/Jump/event_jump.gd、event_label.gd、event_return.gd、subsystem_jump.gd、Modules/End/event_end.gd、Core/DialogicGameHandler.gd、DialogicResourceUtil.gd 和 Resources/timeline.gd 为准。

核对重点：Choice 额外参数保留字符串值；else 的默认行为由内容工程配置提供；全不可选时采用原生 AUTO_SKIP。Jump 固定时间线资源，标签在执行时可展开变量；重复标签选择第一个；Return 恢复跳转之后，空栈结束。原生事件 deferred 执行，因此应用的运行错误检查置于事件派发之前。解析先分配完整资源图再设置引用，可保留合法循环。原生事件、资源和子系统文件保持未修改。

## 0.3.0 角色与立绘依据

- https://docs.dialogic.pro/characters-and-portraits.html：别名、描述、默认和多立绘、变换。
- https://docs.dialogic.pro/event-character.html：JOIN / UPDATE / LEAVE、位置与动画属性。
- https://docs.dialogic.pro/layered-portraits.html：原生分层预设及 show/hide/set。
- https://docs.dialogic.pro/custom-portraits.html：原生立绘接口和资源覆盖。

固定源码：Resources/character.gd、Modules/Character/event_character.gd、subsystem_portraits.gd、subsystem_containers.gd、DefaultAnimations/、Modules/HighlightPortrait/、Modules/LayeredPortrait/。2026-10-25 核对网页与指定源码；网页存在跨版本差异时使用固定源码，例如 fade_length、ignore_char_scale 及原生动画命名。PAGE 未修改这些插件代码或资源。

## 0.3.0 场景身份与清理核对补记

2026-10-25 核对 [Godot TSCN 格式](https://docs.godotengine.org/en/stable/engine_details/file_formats/tscn.html)、[Godot UID 说明](https://godotengine.org/article/uid-changes-coming-to-godot-4-4/)、[Dialogic 分层立绘](https://docs.dialogic.pro/layered-portraits.html) 与 [CharacterEvent](https://docs.dialogic.pro/classes/class_dialogiccharacterevent.html)。文档描述通用结构；兼容判定以指定 4.7.1 原生 ResourceSaver 输出和 Alpha 20 源码、实际双向测试为准。

原生保存产生的节点 `unique_id`、场景及外部资源 `uid` 在编辑后保留；预览按内容根中的显式路径校验资源，不借用应用 UID 注册表解析目标图片。Alpha 20 的 `paused=false` setter 即使原来未暂停也会调用子系统 `_resume`；PAGE 关闭时先停止并释放本次动画节点，清空原生状态后才在必要时恢复暂停状态。原插件文件未修改。

## 0.4.0 文本、样式与交互

核对日期：2026-10-26（UTC+8）。

- https://docs.dialogic.pro/writing-texts.html
- https://docs.dialogic.pro/text-effects.html
- https://docs.dialogic.pro/text-modifiers.html
- https://docs.dialogic.pro/styles-and-layouts.html
- https://docs.godotengine.org/en/4.7/tutorials/ui/bbcode_in_richtextlabel.html
- https://docs.godotengine.org/en/4.7/classes/class_fontfile.html
- https://godotengine.org/download/archive/4.7.1-stable/

以用户指定 04-dialogic2alpha20_godot4.7.1.zip 原始工程和随附 Alpha 20 源码为直接依据。核对 Text/Event、Text/Input 子系统、AutoAdvance/AutoSkip、Style/DialogicStyle/DialogicStyleLayer、Setting/Settings、Wait/WaitInput、Clear、TextInput 及 DefaultLayoutParts 的公开导出字段。原生 Setting 写全局 Save 的行为在独立预览期间隔离；不改插件实现。文本效果顺序、随机选择和样式继承等语义以该固定版本实际执行为准。

### 固定原生版本运行差异的实测记录

- `Settings/subsystem_settings.gd:38` 对已有设置值直接使用 `!=`。原始工程实测布尔值改为字符串会产生脚本错误；PAGE 在执行前诊断不兼容的类型切换，保留源文本与插件字节。整数与浮点数互换仍允许。未声明默认值的设置可先 reset，再赋新类型；已声明默认值应使用相同类型或先修改默认配置。
- 原生 TextInput 出现后若在文本框隐藏动画尚未结束时立即提交，参考工程曾出现下一段文本停在揭示状态的现象；日志和 25 秒超时轨迹保留。双向正常输入对照等待原生动画完成后提交，这不构成快速输入场景已通过的结论。

- 独立原生对照确认：`auto_advance.gd` 初始 `delay_modifier` 为 1.0，`Settings._reload_settings()` 只载入默认字典，不发出变更信号。因此原生工程启动时设置的 `autoadvance_delay_modifier` 默认值不会立即影响计时；后续 Setting 事件真正改变该值才触发更新。PAGE 按这一固定版本行为预览，保存的原生默认键仍原样保留。
- 原生预设包含的布局层不同。预览遇到缺少正文、选择或 TextInput 所需布局层时明确提示补齐；Text Bubble 基座需配合其动态文本气泡层。

### 富文本效果的观察依据

Godot 官方 [BBCode 文档](https://docs.godotengine.org/en/stable/tutorials/ui/bbcode_in_richtextlabel.html#fade) 将 fade 定义为逐字符静态透明度渐变；wave、tornado、shake、rainbow、pulse 可随时间改变。测试等待原生文本框入场结束，只比较文字区域；fade 与无标签对照比较，避免把文本框入场动画当作字形效果。此项核对日期为 2026-10-26（UTC+8），实际运行仍使用固定 4.7.1 引擎。

## 0.5.0 媒体与状态核对

- [Godot 运行时文件加载](https://docs.godotengine.org/en/4.7/tutorials/io/runtime_file_loading_and_saving.html)：外部图片、WAV/OGG/MP3 的运行时加载。
- [Dialogic 存读档](https://docs.dialogic.pro/saving-and-loading.html)：原生状态与保存槽。
- [Dialogic Audio](https://docs.dialogic.pro/classes/class_dialogic_audio.html)、[Voice](https://docs.dialogic.pro/classes/class_dialogic_voice.html)、[TypeSounds](https://docs.dialogic.pro/classes/class_dialogicnode_typesounds.html)：通道、语音、打字声音。
- [Dialogic 文本效果](https://docs.dialogic.pro/text-effects.html)、[角色与立绘](https://docs.dialogic.pro/characters-and-portraits.html)：mood 与角色字段。

固定源码：Modules/Background、Audio、Voice、History、Save、Text/node_type_sounds.gd，Core/DialogicGameHandler.gd、DialogicSaveState 资源与 Variable/subsystem_variables.gd。网页描述与固定代码不同时，以随包 Alpha 20 为兼容依据。已保留 History 保存开关、大小写动作、Save Default 序列化等差异；详细证据在独立测试进度包。存档适配保持原生子系统 API，但稳定资源引用与完整性验证属于 PAGE 预览环境。

0.5.0 补充核对固定源码 `DialogicResourceUtil.gd` 的事件索引顺序、`Variable/event_variable.gd` 的 `set` 前缀识别及 `Settings/event_setting.gd` 的 `setting` 识别。原始参考工程在执行614中复现前者先命中；PAGE 应用层调整顺序的执行506通过，原生差异仍保留。背景生命周期另核对 `Background/subsystem_backgrounds.gd`：无布局 holder 时清理提前返回，身份字段不会重置；PAGE 在移除布局前取消过渡，原生清理后明确清空身份，执行547–551验证实际节点、像素与关闭/重启。以上为 0.5.0 的历史核对记录，未修改插件；0.6.0 的对应结果以本版独立测试进度为准，不复用这些通过状态。

## 0.6.0 术语与多语言核对（2026-10-27）

- [Dialogic Translation](https://docs.dialogic.pro/translation.html)：稳定标识、CSV、原文语言与收集流程。
- [Dialogic Glossary](https://docs.dialogic.pro/glossary.html)：术语、别名和翻译后的高亮/弹窗。
- [Godot Internationalizing games](https://docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html)：locale、Translation、CSV 与回退。

固定源码位置：Resources/event.gd、Resources/character.gd、Editor/Settings/CoreSettingsPages/settings_translation.gd、Modules/Glossary/glossary_resource.gd 与 subsystem_glossary.gd，以及 Godot core/string/translation_server.cpp。线上 Glossary 文档将 entries 描述为 Array，但固定 alpha-20 的 `@export var entries := {}` 实际是 Dictionary，别名以字符串指向主条目。本版采用固定字典结构。Character._translation_id 没有 @export，Resource.duplicate 不自动保留它，编辑候选和运行副本均显式复制。昵称的原生译文分隔符是逗号加空格，术语 alternatives 使用逗号。

Godot 4.7.1 内部的 fallback getter/setter 未向 GDScript 暴露。PAGE 预览用会话 Translation 副本合并原文回退消息并恢复宿主翻译资源；收集到目标工程时登记原生 internationalization/locale/fallback。未修改固定插件来绕开差异。逐资源 CSV 的原生命名对同名文件可能冲突，PAGE 明确拒绝冲突，保留原文件。


## 固定引擎的弹出菜单差异

提供的 Godot 4.7.1 源码 `scene/gui/popup.cpp`、`scene/gui/option_button.cpp` 与 `scene/main/window.cpp` 用于核对 Popup 可见父窗口连接、原生窗口选项与坐标转换。本版最小复现分别运行编辑器引擎和 release 模板：嵌入式 Popup 在 release 模板关闭时记录重复断开连接错误，原生 Popup 没有此错误。应用只对本版新增的五个下拉菜单使用原生 Popup，并将按钮坐标转换到桌面坐标，保留屏幕边界限制。未修改固定引擎或 Dialogic 插件。具体复现、失败和实际成品界面证据在独立进度包中。

## 0.7.0 项目、宿主与扩展（2026-10-27）

- https://docs.godotengine.org/en/stable/classes/class_projectsettings.html
- https://docs.godotengine.org/en/stable/classes/class_resourceuid.html
- https://docs.godotengine.org/en/stable/classes/class_pckpacker.html
- https://docs.dialogic.pro/creating-extensions
- https://docs.dialogic.pro/dialogic-signals.html
- https://docs.dialogic.pro/custom-portraits.html

固定源码核对：Godot `core/io/resource_uid.cpp`、`file_access_pack.cpp`、`pck_packer.cpp`、`logger.cpp`、`core/config/project_settings.cpp`、`main/main.cpp`、LinuxBSD/Windows 的 `os_*` 和 `export/export_plugin.cpp`；Dialogic `Core/index_class.gd`、`DialogicResourceUtil.gd`、Signal/Call、`Editor/dialogic_editor.gd`、Portrait/Animation/Style 及 Text 索引。

实测差异：固定 release 模板不允许 `--main-pack`，因此发布预览按该版本原生资源段和 PCK 尾部格式生成临时独立程序。PCK V3/V4 文件偏移相对于包起点；ELF 64 位资源段大小和 PE pck SizeOfRawData 随包同步。发布版默认不立即刷新普通日志，预览配置显式开启 `application/run/flush_stdout_on_print`。固定子系统安装回调是 `_post_install`；不采用文档或记忆中的其他拼写。

Signal 字典参数使用原生 JSON 对象与只读字典语义；Call 参数及 await 行为由固定插件执行。不会为消除原生差异修改插件。所有对应运行结果以本版独立 Test_Progress 为准。

## 0.7.0 固定源码核对

项目读写与原生预览核对了指定 4.7.1 的 ConfigFile、ResourceUID、PCK 与 PC 导出器实现；独立程序按其 ELF/PE 嵌入资源段读取目标包，不改引擎代码。固定 release 模板不支持以 --main-pack 覆盖启动包。

原生扩展以指定 Alpha 20 的 DialogicIndexer、DialogicEditor、DialogicSubsystem、DialogicPortrait、DialogicAnimation 和布局层接口为准。跳转语法以 Modules/Jump/event_jump.gd 为准：jump other/Start 跨时间线，jump story/ 跳到另一时间线开头，无斜线形式为当前时间线标签。固定 Godot scene/main/window.cpp 的关闭事件在 exclusive_child 存在时被阻止，退出应用须先关闭模态项目面板。


## 0.7.0 本轮固定源码与实测补充

- 固定 Godot 源码 `editor/file_system/editor_file_system.cpp` 读取 `editor/import/use_multiple_threads`；它与场景线程选项不同。字体导入异常及单线程导入诊断见 BUILD.md，原始679/680失败日志和后续结果均保留。
- 固定 Dialogic `Modules/Save/event_save.gd` 的字段初值为空串，但序列化默认值为 `Default`。原始参考工程执行727独立复现显式 Default → `[save]` →空槽的往返差异。PAGE 不修改插件，自己的保存显式写槽名。
- `Modules/History/subsystem_history.gd` 将两类历史数组作为导出属性。原始参考工程727的四种保存开关组合均保留数组，PAGE执行806的实际保存/载入复现该行为。相关用例保持未完成。
