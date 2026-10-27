# PAGE Editor 0.6.0

PAGE Editor 是基于 **Godot 4.7.1 / Dialogic 2.0-alpha-20** 的独立对话创作程序。发布程序可直接运行，无须打开 Godot 编辑器；Source 包用于修改与构建。

本版新增术语编辑、稳定原生翻译 ID、CSV 更新/导入/导出、翻译资源收集和预览语言切换。时间线、角色名称/昵称及术语均可翻译。保留媒体与状态、文本和样式、角色与立绘、变量和表达式、条件与跨时间线流程。完整 Dialogic 功能按 Source 中的 ROADMAP.md 逐步实现，实际测试状态见 RELEASE_NOTES.md。

## 运行与基础操作

- Windows：解压发布包，运行 `PAGE_Editor.exe`。
- Linux：解压发布包，运行 `./PAGE_Editor.x86_64`；若解压工具未保留权限，先执行 `chmod +x PAGE_Editor.x86_64`。
- 无须单独安装 Godot 或 Dialogic。程序需要图形桌面和支持 OpenGL Compatibility 渲染的驱动。
- 实际构建、测试环境和未运行事项见对应发布说明。Windows 实机测试按计划在 1.0.0 交付前统一进行；不能把 Linux 上的 Windows 包检查视为实机验证。

1. 使用 **Content Folder** 选择内容根目录。可选普通文件夹或目标 Godot 工程根目录。打开、浏览不自动改写工程设置；显式保存变量时写入该根的 `project.godot`。
2. 在 **Character** 页新建角色，填写标识、显示名称、别名等属性，管理多张立绘并选择默认项，保存为 `.dch`。新角色标识对应文件名；修改显示名不改变引用标识。
3. 在 **Timeline** 页新建或打开 `.dtl`，编写角色文本、旁白、注释与基本进退场，保存后使用 **Play / F5** 预览。
4. Enter、Space、Advance 或点击对话区域推进；等待选项时使用鼠标或键盘选择，Advance 不代选。Esc / F6 / Close 停止，Restart 从头播放。
5. 在 **Variables** 页创建 String / Int / Float / Bool 变量并保存；在台词中使用 `{player_name}` 等简单引用。变量操作与保存规则见下节。
6. 更换内容目录或从外部新增、修改资源后，使用 **Refresh** 更新列表与诊断。整体移动内容目录后，在新位置重新选择内容根。

纯旁白和注释时间线可以直接打开。涉及角色的时间线必须能在当前内容根目录中解析角色和立绘。随包的 `examples/character_story/` 可直接选为内容根，打开其中 `conversation.dtl`；其他示例见 [examples/README.md](../examples/README.md)。

快捷键：Ctrl+N 新建、Ctrl+O 打开、Ctrl+S 保存、Ctrl+Shift+S 另存为；时间线 Ctrl+F 查找，F3 / Shift+F3 前后查找，F5 / F6 播放、停止。编辑控件提供撤销与重做。新建、打开、切换页面或目录和退出经过未保存处理；打开失败保留当前会话。

命令行参数放在 `--` 后，例如：

```bash
./PAGE_Editor.x86_64 -- --content-root "/absolute/content" "/absolute/content/timelines/demo.dtl"
```

文件和内容根使用绝对路径。内容根是内容文件中逻辑 `res://` 对应的目录，与 PAGE Editor 自身资源目录分离。

## 当前功能与边界

| 内容 | 0.6.0 范围 |
|---|---|
| 时间线 | 原生 `.dtl` 新建、打开、编辑、保存、另存为；旁白、注释、基础角色文本 |
| 角色 | 原生 `.dch` 新建、打开、编辑、保存；文件名标识、静态显示名称、名字颜色 |
| 角色与立绘 | 别名、描述、自定义信息、多立绘、默认选择、全局和单立绘变换、HighlightPortrait 与受限原生分层场景 |
| 角色事件 | JOIN / UPDATE / LEAVE All；五种预设位置、自定义位置与大小、旋转、层级、镜像和原生动画属性 |
| 内容目录 | 时间线、角色和立绘依赖扫描；重复标识、缺失角色及图片诊断 |
| 变量 | 扁平 String / Int / Float / Bool 变量的新建、编辑、改名、删除及字面初值；原生保存与重新打开 |
| 文本引用 | 旁白和基础角色台词中的 `{variable_name}`；缺失引用与非法名称诊断 |
| 表达式 | 标量算术、比较、逻辑、直接 SET 表达式赋值和文本表达式；原生求值与错误诊断 |
| 条件 | 嵌套 if / elif / else；一致缩进、空分支及原生内部 EndBranch；Condition 属性窗口 |
| 选项与流程 | Choice 文本、条件、隐藏/禁用、附加数据；Label、Jump、Return、End；嵌套与跨时间线流程及属性窗口 |
| 条件文本 | 原生 [if 条件 真文本/假文本]；Conditional Text 属性窗口，条件选择后展开变量 |
| 编辑辅助 | 文本编辑、角色和变量表单、单行字面查找、物理源行诊断及定位 |
| 文本与交互 | 原生 BBCode、效果、随机文本、Text 与六类交互事件属性；运行输入、自动推进及跳过 |
| 样式与设置 | 三种原生样式预设、布局层及公开属性、继承、字体、角色样式、文本前后缀与原生配置 |
| 媒体与声音 | Background、Audio、Voice；角色声音 mood、通道默认值及原生音频设置 |
| 历史与状态 | History、Save；预览历史、存档槽管理、加载后继续与内容根隔离 |
| 术语 | 原生 .tres 条目、别名、标题、说明、extra、颜色、启停与项目注册顺序；原生悬停弹窗 |
| 翻译 | 稳定 #id / _translation_id；项目级或逐资源 CSV、语言列编辑、合并导入、原生 .translation 收集与预览语言切换 |
| 运行预览 | 使用 Dialogic 运行时播放支持范围内的内容，支持推进、停止、重启与自然结束 |
| 文件保护 | 未保存处理、外部修改冲突处理；超范围文件只读保护；非法内容或缺失依赖时阻止相应保存和预览 |
| 产品配置 | 集中配置名称、文件名前缀、左上角 LOGO、应用图标与稳定用户数据目录；版本单独管理 |

