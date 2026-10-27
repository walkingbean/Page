# PAGE Editor 0.6.0 示例

| 示例 | 打开方式 | 内容 |
|---|---|---|
| `variable_story/` | 先选该目录为 Content Folder，再打开 `conversation.dtl` | 原生字符串变量初值、中文与空值、台词中的简单引用 |
| `narration.dtl` | 在 Timeline 页直接打开 | 中文旁白、冒号转义和续行 |
| `comments.dtl` | 在 Timeline 页直接打开 | 独立注释、文本续行和转义井号 |
| `character_story/` | 先选该目录为 Content Folder，再打开 `conversation.dtl` | 两个原生角色、默认 PNG 立绘、左右入场、对白和逐一离场 |

示例使用 Dialogic 2.0-alpha-20 原生格式。角色样例中的 `res://` 以 `character_story/` 为内容根，不指向 PAGE Editor 安装目录；完整步骤见该目录的 README。

这些文件用于说明本版本的功能范围，不是本轮测试报告。

## assignment_story

选择该目录为 Content Folder，打开 conversation.dtl。预览展示数值、布尔与字符串赋值；Restart 恢复初值。

## expression_story

0.0.4 标量表达式、SET 计算赋值与文本表达式示例。复制目录并选为 Content Folder；打开 conversation.dtl。

## condition_story

0.0.5 单层条件、分支赋值和后续条件示例。复制目录并选为 Content Folder，打开 conversation.dtl；将 score 初值改为 12、7、2 可体验全部路线。

## nested_story

本版嵌套条件、赋值、条件文本组合示例。复制并选为 Content Folder；ready 设 true/false，score 设 12/7/2，保存后重启比较所有路线。

- `flow_story/`：条件选项、嵌套分支、角色与跨时间线 Jump / Return。

## portrait_story — 角色与立绘

在 Content Folder 选择此文件夹，打开 conversation.dtl。示例依次展示高亮、多立绘变换、UPDATE、原生动画、全部退场和 LayeredPortrait 的 Badges/Gold、Badges/Blue 排他切换。角色图片来自既有 character_story；色块为本项目生成的分层演示素材。角色页可调整别名、描述和自定义信息；Layer editor 可直接编辑 portraits/layered.tscn。迁入原生工程时保留相对路径并合并 project.godot 的 dialogic 配置，不覆盖目标工程其他设置。

## text_style_story — 文本、样式与交互

选择可写副本为内容根并打开 conversation.dtl。包括真实姓名输入、角色样式、富文本/随机文本/效果、字体/图片、等待、设置、清除与变量分支。原生资源和配置可直接移交固定参考工程。

## media_state_story

0.5.0 背景、音频、语音、历史和预览存档示例。选该目录为 Content Folder，打开 media_state.dtl。两个 WAV 均为生成测试音；History / Saves 提供槽管理。

## localization_story（0.6.0）

中英日原文和译文、角色、术语与别名示例。复制到可写目录，选择其为 Content Folder，打开 story.dtl；通过 Translate 检查 CSV，通过 Glossary 编辑术语，在预览顶部切换语言。
