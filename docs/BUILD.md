# PAGE Editor 0.5.0 构建与发布

## 构建条件

- Godot **4.7.1 标准版**，不需要 .NET。
- 与引擎匹配的 **4.7.1.stable Export Templates**，包含 Windows x86_64 和 Linux x86_64 模板。
- 打包工具需要 Python 3.8 或更新版本，仅使用标准库。
- Source 不包含引擎、导出模板或 `.godot` 缓存；首次导入会生成所需缓存。

从 [Godot 4.7.1 官方发行页](https://godotengine.org/download/archive/4.7.1-stable/) 下载对应主机平台的 Standard 编辑器与 Standard Export Templates。按 [4.7 导出模板说明](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html#export-templates)，在编辑器的 `Editor > Manage Export Templates` 中安装下载的 TPZ；也可在该管理器中选择所需平台和架构。执行下面的命令前，确认构建用户已安装匹配的 `4.7.1.stable` Windows x86_64 与 Linux x86_64 模板。

Godot 4.7.1 的 Windows 导出器内置 EXE 图标与版本资源修改。启用 `application/modify_resources` 并使用同步后的 `application/icon` 即可；本版流程不需要 rcedit 或 Wine。应用图标可直接配置为 SVG，由导出器处理。

## 配置与导出

在包含 `project.godot` 的工程根执行，把 `godot` 替换为实际的 4.7.1 引擎路径：

```bash
godot --headless --editor --path . --import
godot --headless --path . --script res://tools/apply_branding.gd
godot --headless --path . --export-release "Windows Desktop"
godot --headless --path . --export-release "Linux"
```

`config/branding.cfg` 是名称与图形的统一来源；版本来自 `VERSION.txt`。同步脚本处理项目设置、Windows 产品属性与图标、平台导出路径、侧栏 LOGO 和 Home 图标资源。脚本会创建 `builds/windows/`、`builds/linux/`，并在配置无效时说明原因。

本版默认输出：

```text
builds/windows/PAGE_Editor.exe
builds/linux/PAGE_Editor.x86_64
```

Windows 产品名和文件描述为 `PAGE Editor`，文件与产品数字版本为 `0.5.0.0`。应用版本为 `0.5.0`。修改集中配置或 SVG 后应重新导出程序，仅改压缩包名不会修改 EXE 内的产品资源。

两个预设均将 PCK 嵌入可执行程序；不必在程序旁另放 PCK。程序未代码签名。构建需要匹配模板，使用发布包运行应用不需要安装 Godot。

## 打包

在两个平台导出完成后，在工程根运行：

```bash
python3 tools/package_release.py --output /absolute/path/to/deliverables
```

`--output` 必须是工程目录之外的交付目录。可选 `--date YYYY-MM-DD` 参数校验并记录打包命令使用的日期，默认使用系统日期；它不会自动重写文档日期。ZIP 条目使用固定时间戳。

工具从 `config/branding.cfg` 和 `VERSION.txt` 获取名称和版本，读取 `docs/RELEASE_NOTES.md`、`docs/ROADMAP.md` 和 `docs/TESTCASES.md`，创建三个程序/源码包；发布说明、路线图和测试清单保留在源码 docs/ 中。所有必要输入必须存在，两个平台程序须已实际导出。本版默认文件名为：

| 文件 | 包内根目录或程序 |
|---|---|
| `PAGE_Editor_0.5.0_Source.zip` | `PAGE_Editor_v0.5.0/` |
| `PAGE_Editor_0.5.0_Windows_x86_64.zip` | `PAGE_Editor_0.5.0_Windows_x86_64/PAGE_Editor.exe` |
| `PAGE_Editor_0.5.0_Linux_x86_64.zip` | `PAGE_Editor_0.5.0_Linux_x86_64/PAGE_Editor.x86_64` |

打包工具先在临时目录准备完整三份构建交付文件，再以拒绝覆盖的方式写入交付目录；遇到已有文件、缺少程序或文档时明确失败。工具在控制台输出实际三份压缩包的大小与 SHA256；交付回答和 RECORD 保存这些信息；不把包哈希回写进包内文档，不计算自身循环哈希。

平台包包含运行程序、内容示例、启动说明和必要许可证。Linux 包保留程序可执行权限；若用户的解压工具未保留权限，可执行 `chmod +x PAGE_Editor.x86_64`。

Source 包不包含 `.godot`、构建输出、测试执行数据、恢复进度、对话 RECORD、执行日志和过程截图。`docs/`、`tools/`、`examples/` 不进入应用 PCK，示例作为平台包中的独立内容目录分发。原生 `.dtl`、`.dch`、配置、版本文件和必要 SVG 已纳入导出过滤规则。

## 工程设置

- 保留 `editor/export/convert_text_resources_to_binary=false`，使原生内容与插件资源按当前工程设置导出。
- 独立应用不启用 Dialogic EditorPlugin；使用已经配置的 `Dialogic` autoload。
- `user_data_directory` 是稳定技术标识，与产品显示名分离。仅调整名称或 LOGO 时不要改动此值。
- `project.godot`、`export_presets.cfg` 和同步脚本处理的 UI 资源引用属于生成元数据，应由集中配置同步。

## 测试与发布状态

每个版本的 `docs/TESTCASES.md` 都是独立全量清单，完整列出共有、Linux 专用和 Windows 专用用例，不因为旧版已有同项而省略。先保存清单，再生成候选程序、执行测试并逐项保存结果与恢复记录。

测试清单只使用“已运行 / 未运行”状态。失败、阻塞、中断或未执行都保留“未运行”；真实结果、证据和尝试历史单独保存，不写进 Testcases.md。通过仅针对实测的平台与候选程序。仅更新状态不改变测试设计修订。

发布前完成共有用例在 Linux 的部分、Linux 专用用例和可执行的 Windows 包静态检查。Windows 实机测试延期至 1.0.0 交付前统一进行，届时还须执行所有共有用例的 Windows 部分。静态检查、headless 运行和实际 GUI 操作不能互相冒充。

环境前置条件未满足的用例保持未运行，并在发布说明列明阻碍和补测条件；不能据此声明全量验证完成。受限 UID 0 不能代替普通用户权限验证，无真实输入法或文件管理器时不能宣称相应桌面操作通过。

打包前把实际构建信息、测试环境、测试摘要与未运行事项写入 `docs/RELEASE_NOTES.md`，平台包只保留运行使用说明；发布说明、路线图、测试清单仅位于 Source 包。最终包须对应经过验证的候选程序；重新导出改变程序时按影响重测。构建和导出完成不等于运行测试通过。

## 导入完成的判断

以进程成功退出、资源导入完成且无脚本错误为完成依据，再执行配置同步和导出。异常时保留日志；修正问题后重新验证，不将异常退出视作成功导入。

0.0.4 的验证中，全新导入曾在 NotoSansCJK 字体导入阶段出现线程通知错误和 SIGSEGV。重新解压同一候选后，完整导入、双平台导出和打包通过；该次失败及重跑记录保存在 0.0.4 的独立测试进度包。尚未确认或修复引擎层根因，不能在异常退出后直接继续发布。

0.3.0 执行 608 再次在全新 NotoSansCJK 字体导入阶段出现 `propagate_notification()` 线程错误和 signal 11，进程返回 -6。执行 609 使用同一 Source 候选的另一份全新解压副本，重新完成导入、品牌同步、双平台导出、打包及实际 Linux 界面检查，全部通过。两次记录均保留；成功重跑不表示该引擎导入异常的根因已确认或修复。

0.3.0 执行 622 的另一项独立构建在同一字体导入阶段记录到 `Variant::VARIANT_MAX` 越界错误，导入断言失败；该旧驱动未记录导入子进程退出码，不能据此声称具体退出信号。修正驱动的退出码记录和失败后停止逻辑后，执行 623、624 分别从全新副本完成完整导入、双平台构建、打包及交付程序检查，均通过。此前成功的 15 次发布驱动导入也补查了正常退出和无 ERROR 行。原失败记录完整保留，未将失败导入后生成的诊断产物用于正式交付。

固定版本引擎此前曾在干净副本资源导入时异常退出。应检查导入退出码和完整日志；若失败，保留日志并从新解压副本重新执行导入和后续完整验证。成功重试不代表引擎层根因已修复。本版实际结果以独立进度包为准。

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

版本来自 **`VERSION.txt`**，本版内容为 `0.5.0`；平台数字版本同步为 `0.5.0.0`。

具体操作：

1. 解压 Source，进入包含 `project.godot` 的 `PAGE_Editor_v0.5.0/`。打开 `config/branding.cfg`。
2. 修改 `project_name` 和 `artifact_stem`。只调整显示名称时保持 `user_data_directory` 不变，避免改变用户数据位置。
3. 替换 `asset/branding/page-logo.svg`，或把新 SVG 放到 `asset/branding/` 并更新 `logo_svg`。必须是真实 SVG XML；建议透明背景、适配深色主题、文字转为轮廓。文件不得超过 2 MiB，不可放在导出排除的 `docs/`、`tools/`、`examples/`、`tests/` 或 `builds/` 中。
4. 如需修改应用图标，替换 `asset/branding/page-icon.svg` 或更新 `app_icon_svg`。横向 LOGO 与应用图标用途不同；替换一个不自动替换另一个。
5. 按[构建说明](BUILD.md)执行资源导入和 `tools/apply_branding.gd`，使项目设置、平台图标、产品属性、版本和导出路径与集中配置同步。`project.godot`、`export_presets.cfg` 是生成后的元数据，不作为第二套手工配置。
6. 重新导出对应平台并重新打包；修改 Source 不会自动更新已经生成的程序包。交付目录、压缩包和说明中的名称也应采用新的 `artifact_stem`。

LOGO 使用原有 `ResourceSidebar / Layout / LogoMargin / Logo` 节点，图像等比居中放入 768×195 透明画布，保持侧栏布局。方形图片放入该横向区域时会显得较小；可改用适合横向区域的 SVG，或按需要小幅调整节点边距。

Godot 导出时会处理 SVG 纹理，程序支持源码 SVG 与导出纹理。不必把 SVG 另外放到可执行文件旁。Windows 文件图标和版本属性需通过资源修改步骤写入实际 EXE，仅修改配置文本不能代替重新导出。


## 测试文件交付位置

完整用例保存在源码根 docs/TESTCASES.md，随 Source.zip 交付，不生成外部 Testcases.md。测试执行结果与恢复进度单独打包为 PAGE_Editor_<版本号>_Test_Progress.zip，在对话中直接提供并保存至项目资料库来源；不进入源代码或程序包。打包脚本只打包产品及文档，执行证据由测试流程独立封存。

0.4.0 首次字体导入同样出现线程通知错误和 signal 11，原始日志保留。执行 442 从全新 Source 解压副本完成无错误导入、品牌同步、双平台导出与打包；该次实际导出的程序用于当版独立程序验收。后续文档和状态调整不改变程序字节，最终技术文件清单另行比对。此结果不等同于引擎异常根因已修复。

0.4.0 执行 608 的独立品牌检查在全新字体导入阶段以 signal 11（-11）退出，未继续后续构建。执行 609 从另一份全新副本完整重跑通过；这仍是根因未确认的导入异常。

0.5.0 增加运行时媒体解码与预览状态适配，仍使用相同 Godot 导出模板，不增加系统编解码器依赖。QA 使用的 ffmpeg、Xvfb、OCR 工具不随产品分发，实际发布程序无需它们。

## 本次观察到的原生导入异常

一次全新目录导入在开始处理 `NotoSansCJKsc-Regular.otf` 时以信号11退出；后续导出立即停止。源码、驱动和命令均未改动，新目录的完整重跑及之后三次全新构建通过。根因未定位，不能据此宣称引擎问题已修复。构建时应检查每一步返回码和日志；出现原生崩溃时保留日志，不沿用失败导入结果继续导出。原记录见独立测试进度691及692–697相关用例。