尚未提供变量文件夹、函数调用、动态角色/立绘表达式、任意自定义脚本/场景/动画、完整视觉事件块编辑和完整目标工程管理。未支持的界面入口保持禁用。

含未知事件或高级角色属性的既有文件采用只读保护；不会静默删除属性后保存。需要完整功能时，可在安装对应 Dialogic 版本的 Godot 工程中继续编辑这些文件。

内容限制：PNG 不超过 32 MiB，单边不超过 8192 像素，总像素不超过 16,777,216（4096×4096）；单份 `.dtl` / `.dch` 编码后不超过 4 MiB。变量配置 `project.godot` 编码后（含 BOM 和换行）不超过 4 MiB，字典或构造器嵌套深度不超过 64；变量展开后的单条预览文本不超过 4 MiB。目录扫描上限为 20000 项、64 层，跳过 `addons`、缓存、版本控制目录及符号链接。扫描不完整时禁用角色引用，避免把缺失的重复资源误判为唯一资源。这些上限不构成大文件流畅性能保证。

## 术语与多语言（0.6.0）

先将 `examples/localization_story` 复制到可写目录，选择该目录为 Content Folder，再打开 `story.dtl`。示例包括中文、英语、日语。预览顶部的语言选择框切换语言并从头重新播放。

1. 点击 **Glossary**。New 新建原生 `.tres`，Open 打开根内资源；Add entry 添加条目。填写 Name、逗号分隔的 Aliases、Popup title、Definition 和 Extra；后两项支持原生富文本。可设置颜色、大小写敏感和条目/整份资源启停。
2. 点击 **Save glossary** 同时保存资源及 `project.godot` 的原生注册列表。Move earlier / Move later 调整注册顺序。未保存表单在切换资源、关闭时提供 Save / Discard / Cancel。
3. 点击 **Translate**，设置 Enable translation、Original locale、文件模式和输出目录，再 Save settings。原文语言必须与已有 CSV 的原文列一致；更换原文语言前应整理所有 CSV。
4. **Update CSV files** 为可翻译的 Text、Choice、角色及术语分配缺失的原生十六进制 ID，保留已有 ID，更新原文列。已有译文、额外语言和暂时没有源文的行保留，后者显示诊断。重复 ID 会阻止整个批量写入。
5. 用文件选择框切换 CSV，**Add language** 添加语言列，在文本编辑区输入译文并 Save CSV。CSV 的第一列是 keys；带逗号、引号或换行的单元格须使用双引号，内部双引号写成两个双引号。也可在外部表格工具中编辑，随后用 Import CSV 按键和语言合并。Export CSV 另存当前表格，拒绝覆盖已有文件。
6. **Collect translations** 生成真实 `.translation` 文件，并在目标 `project.godot` 注册它们、语言列表和原文回退语言。将内容交给目标 Godot 工程前须执行收集。PAGE 预览使用当前 CSV 的会话副本；只修改外部 CSV 后可直接预览，但目标工程仍须重新收集。

原生键分别为 `Text/<id>/text`、`Choice/<id>/<property>`、`Character/<id>/name` / `nicknames` 和 `Glossary/<resource-id>/<entry-id>/<property>`。修改 Text/Choice 属性、角色字段或术语条目时保留既有 ID。角色昵称在原生译文中使用逗号加空格分隔；术语别名使用逗号分隔。

项目级文件为 `dialogic_timeline_translations.csv`、`dialogic_character_translations.csv`、`dialogic_glossary_translations.csv`。逐时间线模式采用固定插件的命名方式；不同目录的同名资源输出到同一翻译目录时会冲突，需选择 Next to source 或重命名资源，不能覆盖另一份译文。

空译文不创建该语言的消息，回退到原文语言。术语名与别名需要可用的翻译消息才会被原生高亮；收集原文列后，空译文可从原文列回退。术语的 title/text/extra 在缺译时遵循原生正文回退。PAGE 的会话副本补齐回退消息，不更改宿主应用的全局回退语言。关闭预览恢复原 locale、翻译资源、术语列表及设置。切换语言重新开始，历史重新建立；预览存档绑定内容与语言，不跨语言载入旧历史。

术语名称和别名遵循 alpha-20 的正则匹配语义。无效表达式和重复名字/别名会诊断；跨资源或译名歧义会阻止批量更新及受影响预览。未知根属性、外部脚本或子资源保持只读；条目扩展字段保留，公有字符串字段进入 CSV，私有字段不翻译。注册文件须位于内容根且不能经过符号链接。

批量操作写入前检查所有文件快照，准备临时文件及 `.editor-backup-*.bak` 恢复副本后再提交。普通失败尝试恢复已提交文件；这不是断电时跨多个文件的原子事务。保留恢复副本便于人工恢复。发生外部修改冲突时，先核对文件，再重新打开面板。

PAGE 不执行目标工程中的外部脚本，不直接载入任意第三方 `.translation` 资源；多语言预览需要可用的源 CSV。仅有编译后的翻译文件时，先导入其源 CSV。界面提供 CSV 文本编辑器，尚未提供电子表格式单元格网格。

