# PAGE Editor 0.0.2 构建与发布

## 构建条件

- Godot **4.7.1 标准版**，不需要 .NET。
- 与引擎匹配的 **4.7.1.stable Export Templates**，包含 Windows x86_64 和 Linux x86_64 模板。
- 打包工具需要 Python 3.8 或更新版本，仅使用标准库。
- Source 不包含引擎、导出模板或 `.godot` 缓存；首次导入会生成所需缓存。

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

Windows 产品名和文件描述为 `PAGE Editor`，文件与产品数字版本为 `0.0.2.0`。应用版本为 `0.0.2`。修改集中配置或 SVG 后应重新导出程序，仅改压缩包名不会修改 EXE 内的产品资源。

两个预设均将 PCK 嵌入可执行程序；不必在程序旁另放 PCK。程序未代码签名。构建需要匹配模板，使用发布包运行应用不需要安装 Godot。

## 打包

在两个平台导出完成后，在工程根运行：

```bash
python3 tools/package_release.py --output /absolute/path/to/deliverables
```

`--output` 必须是工程目录之外的交付目录。可通过 `--date YYYY-MM-DD` 显式指定发布日期；默认使用运行打包工具的系统日期。

工具从 `config/branding.cfg` 和 `VERSION.txt` 获取名称和版本，读取 `docs/RELEASE_NOTES.md`、`docs/ROADMAP.md` 和 `docs/TESTCASES.md`，创建六个标准交付文件。所有必要输入必须存在，两个平台程序须已实际导出。本版默认文件名为：

| 文件 | 包内根目录或程序 |
|---|---|
| `PAGE_Editor_0.0.2_Source.zip` | `PAGE_Editor_v0.0.2/` |
| `PAGE_Editor_0.0.2_Windows_x86_64.zip` | `PAGE_Editor_0.0.2_Windows_x86_64/PAGE_Editor.exe` |
| `PAGE_Editor_0.0.2_Linux_x86_64.zip` | `PAGE_Editor_0.0.2_Linux_x86_64/PAGE_Editor.x86_64` |
| `PAGE_Editor_0.0.2_Release_Notes.md` | 功能、边界、实际构建与测试摘要及三包文件信息 |
| `PAGE_Editor_0.0.2_Plan_and_Roadmap.md` | 完整版本计划、路线图、约束和交付标准 |
| `PAGE_Editor_0.0.2_Testcases.md` | 本版独立全量测试列表与运行状态 |

打包工具先在临时目录准备完整六文件，再以拒绝覆盖的方式写入交付目录；遇到已有文件、缺少程序或文档时明确失败。发布说明中的大小和 SHA256 从实际三份压缩包计算；不把包哈希回写进包内文档，不计算自身循环哈希。

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

打包前把实际构建信息、测试环境、测试摘要与未运行事项写入 `docs/RELEASE_NOTES.md`，使各平台包中的说明与外部发布说明一致。最终包须对应经过验证的候选程序；重新导出改变程序时按影响重测。构建和导出完成不等于运行测试通过。
