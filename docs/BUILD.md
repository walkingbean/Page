# PAGE Editor 0.0.1 构建与发布

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

Windows 产品名和文件描述为 `PAGE Editor`，文件与产品数字版本为 `0.0.1.0`。应用版本为 `0.0.1`。修改集中配置或 SVG 后应重新导出程序，仅改压缩包名不会修改 EXE 内的产品资源。

两个预设均将 PCK 嵌入可执行程序；不必在程序旁另放 PCK。程序未代码签名。构建需要匹配模板，使用发布包运行应用不需要安装 Godot。

## 打包

在两个平台导出完成后，在工程根运行：

```bash
python3 tools/package_release.py --output /absolute/path/to/deliverables
```

`--output` 必须是工程目录之外的交付目录。可通过 `--date YYYY-MM-DD` 显式指定发布日期；默认使用运行打包工具的系统日期。

工具从 `config/branding.cfg` 和 `VERSION.txt` 获取名称和版本，创建源码、Windows、Linux 压缩包及带实际文件大小和 SHA256 的发布说明。本版默认文件名为：

| 文件 | 包内根目录或程序 |
|---|---|
| `PAGE_Editor_0.0.1_Source.zip` | `PAGE_Editor_v0.0.1/` |
| `PAGE_Editor_0.0.1_Windows_x86_64.zip` | `PAGE_Editor_0.0.1_Windows_x86_64/PAGE_Editor.exe` |
| `PAGE_Editor_0.0.1_Linux_x86_64.zip` | `PAGE_Editor_0.0.1_Linux_x86_64/PAGE_Editor.x86_64` |
| `PAGE_Editor_0.0.1_Release_Notes.md` | 功能、边界、构建状态和实际交付文件信息 |

平台包包含运行程序、内容示例、启动说明和必要许可证。Linux 包保留程序可执行权限；若用户的解压工具未保留权限，可执行 `chmod +x PAGE_Editor.x86_64`。

Source 包不包含 `.godot`、构建输出、对话 RECORD、执行日志和过程截图。`docs/`、`tools/`、`examples/` 不进入应用 PCK，示例作为平台包中的独立内容目录分发。原生 `.dtl`、`.dch`、配置、版本文件和必要 SVG 已纳入导出过滤规则。

## 工程设置

- 保留 `editor/export/convert_text_resources_to_binary=false`，使原生内容与插件资源按当前工程设置导出。
- 独立应用不启用 Dialogic EditorPlugin；使用已经配置的 `Dialogic` autoload。
- `user_data_directory` 是稳定技术标识，与产品显示名分离。仅调整名称或 LOGO 时不要改动此值。
- `project.godot`、`export_presets.cfg` 和同步脚本处理的 UI 资源引用属于生成元数据，应由集中配置同步。

构建、导出与运行测试是不同步骤。PAGE Editor 0.0.1 的交付范围不包含运行测试、回归测试或回归修复；发布说明按实际完成情况记录构建和导出，不把未执行的测试写成通过。
