# PAGE Editor 0.0.5 官方资料

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
