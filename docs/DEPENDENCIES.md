# PAGE Editor 0.7.0 依赖与许可

| 依赖 | 版本或来源 | 用途 | 许可 |
|---|---|---|---|
| Godot | 4.7.1 标准版；导出模板 4.7.1.stable | 应用运行、资源处理和导出 | MIT；组件声明见 GODOT_COPYRIGHT |
| Dialogic | 2.0-alpha-20 | 原生文件与对话预览运行时 | MIT |
| Noto Sans CJK SC | NotoSansCJKsc-Regular.otf；具体文件 SHA256 见 dependencies.json | 中文字体回退及品牌 SVG 字形轮廓 | SIL OFL 1.1 |
| Roboto | Dialogic 随附字体 | 界面与对话文本 | 随附字体许可 |
| Dialogic 音效 | Dialogic 随附资源 | 插件依赖资源 | CC BY-SA 4.0；原始署名见 DIALOGIC_SOUND_LICENSE.txt |
| 指定界面资源 | dialogic_editor_ui_260903.zip | 主场景、主题、布局与图形资源 | 保持提供材料的授权条件 |

源文件输入的名称、大小与 SHA256 记录于 [dependencies.json](dependencies.json)。本版使用指定依赖版本；在线文档更新不自动升级依赖。

许可证位于 Source 的 `third_party/`，发布程序包内对应文件夹同样为 `third_party/`。Dialogic 插件目录内的原始许可文件也保留。`examples/character_story/` 使用 Dialogic 示例立绘，附 `DIALOGIC_LICENSE.txt`。

Dialogic 随附的原始打字音效由 Tim Krief 创作，采用 [Creative Commons Attribution-ShareAlike 4.0 International（CC BY-SA 4.0）](https://creativecommons.org/licenses/by-sa/4.0/) 许可。本项目分发这些音效时未作修改，并完整保留 `third_party/DIALOGIC_SOUND_LICENSE.txt` 中的原始署名和许可声明。

Godot 和 Dialogic 的产品名、API 名、类名、原生格式及版权信息保持原义，不由 PAGE Editor 的品牌配置替换。此说明不为用户提供的 UI 素材或应用业务代码另行指定授权条款。

Godot 引擎二进制和导出模板不包含在 Source 压缩包中。实际使用的引擎构建、导出结果和平台执行状态见本版发布说明。

Godot 导入会为随包 `.import` 文件补充当前引擎的默认字段；这类自动生成的导入元数据单独记录。Dialogic 原始脚本、场景和资源内容保持原字节。

0.3.0 在 0.2.0 正式 Source 基础上扩展角色与立绘。新增能力使用现有 Dialogic 内置 HighlightPortrait / LayeredPortrait 预设和默认动画，没有增加第三方依赖或更换版本。

0.4.0 在 0.3.0 正式 Source 基础上扩展文本、样式与交互。没有升级依赖；新增示例复用相同 Noto Sans CJK 字体和 Dialogic 示例 PNG，许可与 SHA256 适用。固定原生插件脚本未改变。

0.5.0 基于正式 0.4.0 Source 扩展媒体与状态，未升级或新增第三方产品依赖。media_state_story 的 SVG 和两个 WAV 是本次编写示例时生成的简单图形与测试音；没有引入外部人声录音或音乐。

插件比对范围区分原始源码／资源与生成元数据：脚本及原始资源保持字节一致；Godot重建的141个 `.import` 文件存在差异，路径清单保存在独立测试进度的 C-FLOWRT-05 记录。它们不作为修改插件语义的依据。

0.6.0 基于正式 0.5.0 Source 实现术语与多语言，未新增或升级第三方依赖。localization_story 的中英日文本与术语由本版编写，沿用既有字体。

0.7.0 基于正式 0.6.0 Source 实现项目与扩展，继续使用固定依赖，不引用早期 0.0.1—0.0.3 工程文件。生成的原生扩展示例不增加第三方依赖；临时预览程序复用所交付的同版本引擎。

项目与扩展示例复用同一 Noto Sans CJK SC 字体，原生样式显式设置该字体以显示中文角色名和对白；字节哈希沿用 dependencies.json，许可随示例 fonts/ 保留。
