# PAGE Editor 0.0.2 官方资料

本版兼容目标固定为 Godot 4.7.1 / Dialogic 2.0-alpha-20。开发细节对照指定版本源码；在线文档用于补充与核对，不自动改变兼容目标。

| 官方资料 | 对应事项 |
|---|---|
| [Godot 4.7 导出工程](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html) | 标准版、导出模板和实际可执行程序 |
| [Godot 4.7 Windows 导出属性](https://docs.godotengine.org/en/4.7/classes/class_editorexportplatformwindows.html) | 图标、modify_resources、产品名、文件描述和数字版本 |
| [Godot 4.7 Windows 应用图标](https://docs.godotengine.org/en/4.7/tutorials/export/changing_application_icon_for_windows.html) | EXE 资源与图标生成 |
| [Godot ConfigFile](https://docs.godotengine.org/en/4.7/classes/class_configfile.html) | 集中产品配置的 INI / Variant 表达 |
| [Godot 文件路径](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html) | 应用 res://、内容目录与 user:// 的区分 |
| [Dialogic 变量](https://docs.dialogic.pro/variables.html) | 字符串初值、简单文本引用及超出本版的完整变量能力 |
| [Godot 4.7 ProjectSettings](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html) | project.godot 中的原生项目设置 |
| [Dialogic 文本](https://docs.dialogic.pro/writing-texts.html) | 文本替换与后续效果处理 |
| [Dialogic 时间线语法](https://docs.dialogic.pro/timeline-text-syntax.html) | .dtl 文本、角色引用与注释 |
| [Dialogic 角色与立绘](https://docs.dialogic.pro/characters-and-portraits.html) | .dch、显示名称、默认立绘与资源 |
| [Dialogic 角色事件](https://docs.dialogic.pro/event-character.html) | join / leave 和位置参数 |
| [Dialogic 引用管理](https://docs.dialogic.pro/reference-manager.html) | 角色身份、文件引用与资源依赖 |

源码关注位置：Dialogic 的 CharacterResourceLoader / Saver、DialogicResourceUtil、Text / Character 事件与 Portraits 子系统；Godot 的项目配置、资源导出和 Windows 平台导出器。产品配置只影响 PAGE Editor 的应用身份，保留第三方 API 和资源语义。
