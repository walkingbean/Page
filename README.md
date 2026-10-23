# PAGE Editor 0.0.1

PAGE Editor 是基于 **Godot 4.7.1 / Dialogic 2.0-alpha-20** 的独立对话创作程序。发布程序可直接运行，无须打开 Godot 编辑器；Source 包用于修改与构建。

本版提供原生时间线编辑与预览、基础角色、单张默认立绘、基本进退场及内容目录管理。完整 Dialogic 功能按[版本路线图](docs/ROADMAP.md)逐步实现。

## 运行与基础操作

- Windows：解压发布包，运行 `PAGE_Editor.exe`。
- Linux：解压发布包，运行 `./PAGE_Editor.x86_64`；若解压工具未保留权限，先执行 `chmod +x PAGE_Editor.x86_64`。
- 无须单独安装 Godot 或 Dialogic。程序需要图形桌面和支持 OpenGL Compatibility 渲染的驱动。
- 本版未执行运行测试或回归测试；构建与导出的实际状态见对应发布说明。

1. 使用 **Content Folder** 选择内容根目录。可选普通文件夹或目标 Godot 工程根目录；本版不修改目标 `project.godot`。
2. 在 **Character** 页新建角色，填写标识、显示名称和颜色，选择一张 PNG 作为默认立绘，保存为 `.dch`。新角色标识对应文件名；修改显示名不改变引用标识。
3. 在 **Timeline** 页新建或打开 `.dtl`，编写角色文本、旁白、注释与基本进退场，保存后使用 **Play / F5** 预览。
4. Enter、Space、Advance 或点击对话区域推进；Esc / F6 / Close 停止，Restart 从头播放。
5. 更换内容目录或从外部新增、修改资源后，使用 **Refresh** 更新列表与诊断。整体移动内容目录后，在新位置重新选择内容根。

纯旁白和注释时间线可以直接打开。涉及角色的时间线必须能在当前内容根目录中解析角色和立绘。随包的 `examples/character_story/` 可直接选为内容根，打开其中 `conversation.dtl`；其他示例见 [examples/README.md](examples/README.md)。

快捷键：Ctrl+N 新建、Ctrl+O 打开、Ctrl+S 保存、Ctrl+Shift+S 另存为；时间线 Ctrl+F 查找，F3 / Shift+F3 前后查找，F5 / F6 播放、停止。编辑控件提供撤销与重做。新建、打开、切换页面或目录和退出经过未保存处理；打开失败保留当前会话。

命令行参数放在 `--` 后，例如：

```bash
./PAGE_Editor.x86_64 -- --content-root "/absolute/content" "/absolute/content/timelines/demo.dtl"
```

文件和内容根使用绝对路径。内容根是内容文件中逻辑 `res://` 对应的目录，与 PAGE Editor 自身资源目录分离。

## 当前功能与边界

| 内容 | 0.0.1 范围 |
|---|---|
| 时间线 | 原生 `.dtl` 新建、打开、编辑、保存、另存为；旁白、注释、基础角色文本 |
| 角色 | 原生 `.dch` 新建、打开、编辑、保存；文件名标识、静态显示名称、名字颜色 |
| 默认立绘 | 每角色最多一张 PNG，可导入内容目录；按内容根解析相对路径 |
| 进退场 | 基本 `join` / `leave`；`left`、`center`、`right` 位置及默认事件行为 |
| 内容目录 | 时间线、角色和立绘依赖扫描；重复标识、缺失角色及图片诊断 |
| 编辑辅助 | 文本编辑、角色表单、单行字面查找、物理源行诊断及定位 |
| 运行预览 | 使用 Dialogic 运行时播放支持范围内的内容，支持推进、停止、重启与自然结束 |
| 文件保护 | 未保存处理、外部修改冲突处理；超范围文件只读保护；非法内容或缺失依赖时阻止相应保存和预览 |
| 产品配置 | 集中配置名称、文件名前缀、左上角 LOGO、应用图标与稳定用户数据目录；版本单独管理 |

尚未提供变量、条件、选项与跳转流程、角色别名、高级角色属性、多立绘切换、`UPDATE`、自定义场景、动画与变换、媒体、样式编辑、术语、翻译、完整视觉事件块编辑和完整目标工程管理。未支持的界面入口保持禁用。

含未知事件或高级角色属性的既有文件采用只读保护；不会静默删除属性后保存。需要完整功能时，可在安装对应 Dialogic 版本的 Godot 工程中继续编辑这些文件。

