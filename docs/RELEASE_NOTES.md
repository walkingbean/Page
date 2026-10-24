# PAGE Editor 0.0.3 发布说明

日期：2026-10-24（UTC+8）  
Godot：4.7.1.stable.official.a13da4feb（标准版）  
Dialogic：2.0-alpha-20  
平台：Windows x86_64、Linux x86_64

PAGE Editor 是独立对话创作程序，平台包无需 Godot 编辑器即可启动。本版增加标量变量类型与原生字面量赋值。最终目标仍为覆盖固定版本 Dialogic 的全部功能，输出完全兼容的原生内容。

## 本版功能

- Variables 页面支持 String、Int、Float、Bool 初值，显式选择类型，创建、编辑、改名、删除、保存及重开。数组、字典和 null 原样只读保留。
- 原生 `set {variable} = literal` 赋值。Variable 属性窗口可插入或加载并编辑当前事件，支持撤销、重做及过期内容保护。
- 按时间线顺序应用赋值和后续台词引用，遵循原生 SET 的动态类型行为；后续展开触发未支持文本功能时明确诊断。
- 使用原始 Dialogic 运行预览；开始、Restart、停止重开均恢复已保存初值，运行值不写回配置或时间线。
- 保留原生时间线文本编辑、旁白、注释、基础角色文本、基础角色属性、单张默认 PNG、基本进退场、内容目录、查找、物理行诊断、文件冲突及恢复副本保护。
- 保留指定 UI 场景、布局与主题。集中品牌配置和 SVG 替换方法移至 `docs/BUILD.md`；版本由 `VERSION.txt` 管理。

## 使用方法与边界

Windows 解压运行 `PAGE_Editor.exe`。Linux 执行 `./PAGE_Editor.x86_64`；若解压工具未保留执行位，先执行 `chmod +x PAGE_Editor.x86_64`。需要图形桌面和 Compatibility 渲染驱动。

将 `examples/assignment_story/` 复制至可写目录并选为 Content Folder，打开 `conversation.dtl` 后播放。在 Variables 中编辑保存默认值；Timeline 中把光标定位到赋值行，使用 Variable 入口编辑属性。

变量名采用 `[A-Za-z_][A-Za-z0-9_]*`，大小写敏感。当前仅支持 SET 字面量，不支持复合赋值、运算表达式、变量间赋值、方法调用、条件、文件夹或宿主属性。`true`、`false` 名称与原生字面量解析冲突时会诊断。整数初值支持 int64，赋值需同时能被原生解析器精确表示；非有限数拒绝。

固定插件对字符串引号、花括号及部分函数名有预处理。属性编辑器生成原生可执行的 Unicode 转义来保存字面值；无法忠实表示的手写输入会明确拒绝，不修改插件语义。预览中的富文本、文本效果、随机文本及条件文本仍受保护。

预览至少需要一条可显示的 Text；只有赋值、注释或进退场的文件可保存，但不启动预览。

选项、跳转、多立绘、高级角色属性、动画、媒体、样式、术语、翻译及自定义扩展尚未开放。下一版本 0.0.4 聚焦表达式。完整操作、大小限制和功能边界见 README／平台 USER_GUIDE，完整路线图见 `docs/ROADMAP.md`。

## 交付内容

| 文件 | 内容 |
|---|---|
| PAGE_Editor_0.0.3_Source.zip | 工程、依赖、配置、构建工具、示例和文档；全量用例在 docs/TESTCASES.md |
| PAGE_Editor_0.0.3_Windows_x86_64.zip | Windows 独立程序、示例、文档和许可 |
| PAGE_Editor_0.0.3_Linux_x86_64.zip | Linux 独立程序、示例、文档和许可 |
| PAGE_Editor_0.0.3_Release_Notes.md | 发布说明与三包大小、SHA256 |
| PAGE_Editor_0.0.3_Plan_and_Roadmap.md | 最终目标、完整路线图和交付规则 |
| PAGE_Editor_0.0.3_Test_Progress.zip | 独立测试结果、执行记录、恢复资料与验证工具 |

Test_Progress.zip 不进入源包或平台包。源包不包含引擎、模板、缓存、测试执行数据或对话记录。程序未代码签名。

## 构建与测试状态

使用上述精确引擎及匹配的 4.7.1.stable 模板实际导出 Windows 和 Linux 程序。测试设计 TC-0.0.3-r1 包含 152 条独立完整用例（共有 132、Linux 专用 10、Windows 专用 10），先生成设计，再逐项执行和持久化。失败历史保留；只有满足整条预期的成功执行才标记已运行。

实际环境为 Linux x86_64、Xvfb/X11、Mesa llvmpipe、OpenGL Compatibility。当前进程为能力受限的 UID 0，没有普通用户桌面、中文输入法或文件管理器。相关条件不足的用例保持未运行。Windows 仅导出和静态检查，实机验证按约定在 1.0.0 统一执行。

已实际完成核心类型/赋值、基础功能回归、参考工程双向原生运行、图形交互、独立 Linux 程序运行、品牌配置、EXE 资源和全新 Source 构建验证。完整分平台状态以 `docs/TESTCASES.md` 为准；每次执行的序号、结果、日志和重跑历史保存在独立 Test_Progress 包中。

全新副本首次导入时出现过 Godot SIGSEGV，日志停在 Noto 字体导入阶段；受影响项目已在另外的全新副本重跑通过，完整 Source 也已从全新解压完成双平台导出及重新打包。根因尚未确定，失败历史未删除。构建条件和导入异常处理见 `docs/BUILD.md`。

共有用例中的 C-FILE-04、C-FILE-07、C-ROOT-08、C-ROOT-09、C-VAR-16 含普通用户权限或不可读/不可写条件，当前环境不能完整满足。Linux 专用的 LNX-01、03、04、05、07、08、09 同样保留未运行；部分子样本的成功不代替完整用例完成。独立子进程切换普通用户的尝试返回 EINVAL，真实中文输入法和桌面文件管理器也不可用。

Windows 实机未运行，所有共有用例的 Windows 部分和 Windows 专用用例均保留未运行。


## 最终用例状态

| 范围 | 已运行（完整通过） | 未运行 |
|---|---:|---:|
| 共有用例 · Linux | 127 | 5 |
| Linux 专用 | 3 | 7 |
| 共有用例 · Windows | 0 | 132 |
| Windows 专用 | 0 | 10 |

Linux 专用已完整运行项为 LNX-02（执行权限与恢复启动）、LNX-06（大小写及中文/空格路径）、LNX-10（动态依赖和实际图形启动）。其余未运行项及前置条件见上文与测试进度包。

## 本次独立程序标识

| 平台 | 程序文件 | 大小（字节） | SHA256 |
|---|---|---:|---|
| Linux x86_64 | PAGE_Editor.x86_64 | 93020680 | `52c12aa84a1e96e3afc96844a1d8ffb813dffce41bdedd80fbd84d54cb2a9438` |
| Windows x86_64 | PAGE_Editor.exe | 128640728 | `c33a7cec310f897fabbc1dee21c596e55b32ba30eaf348570e69991e6596e726` |