## 原生文件与目标工程

建议内容目录：

```text
content/
  characters/alice.dch
  characters/bob.dch
  portraits/alice.png
  portraits/bob.png
  timelines/demo.dtl
  project.godot       # 使用变量时保存其原生配置
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

`alice`、`bob` 是 `.dch` 文件名标识，显示名称可以是中文。带空格的引用标识需加双引号；`_`、`--All--` 等原生命令特殊标识不作为角色名。角色文本不自动让角色入场；使用 `join` 显示默认或指定立绘。省略位置时采用中心位置，`leave` 不带位置。

把内容交给已安装 **Dialogic 2.0-alpha-20** 的 Godot 工程时，将内容根**内部**的目录复制到目标工程根，并保持相对路径。不要额外增加一层 `content/` 而不调整资源引用。合并 `[dialogic]` 中使用的 `variables`、`text/*`、`settings/*`、`layout/*`、`audio/*`、`history/*`、`save/*` 原生键；不要用内容目录的最小 `project.godot` 覆盖目标工程的整个配置。使用自定义总线时，还需保留总线布局及项目中的原生布局路径配置。等待 Godot 导入资源，并确认角色文件名标识唯一。自定义资源标识、批量重命名及自动修复引用不在本版范围。

## 角色、多立绘与演出

Character 页提供 Nicknames（每行一个）、Description（多行）和 Custom info（原生字典）。Custom info 可保存字符串、整数、有限浮点、布尔、数组和嵌套字典；不执行对象、脚本或资源构造。Identifier 始终来自 `.dch` 文件名，别名不会建立第二套引用标识。

Portraits 列表选择当前立绘；填写名称后使用 Add、Rename、Duplicate 或 Delete。Choose PNG 将图片复制进内容目录，复制立绘不会复制或删除图片文件。Default portrait 选择默认项；删除默认立绘时选取剩余项，删空后默认名为空。改名不自动改写其他时间线，旧引用会诊断。新增空立绘须选择图片或有效分层场景后才能保存。

角色与立绘均可设置 scale、offset X/Y、mirror；Ignore character scale 对应原生 `ignore_char_scale`。缩放为正有限值（不超过 10000），镜像按固定原版组合语义执行。立绘选择只改变当前编辑项，不自动改变默认项。非默认图片缺失也会阻止损坏内容被作为完整角色保存或播放。

Timeline 事件区的 **Properties** 在当前 Character 事件行编辑属性，否则插入；**Update** 插入/编辑 UPDATE，**Leave All** 插入全部退场。字段留空表示不写该参数，显式 `false` 和 `0` 会保留为更新操作。Apply 是一次撤销操作；过期表单拒绝覆盖新源文本。

```text
join Alice (idle) left [animation="Fade In" length="0.2" wait="true"]
Alice: Hello.
update Alice (happy) right [mirrored="true" z_index="3" fade="Fade Cross" fade_length="0.2" move_time="0.3" move_ease="out" move_trans="cubic"]
Alice (idle): Back to idle.
update Alice [animation="Bounce" length="0.2" repeat="2" wait="true"]
leave --All-- [animation="Fade Out" length="0.2" wait="true"]
```

默认位置为 leftmost / left / center / right / rightmost；也可使用 `pos=x0.5y1 size=y400px rot=20`（支持比例、百分数及 px）。省略 JOIN 位置使用 center；UPDATE 省略的立绘、位置、镜像、层级不被重置。文本显式立绘可切换；无指定立绘的文本保持原生当前立绘行为。

动画只接受固定插件内对应类型的原生名称。`length`、`fade_length`、`move_time` 为 0–3600 秒，`repeat` 为 1–10000，`z_index` 为 -4096–4096。`repeat_forever="true"` 启用无限重复，此时须 `wait="false"`；关闭/重启预览会清理动画及临时资源。参数名称以 Alpha 20 固定源码为准，例如立绘淡变时长使用 `fade_length`。

### HighlightPortrait 与 LayeredPortrait

Preset 选择 HighlightPortrait 后为当前立绘选择 PNG。说话者高亮、其余角色变暗与临时层级均由原版预设处理。

选择 LayeredPortrait scene 后填写内容根内 `res://…tscn`，使用 **Layer editor** 创建或打开。根为 CanvasGroup，Add group 新增 Node2D，Add sprite 新增 Sprite2D；填写名称、父路径（`.` 为根）、PNG、位置、缩放和 Visible 后点击 Apply layer，最后 Save scene and use。重命名组同步更新其后代路径；删除组同时删除该组子节点，不删除 PNG。fix_offset 使用原生底部对齐行为。关闭未保存的层编辑窗口会放弃该窗口内的场景草稿；导入的 PNG 副本保留。

新场景以标准 Godot `.tscn` 保存，固定脚本引用 `addons/dialogic/Modules/LayeredPortrait/custom_layered_portrait.gd`；打开的原生 `layered_portrait.gd` 场景保留原脚本路径。已有场景、资源 UID 和节点 `unique_id` 在编辑后保留。仅支持 CanvasGroup 根、Node2D 分组、Sprite2D 图层和内容目录内 PNG；未知脚本、节点、属性、连接、继承场景与额外资源保持只读，不静默删减。图片及分层场景均从选定内容根解析；固定预设脚本从应用资源根提供。

```text
join Layered [extra_data="hide Group/Open, show Group/Closed"]
Layered: Closed eyes.
update Layered (idle) [extra_data="set Group/Open, hide Body"]
Layered: Open eyes.
```

`show` / `hide` 使用有效节点路径；`set` 只能选择 Sprite2D，并按原生行为隐藏同组其他 Sprite2D。缺少目标层会诊断。UPDATE 未指定立绘时，附加命令必须对该角色所有可能的立绘有效；可显式指定分层立绘消除歧义。

示例 `examples/portrait_story/` 演示多立绘、高亮、动画和原生分层。将示例作为独立 Content Folder 打开；迁入原生工程时保持相对路径并合并目标配置。

## 变量类型、赋值与文本引用

在 Variables 新建变量，选择 String、Int、Float 或 Bool，然后输入初值并保存。String 原样保留输入；数值外观或 true 不会自动改变字符串类型。Int 使用有符号 64 位整数，Float 只接受有限十进制数（含科学计数法），Bool 填写 true 或 false。选择其他类型后须输入该类型的合法值；不静默转换无效内容。

变量名采用 `[A-Za-z_][A-Za-z0-9_]*`，大小写敏感。配置保存在内容根 `project.godot` 的 `[dialogic]` 节 `variables` 字典；原生数组、字典、null 等暂时只读保留。改名或删除定义不会自动重写时间线，相关引用与赋值目标会重新诊断。

在 Timeline 的事件面板点击 **Variable**。光标在赋值行时编辑该行，否则在当前行之前插入独立赋值行。表单提供目标变量、String / Int / Float / Bool / Expression 模式和值；Apply 写入源文本，可撤销与重做。目标必须是已保存且受支持的变量。

```text
初始分数：{score}
set {score} = 10
现在分数：{score}
set {ready} = true
准备状态：{ready}
set {player_name} = "小明"
你好，{player_name}。
```

赋值使用原生 SET 动态类型语义，允许改变运行值类型；保存初值的类型不随运行改变。每次开始、Restart 或停止后重开，都从已保存初值开始。运行值不自动写回 `project.godot` 或 `.dtl`。未保存变量仍需先保存、放弃或取消。

复杂字符串建议通过 Variable 表单输入。为避开 Alpha 20 在引号内也执行的字符串预处理，表单把双引号、花括号和左圆括号等编码为原生可识别的 Unicode 转义；实际运行值保留原字符。手写内容若不能由原生解析器忠实表示，会被诊断并保留供修正。名为 true / false 的变量可能遮蔽原生布尔字面量；出现冲突时提示先改名。原生表达式解析器无法精确表示的数值赋值也会被拒绝，不能静默截断。

普通时间线预览需要至少一条可显示的 Text。含 Choice 或流程事件的时间线允许没有 Text，例如直接显示选项、Return 或 End。

赋值支持字面量、变量传值和标量表达式，操作符使用 `=`。复合赋值 `+= -= *= /=`、随机数、函数和宿主调用保留后续阶段。按事件顺序检查台词引用；展开后的文本支持本版原生富文本、文本效果和随机文本；对无效参数或缺失资源进行诊断。字符串内普通字面花括号按指定版本的原生替换顺序处理。

可复制 `examples/expression_story/` 到可写目录，选择为 Content Folder，打开 `conversation.dtl` 进行体验。

## 表达式

Variable 属性窗口选择 **Expression**，填写原生表达式后 Apply；重新打开表达式赋值行会加载原文。纯常量文本表达式不需要内容目录；涉及变量时先保存内容根中的变量。

```text
常量：{1+2}
初值：{score}
set {score} = ({score}+2)*3
计算后：{score}；再加一：{{score}+1}
set {ready} = {score}>=9 and not false
判断：{ready}
set {player_name} = {player_name}+"，你好"
{player_name}
```

| 类别 | 语法与行为 |
|---|---|
| 算术 | `+ - * / % **`；括号和一元负号；不支持一元正号，`1+-2` 可表示加负数 |
| 比较 | `== != < > <= >=`；合法类型组合由固定引擎决定 |
| 逻辑 | `and or not`、`&&`、&#124;&#124;、`!`；按原生优先级求值；原生逻辑没有短路，右操作数错误仍被诊断 |
| 变量 | 单独的 `{name}` 传值；表达式内使用 `{name}`，例如 `{score}+1`；变量名大小写敏感 |
| 字符串 | 双引号字符串及 `+` 连接；引号、花括号和左圆括号可写 `\u0022`、`\u007b`、`\u007d`、`\u0028` |
| 文本 | 外层 `{expression}`；内部变量引用保留自身花括号，因此数值变量计算写 `{{score}+1}` |

数值计算保留 Godot 4.7.1 的原生类型和精度：`7/2` 为整数 `3`，`7.0/2` 为浮点数 `3.5`。整数幂返回整数，`2**(-2)` 为 `0`；浮点数参与时按原生浮点规则处理。幂按固定解析器左结合，`2**3**2` 为 `64`。需要清晰分组时加括号，例如 `2**(-2)`；引擎不接受未分组的 `2**-2`。

变量代入使用原生 `var_to_str`，不会承诺超出引擎序列化精度的无损计算。超出 Int64 的输入、非有限结果、除零、错误类型以及不属于本版语法的内容会诊断。整数运算本身遵从固定引擎的整数行为，不能代替任意精度计算。

表达式源码上限 65536 UTF-8 字节、1024 词元、64 层圆括号、128 层操作数嵌套。代入后的表达式、中间字符串与展开后的单条文本分别不超过 4 MiB；代入后的表达式还包含引号与运算符，不能用其文本数据大小替代总字节数。直接变量传值沿用 4 MiB 值上限。上限是保护边界，不是性能承诺。

函数、方法、宿主属性、数组/字典、下标、位运算、条件表达式和字符串 `%` 格式化尚未开放。纯字符串中的这类字样不会作为代码执行；若触发原生预处理，则提示使用 Unicode 转义。按事件顺序检查实际计算结果，结果在台词中形成无效效果参数或资源引用时阻止预览。

## 嵌套条件

在 Timeline 事件面板点击 **Condition**。光标在条件头上时加载并编辑该头；在普通行或空行上创建条件，会在当前行前插入条件头和一行缩进正文。可选择 if、elif、else；else 无表达式。Apply 校验头语法与分支结构，取消不改变内容，一次应用可一次撤销。光标所在行的缩进成为新条件头的缩进，正文再增加一级；编辑已有内层头会保留其原缩进。

```text
if {score} >= 10:
	高分路线。
	set {ready} = true
elif {score} >= 5:
	普通路线。
else:
	开始路线。
这里已经退出分支。
```

- 条件头位于对应层级的行首，结尾使用冒号。if / elif 必须有非空表达式；本版不使用原生空头的隐式 true。
- 分支正文使用一个 Tab，或全文一致宽度的 1—32 个空格。不能混用或跳层，最多 64 层正文缩进；续行文本保持原事件缩进。编辑区显示 Tab / 空格，便于识别边界。
- elif / else 紧跟上一分支，允许中间空白行；else 最多一个且位于最后。同层的注释或普通事件会结束该层条件链，不能再接 elif / else。下一条 if 开始独立链。
- 允许空分支；仅有条件、赋值、注释而没有 Text 或流程事件的时间线可以保存，但不启动预览。全假条件导致没有文本实际显示时，会正常结束。
- 原生解析器自动生成内部 EndBranch，`.dtl` 不写入 `<<END BRANCH>>`。Alpha 20 在空格缩进的文件末尾按空格字符数生成内部结束事件；本版保留原始字节与原生执行，不改插件。
- 条件中的变量必须使用 `{name}`。条件直接执行表达式，不按裸名称查找变量；true / false 在条件中仍是布尔常量，即使变量字典存在同名变量。
- 比较、逻辑和原有标量表达式均可使用。0、0.0、空字符串为假，其他受支持的非零数值和非空字符串为真；字符串 `"false"` 为真。
- 只执行首个命中的分支。分支内赋值影响后续条件和文本，未命中分支不改变变量；重启恢复保存的初值。预检按同一路径检查求值、类型和展开内容，未执行路径仍检查语法、变量引用与范围，但不执行其中的运算。原生逻辑运算本身仍没有短路。
- 分支内的 Variable 表单、Text / Comment / Character 插入保留当前行缩进。在条件正文中插入这些事件会放在当前行前；可用撤销重做。需要退出分支时在文本编辑器将新行缩进清空。
- 已存非法或超范围条件文件只读保留；编辑中的错误可以继续修正，但不能保存或预览。诊断定位至物理源行列。

体验：复制 `examples/condition_story/` 到可写目录，选择为 Content Folder，打开 `conversation.dtl`。将 score 初值分别设为 12、7、2 并保存，可验证三条路线；运行不会写回变量初值。

## 条件文本

在事件面板点击 **Conditional Text**。光标位于完整标记内时加载并编辑该标记，否则在光标处插入；不会替换任意选中的其他文本。填写条件、真文本、可选的假文本，点击 Apply；取消、撤销重做与过期/只读保护均有效。表单每个字段使用单行原生内容，长内容可在输入区滚动。

```text
[if true 始终显示。/不会显示。]
[if {ready} 已准备。/等待。]
[if {{score} >= 10} 高分 {score}。/当前 {score}。]
```

条件表达式外层花括号包住表达式，内层 `{name}` 为变量引用；布尔常量可以直接写 true / false。原生先选择条件文本（order 20），再插入变量（order 30）。未选中的文本不会执行插值运算；本版仍检查其语法和引用，帮助发现潜在错误。

原生会去除选中文本的首尾空白；空插入位于两个空格之间时避免重复空格。同一标记按原始匹配列表做全局替换。真文本中的 `/` 必须转义成 `\/`，两侧文本中的 `]` 必须转义成 `\]`；本版保留原生对这些转义的显示行为。真文本的表达式也受 `/` 分隔限制，不在其中使用未转义除法。使用时间线条件可避免该原生行内语法限制。

条件文本内部不能再嵌套条件文本；复杂层级使用时间线条件。普通文本的 BBCode、效果与随机文本支持范围见下方“文本、样式与交互”；在条件文本内部仍需遵守原生分隔与转义限制。变量值在后续插值时才产生的 `[if ...]` 不会回头再次执行条件修饰符，本版会明确拦截这类超范围输出。

体验：复制 `examples/nested_story/`，选择为 Content Folder 并打开 conversation.dtl；分别设置 ready 为 true/false，score 为 12/7/2 后保存和重启。嵌套选择、赋值和条件文本共同生效，原始初值保持不变。

## 查找、注释与诊断

查找是不区分大小写的单行字面匹配，支持中文并循环到首尾；查找框 Enter / Shift+Enter 也可导航。本版没有替换、正则或跨行查找。查找和诊断定位不修改内容、不增加未保存状态、不清除撤销历史；只读时间线同样可用。

诊断按物理源文件行列定位，视觉折行不改变行号。选择下方问题或点击 **Go to line** 定位。输入新内容时清除旧诊断，再按新内容校验。

独立注释使用行首 `#`。普通文本冒号使用 `\:` 转义；Text 行末反斜杠表示续行，此时下一行即使以 `#` 开头也是文本的一部分。独立 Comment 行末的反斜杠不延续注释。普通文本中的 `#` 不自动开启行尾注释。语义以指定 Alpha 20 解析器为准。

## 保存与保护

- 未编辑文件保存时保持原始字节，包括 BOM、换行与空白；编辑后保留原 BOM / CRLF 偏好。
- 覆盖前保留 `<原文件名>.editor-backup-<标识>.bak` 恢复副本；副本不自动清理。
- 外部修改或删除、不可写文件、符号链接替换会阻止覆盖；另存为不覆盖已有文件或链接。保存失败保留编辑内容。
- 导入到内容根的 PNG 不会因放弃角色编辑自动删除，避免误删共享资源。
- 保存处理包含 UNIX 权限位与 Windows 只读属性判断，不承诺完整保存所有者、ACL、扩展属性等系统元数据。
- 不承诺断电、进程崩溃或磁盘错误时的原子提交。

## 从 Source 构建

需要 Godot **4.7.1 标准版**和完全匹配的 **4.7.1.stable Export Templates**，无需 .NET。Source 不包含引擎二进制、导出模板或 `.godot` 缓存。每版单独提供完整测试清单，覆盖本版全部功能；不通过引用旧清单省略重复用例。

在工程根执行，将 `godot` 替换为实际引擎路径：

```bash
godot --headless --editor --path . --import
godot --headless --path . --script res://tools/apply_branding.gd
godot --headless --path . --export-release "Windows Desktop"
godot --headless --path . --export-release "Linux"
```

Windows 图标与元数据导出、平台打包步骤见 [docs/BUILD.md](BUILD.md)。两个预设把 PCK 嵌入程序；输出路径由 `artifact_stem` 决定。本版程序未代码签名。

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

- [版本变更](../CHANGELOG.md)
- Source 包内 `docs/ROADMAP.md`：完整路线图、最终目标、约束和交付标准
- [构建与平台说明](BUILD.md)
- Source 包内 `docs/TESTCASES.md`：本版完整测试清单
- [依赖说明](DEPENDENCIES.md)和[依赖清单](dependencies.json)
- [官方资料](OFFICIAL_REFERENCES.md)

指定版本源码决定兼容格式与行为，在线文档用于核对细节。Godot、Dialogic、字体和音效保留其名称、API 与许可；产品名称配置不改变第三方身份。


## 选项、标签与跨时间线流程

在 Timeline 事件面板点击 **Choice**。光标在选项行时编辑该行；否则在当前行前插入选项和一行缩进正文。填写文本、可选条件、条件不成立时的 Hide / Disable / Default、禁用文字与附加数据。附加数据是字符串值的 JSON 对象，写入的是原生参数；`else` 和 `alt_text` 使用专用字段。Apply 保留正文与相邻行，支持一次撤销；取消不修改源文本。

```text
选择一条路线：
- 前往大厅 | [if {ready}] [else="disable" alt_text="尚未准备"]
	jump hallway/entry
	返回后继续这里。
- 留在原地
	暂时不出发。
两条路线汇合。
[end_timeline]
```

条件为假时 Hide 隐藏，Disable 显示禁用文字（为空时使用原文字）；Default 使用内容工程 `[dialogic]` 的 `choices/def_false_behaviour`（0 隐藏、1 禁用）。全部选项不可用时按原生默认行为跳过问题。选项正文使用与条件相同的缩进规则，可以交错嵌套。文本中的字面竖线写 `\|`；不接受原生解析器会截断或改变属性的引号/方括号组合。长列表可滚动，支持每题最多 256 项。选项文字包含 `[if 条件 真/假]` 时，用 `| [if true]` 等明确分隔后面的选项条件，避免被固定版本解析器读成选项条件。

点击 **Label / Jump / Return / End** 打开对应属性窗口；在同类事件行上编辑，否则在当前行前插入。Label 的名称和可选显示名分别存为 `label entry (入口)`。Jump 支持 `jump entry`、`jump hallway/`、`jump hallway/entry`；不带目标的 `jump` 从当前时间线开始。Jump 保存调用位置，`return` 返回最近一次 Jump 的后一条事件；空栈 Return 和 `[end_timeline]` 结束整个对话。重复标签采用原生的第一个匹配项。

跨时间线使用内容根中的原生标识。未配置别名时采用唯一 `.dtl` 文件名（不含扩展名）；同名冲突需在内容工程 `project.godot` 中指定原生映射：

```ini
[dialogic]
directories/dtl_directory={"hallway": "res://timelines/hallway.dtl"}
```

目标必须属于当前内容根的已扫描文件。不会跟随符号链接或越过根目录；未知、歧义或缺失标识会诊断。Jump 的时间线标识固定，标签可以用 `{target}` 或受支持的文本表达式，在执行时按当前变量解析；动态标签不存在时停止并说明文件与源行。

预览每次读取完整依赖快照，主文件采用当前编辑缓冲区。依赖在预览中途发生磁盘修改不会改变当次快照，下次预览重新读取。所有分支检查语法和引用，仅实际进入分支才执行赋值与运算；运行错误在该事件执行前停止。停止、失败后重启均可恢复，运行变量与临时资源目录不会写回原内容工程。

保护边界：单文件 4 MiB；每次预览最多 128 条时间线、源文件总计 32 MiB；每题最多 256 项；连续无用户交互事件最多 10000 条；Jump 调用栈最多 1024 层。触及执行边界时给出源位置并停止，可重启或关闭。无须让循环运行到界面失去响应。

示例 `examples/flow_story/` 包含角色、变量、条件选项、嵌套选择和跨时间线返回。选择该文件夹为内容根，打开 `conversation.dtl`。复制到正式 Godot 工程时保持相对路径，合并变量和 `directories/dtl_directory` 配置，不能覆盖目标工程全部 project.godot。

依赖读取和校验目前同步进行；接近 32 MiB 边界的内容会增加打开与预览的等待时间。上述容量上限不代表实时校验的性能保证。

固定的 Dialogic Alpha 20 会在选项显示文字中保留 `\|` 的反斜杠；该写法可避免竖线被解析为属性分隔符，PAGE Editor 保持原版的显示结果。

## 文本、样式与交互（0.4.0）

从时间线事件面板选择 Text properties、Wait、WaitInput、Clear、TextInput、Style 或 Setting。光标位于对应事件时加载当前属性，否则插入新事件；Text 支持角色、立绘和多行正文。工具栏插入标准 BBCode / 原生效果 / 随机文本标签，然后编辑参数。Apply 为一次撤销操作；打开后正文已变更时，重新打开表单再提交。

原生文本支持 b/i/u/s、color、font_size、font、img、对齐、表格、列表和内置动态效果；原生处理顺序保持条件、变量、随机文本、效果等模块定义。`[n]` 分段、`[n+]` 追加、`[br]` 换行。速度 speed/lspeed、pause、input、signal、aa、ns、portrait 和 extra_data 等效果由固定插件执行。mood 标签和角色打字声音配置见下方媒体章节。未知普通标签遵循原生显示行为；自定义 RichTextEffect 脚本在 0.7.0。

顶部 **Style** 打开独立样式窗口。可新建 Visual Novel、Text Bubbles、Speaker Textbox 预设，编辑名称、文件路径、继承和默认标记；左侧管理布局层，右侧编辑固定原生层的公开字段，Reset 移除对应覆盖值。保存为内容根内的原生 `.tres`，并更新 project.godot 的 style_list/style_directory/default_style。父样式控制继承后的层顺序；新增、删除和重排请编辑父样式。自定义脚本/场景和未知属性保留只读。角色打字声音支持媒体文件夹；任意布局资源依赖仍按已实现类型检查；自定义按钮场景等待 0.7.0。表单中的目录或资源字段不代表本版会执行未知依赖。

选中字体/图片路径字段后，可使用 Import font / image，将 TTF/OTF/PNG 复制到内容目录；已有文件使用新名称避免覆盖。也可填写内容根内的原生 FontFile / FontVariation / StyleBox 等受支持数据资源。预览直接读取未导入的资源，通过临时缓存供原生控件使用，临时路径不会写回内容。全局字体为空时使用随应用提供的中文回退；显式字体遵循自己的字形覆盖范围。

**Settings** 编辑内容工程的文本设置和运行设置默认值。运行默认项是简单名称与有限标量；text_speed 和 autoadvance_delay_modifier 为非负数。没有 project.godot 时，打开和预览不会创建它；显式保存会说明并确认创建。仅改动选定原生键，保留其他设置、变量和注释。外部改动、override.cfg 和不支持的宿主配置明确诊断。

**Character** 的 Style、Prefix、Suffix 字段对应 custom_info 的 style/prefix/suffix，与其他自定义信息共同保存。全局前缀是 text/dialog_text_prefix；原生没有同等全局后缀键。角色专属样式遵从原生临时切换规则。

预览顶栏 **Auto / Skip** 控制当前会话。TextInput 把确认内容写入运行字符串变量，Enter 用于确认；空内容是否允许由 allow_empty 决定。WaitInput 等待新的推进输入。选择或输入不会被 Skip 自动确认。输入后的表达式和资源引用按实际运行值再次校验。Setting 的 set/reset/reset all 由原生子系统执行，预览期间使用内容根隔离的 Save 适配，退出后恢复应用设置和资源索引，不写回内容变量初值；预览保存写入专属用户存档目录。

设置中的 input_action 可以原生保存，但内容工程的 InputMap 不自动导入应用；预览仍使用 Enter/Space、Advance 和点击。键盘中文输入法需真实桌面环境验证，程序化插入 Unicode 不等于输入法验证。

配置/样式文本上限 4 MiB，布局层最多 1024，样式继承最多 64 个（含根样式），资源依赖链最多 128 层；TTF/OTF/PNG 原始资产上限 32 MiB。PNG 还受 8192 像素边界约束。容量定义按文件字节，不能据此声称响应性能达标。非法数值、错误依赖、循环继承、未知字段和失败写入保留原文与草稿，不静默删除。

Alpha 20 的 Setting 字面字符串解析不能无损保留嵌入引号或反斜杠。本版在原生往返不一致时拒绝修改，可改用字符串变量；不会修改插件来伪造兼容。

0.5.0 在全新原始参考工程中发现、0.6.0 再次实测确认的事件识别顺序问题：Variable 的 `set` 前缀可能先命中 `setting`，使其误读为变量事件。PAGE 在应用层保证 Setting 优先识别；固定插件源码及原始资源字节保持，因此导入目标 Godot 工程后的该项原生互通仍有已记录限制，不能只凭 PAGE 预览成功判断目标工程已通过。

完整演示见 examples/text_style_story。先复制目录到可写位置，选择为 Content Folder，打开 conversation.dtl，按 F5 播放。

原生时间线正文中的冒号必须转义，包括资源 URL，例如 `[font=res\://fonts/example.ttf]Text[/font]`。Text 属性窗口的正文和资源路径字段仍输入普通 `res://`；应用生成原生源文本时会加上转义。未转义的 URL 若被原生语法识别为角色名，会显示明确诊断。


0.4.0 的原始参考工程验证曾记录动画尚未完成时立即确认 TextInput / WaitInput，后续文本不能自然结束，以及无等待立绘切换紧接 extra_data 时两次回放状态不同的边界。固定插件未修改，0.6.0 不把这些历史问题宣称为已修复。原生互通的常规路径等待相关动画完成后继续；本版执行状态以本版进度为准，历史失败摘要仅作问题来源，不计入本版通过数量。

## 媒体、历史与状态（0.5.0）

事件面板增加 **Background / Audio / Voice / History / Save**。插入后通过 Properties 修改原生字段，Apply 形成一次可撤销编辑；打开表单后源文改变，会拒绝覆盖旧选择。

- Background 的 arg 支持空值清除、颜色和内容根内图片；fade、wait 和 transition 使用固定插件内置过渡。自定义背景场景/脚本在项目扩展阶段，当前明确拒绝执行。
- Audio 支持 WAV、OGG、MP3、命名通道、单次音效、替换及停止。音量单位为 dB，负值有效。`set_*` 覆盖开关区分省略默认值与显式 `0`、`false`；sync 保持原生通道同步语义。
- Voice 设置下一条文本的语音路径、音量和总线。History / Saves 面板的 Wait for voice 控制自动推进等待语音，Skip voice 控制自动跳过时是否开始播放语音；这两个选项含义不同。
- Character 的 **Edit typing sounds** 管理 sound_moods/default，支持单文件或同目录音频、模式、音高、音量、方差和字符间隔。模式为 0 Interrupt、1 Overlap、2 Await；立绘 sound_mood 与 `[mood=名字]` 由原生 Text 处理。固定插件的空 `[mood=]` 不改变当前 mood；要静音可指定空 sound_path 的命名 mood。
- Settings 编辑 `audio/type_sound_bus`、通道默认字典、七项 History 及六项 Save 设置。Edit audio channels 提供通道增删改；保存写入当前内容根的原生 project.godot，保留其他节、变量与注释。缺文件时须确认创建；外部修改时拒绝覆盖。

音频总线可读取目标工程的 default_bus_layout.tres 或 audio/buses/default_bus_layout 指定文件，支持名称、路由、音量、静音、solo、bypass；带效果或外部资源的布局目前拒绝加载。预览结束恢复应用原总线。声音资产每文件最多 64 MiB，图片最多 32 MiB、单边 8192 像素、总像素 16,777,216；声音目录和 mood 各最多 256 项，原生总线最多 64 个。资源必须位于内容根内，链接和未知依赖会诊断。这些限制不构成性能承诺。

### 历史与存档操作

先在 Settings 启用所需历史开关，保存时间线后开始预览，点击 **History / Saves** 查看简单文本历史及完整事件历史。Save 创建槽；已有槽覆盖和 Delete 均需确认且可取消，选择槽后 Load 恢复。对话框内键盘输入不会推进时间线；关闭或加载成功后可继续 Enter / Space 推进。

Save 事件省略或空 slot 遵循固定插件的 latest/default 语义；界面槽名为空则使用配置默认槽。固定原生 `Save.to_text()` 会省略显式 `Default`，再次解析后可能变为 latest；此双向边界保留在测试结果中。History 属性界面输出数值 0/1/2（Clear/Pause/Resume），避免固定解析器将大写 Pause/Resume 解析为 0。固定版本的 simple_history_save/full_history_save 不控制完整状态中两个历史数组的导出；关闭这两个开关不能作为不保存历史的保证。

预览槽保存在应用 `user://preview_saves/<内容根绝对路径的 SHA256>/`，不会写入目标内容目录或覆盖目标游戏存档。支持同一位置、同版本、未变更内容的跨进程恢复。源码/内容依赖变化或移动内容根时会拒绝误恢复；草稿不能保存持久槽。保存使用临时槽、旧槽回退和完整性校验；损坏文件、路径越界和伪造校验拒绝加载。完整性密钥和槽一起属于该用户目录，单独复制 state.txt 不构成可移植存档。

预览使用原生 DialogicSaveState 及子系统状态，并把临时路径转换为稳定内容引用。该引用适配是 PAGE 预览专用，**不能将预览存档文件直接当作目标游戏存档**。恢复涵盖原生保存的变量、位置、Jump 栈、立绘、样式、背景、音频和历史；音频精确播放时刻、半字揭示进度等不超出固定插件承诺。加密沿用原生密码与仅导出加密设置，不构成额外密码保护承诺。

预览适配层避开原生变量 `name` 对 Node 元数据属性的遮蔽，并清理关闭时的音量补间。适配不修改 Dialogic 插件文件；参考工程的差异和失败记录仍如实保存。

示例：复制 `examples/media_state_story/`，选为 Content Folder，打开 `media_state.dtl`。tone.wav 和 voice.wav 均为生成测试音，分别供音乐和语音演示；不是人声录音。

修改加密密码或“仅导出加密”策略不会自动迁移已有存档及全局索引。同一内容根已有不同格式的索引时，写入可能被拒绝；恢复原加密设置后使用原槽，或使用独立内容副本验证新策略。


## 较大字体文本资源的等待

包含大量数值字节的 `FontFile.tres` 加载时可能让界面明显等待。0.5.0 真实导出程序的样本使用171272字节字体数据的数值 PackedByteArray 表示，从按下 F5 到自动检测到首条预览约27秒（含观察开销）；随后编辑、保存、重开及六条资源预览均完成，输入资源字节不变。这是该版虚拟显示环境中的样本观察，不是本版性能保证。本版实际测试结果见独立测试进度包；适用的文本资源与资产大小限制仍按前文执行。