内容限制：PNG 不超过 32 MiB，单边不超过 8192 像素，总像素不超过 1600 万；单份 `.dtl` / `.dch` 编码后不超过 4 MiB。目录扫描上限为 20000 项、64 层，跳过 `addons`、缓存、版本控制目录及符号链接。扫描不完整时禁用角色引用，避免把缺失的重复资源误判为唯一资源。这些上限不构成大文件流畅性能保证。

## 原生文件与目标工程

建议内容目录：

```text
content/
  characters/alice.dch
  characters/bob.dch
  portraits/alice.png
  portraits/bob.png
  timelines/demo.dtl
```

`.dch` 使用 Dialogic Alpha 20 的 Godot Variant 文本序列化，`.dtl` 使用原生时间线语法。PNG 引用保存为 `res://portraits/alice.png` 等路径，不写入机器绝对路径或应用安装路径。

```text
# 两角色基本场景
join alice left
join bob right
alice: 你好。
bob: 我们开始吧。
这是一行旁白。
leave alice
bob: 再见。
leave bob
```

`alice`、`bob` 是 `.dch` 文件名标识，显示名称可以是中文。带空格的引用标识需加双引号；`_`、`--All--` 等原生命令特殊标识不作为角色名。角色文本不自动让角色入场；使用 `join` 显示默认立绘。省略位置时采用中心位置，`leave` 不带位置。

把内容交给已安装 **Dialogic 2.0-alpha-20** 的 Godot 工程时，将内容根**内部**的目录复制到目标工程根，并保持相对路径。不要额外增加一层 `content/` 而不调整资源引用。等待 Godot 导入资源，并确认角色文件名标识唯一。自定义资源标识、批量重命名及自动修复引用不在本版范围。

## 查找、注释与诊断

查找是不区分大小写的单行字面匹配，支持中文并循环到首尾；查找框 Enter / Shift+Enter 也可导航。本版没有替换、正则或跨行查找。查找和诊断定位不修改内容、不增加未保存状态、不清除撤销历史；只读时间线同样可用。

诊断按物理源文件行列定位，视觉折行不改变行号。选择下方问题或点击 **Go to line** 定位。输入新内容时清除旧诊断，再按新内容校验。

独立注释使用行首 `#`。普通文本冒号使用 `\:` 转义；Text 行末反斜杠表示续行，此时下一行即使以 `#` 开头也是文本的一部分。独立 Comment 行末的反斜杠不延续注释。普通文本中的 `#` 不自动开启行尾注释。语义以指定 Alpha 20 解析器为准。

## 配置项目名称和左上角 LOGO（Source 包）

统一入口是工程根下的 **`config/branding.cfg`**。无需逐个修改界面脚本中的名称。

```ini
[branding]
project_name="PAGE Editor"
artifact_stem="PAGE_Editor"
logo_svg="res://asset/branding/page-logo.svg"
app_icon_svg="res://asset/branding/page-icon.svg"
user_data_directory="dialogic-standalone-editor"
```

| 字段 | 作用 |
|---|---|
| `project_name` | 项目名、主窗口与预览窗口标题、页脚、Windows 产品名和文件描述；最多 160 字符，不能换行 |
| `artifact_stem` | 程序及交付文件的名称前缀，不含扩展名；1–96 个 ASCII 字母、数字、下划线或连字符，以字母或数字开头 |
| `logo_svg` | 界面左上角横向 LOGO 的 SVG；必须是工程内的规范 `res://` 路径 |
| `app_icon_svg` | 应用图标与 Home 按钮图标 SVG，与横向 LOGO 分开配置；建议使用 256×256 方形画布 |
| `user_data_directory` | 稳定的用户数据目录标识，字符限制同 `artifact_stem`；单纯调整显示名称时保持不变 |

版本来自 **`VERSION.txt`**，本版内容为 `0.0.1`；平台数字版本同步为 `0.0.1.0`。

具体操作：

1. 解压 Source，进入包含 `project.godot` 的 `PAGE_Editor_v0.0.1/`。打开 `config/branding.cfg`。
2. 修改 `project_name` 和 `artifact_stem`。只调整显示名称时保持 `user_data_directory` 不变，避免改变用户数据位置。
3. 替换 `asset/branding/page-logo.svg`，或把新 SVG 放到 `asset/branding/` 并更新 `logo_svg`。必须是真实 SVG XML；建议透明背景、适配深色主题、文字转为轮廓。文件不得超过 2 MiB，不可放在导出排除的 `docs/`、`tools/`、`examples/`、`tests/` 或 `builds/` 中。
4. 如需修改应用图标，替换 `asset/branding/page-icon.svg` 或更新 `app_icon_svg`。横向 LOGO 与应用图标用途不同；替换一个不自动替换另一个。
5. 按[构建说明](docs/BUILD.md)执行资源导入和 `tools/apply_branding.gd`，使项目设置、平台图标、产品属性、版本和导出路径与集中配置同步。`project.godot`、`export_presets.cfg` 是生成后的元数据，不作为第二套手工配置。
6. 重新导出对应平台并重新打包；修改 Source 不会自动更新已经生成的程序包。交付目录、压缩包和说明中的名称也应采用新的 `artifact_stem`。

LOGO 使用原有 `ResourceSidebar / Layout / LogoMargin / Logo` 节点，图像等比居中放入 768×195 透明画布，保持侧栏布局。方形图片放入该横向区域时会显得较小；可改用适合横向区域的 SVG，或按需要小幅调整节点边距。

Godot 导出时会处理 SVG 纹理，程序支持源码 SVG 与导出纹理。不必把 SVG 另外放到可执行文件旁。Windows 文件图标和版本属性需通过资源修改步骤写入实际 EXE，仅修改配置文本不能代替重新导出。

## 保存与保护

- 未编辑文件保存时保持原始字节，包括 BOM、换行与空白；编辑后保留原 BOM / CRLF 偏好。
- 覆盖前保留 `<原文件名>.editor-backup-<标识>.bak` 恢复副本；副本不自动清理。
- 外部修改或删除、不可写文件、符号链接替换会阻止覆盖；另存为不覆盖已有文件或链接。保存失败保留编辑内容。
- 导入到内容根的 PNG 不会因放弃角色编辑自动删除，避免误删共享资源。
- 保存处理包含 UNIX 权限位与 Windows 只读属性判断，不承诺完整保存所有者、ACL、扩展属性等系统元数据。
- 不承诺断电、进程崩溃或磁盘错误时的原子提交。

## 从 Source 构建

需要 Godot **4.7.1 标准版**和完全匹配的 **4.7.1.stable Export Templates**，无需 .NET。Source 不包含引擎二进制、导出模板或 `.godot` 缓存。

在工程根执行，将 `godot` 替换为实际引擎路径：

```bash
godot --headless --editor --path . --import
godot --headless --path . --script res://tools/apply_branding.gd
godot --headless --path . --export-release "Windows Desktop"
godot --headless --path . --export-release "Linux"
```

Windows 图标与元数据导出、平台打包步骤见 [docs/BUILD.md](docs/BUILD.md)。两个预设把 PCK 嵌入程序；输出路径由 `artifact_stem` 决定。本版程序未代码签名。

保留 `editor/export/convert_text_resources_to_binary=false`。运行独立应用不需要启用 Dialogic EditorPlugin；项目已配置 `Dialogic` autoload。

## 工程结构与文档

| 位置 | 用途 |
|---|---|
| `config/branding.cfg`、`VERSION.txt` | 产品信息与版本的统一来源 |
| `tools/` | 构建配置同步和发布工具 |
| `main.tscn`、`ui/`、`asset/dialogic_ui/` | 指定 UI 的场景、主题和页面 |
| `asset/branding/` | PAGE Editor 的 LOGO 与图标 |
| `main.gd`、`application/` | 编辑会话、原生内容、目录和保存 |
| `preview/` | Dialogic 运行预览和资源映射 |
| `addons/dialogic/` | Dialogic 2.0-alpha-20 插件 |
| `examples/` | 本版范围内的原生内容样例 |
| `docs/` | 路线图、构建、官方资料和依赖说明 |
| `third_party/` | 第三方许可证与声明 |

- [版本变更](CHANGELOG.md)
- [完整路线图、最终目标、约束和交付标准](docs/ROADMAP.md)
- [构建与平台说明](docs/BUILD.md)
- [依赖说明](docs/DEPENDENCIES.md)和[依赖清单](docs/dependencies.json)
- [官方资料](docs/OFFICIAL_REFERENCES.md)

指定版本源码决定兼容格式与行为，在线文档用于核对细节。Godot、Dialogic、字体和音效保留其名称、API 与许可；产品名称配置不改变第三方身份。
