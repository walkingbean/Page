# PAGE Editor 0.3.0 发布说明

Godot：4.7.1.stable.official.a13da4feb；Dialogic：2.0-alpha-20。

本版新增角色别名、描述、自定义信息、全局及单立绘变换、多立绘管理与默认选择；JOIN / UPDATE / LEAVE All、原生动画/淡变/补间属性、非默认文本立绘；HighlightPortrait 和受限原生 LayeredPortrait 场景编辑及播放。角色页、事件属性窗口和 Layer editor 提供实际编辑入口。

保留既有变量、表达式、条件、选项和跨时间线流程。未知属性、任意脚本、继承或实例化场景、未知节点/资源保持只读。角色专属样式属 0.4.0，声音属 0.5.0，一般扩展属 0.7.0。本版静态角色/立绘引用及具体限制见 docs/README.md。

应用资源根与目标内容根分离；变量定义和保存初值以目标工程原生配置为准，不建立私有权威配置。运行缓存、图像和分层 PackedScene 映射只用于预览，不写回内容。原插件、主场景及用户根 README 保持原字节。

下一功能版本为 **0.4.0：文本、样式与交互**，需单独确认实施范围和开始编码。

## 测试与交付

测试设计 TC-0.3.0-r1，独立全量 344 条：共有 324、Linux 专用 10、Windows 专用 10。完整设计在生成工程代码前已保存。各项执行先保存证据并确认，再更新状态并执行下一项；失败和重跑均保留。

| 范围 | 已运行 | 未运行 |
|---|---:|---:|
| 共有 · Linux | 318 | 6 |
| Linux 专用 | 3 | 7 |
| 共有 · Windows | 0 | 324 |
| Windows 专用 | 0 | 10 |

上述为封包状态，执行台账截至序号 628；执行次数包含同一用例的不同验证方式、失败及重跑，不等于独立用例数。

实际环境为 Linux x86_64、X11 虚拟显示、Mesa llvmpipe、UID 0，使用 Godot 4.7.1.stable.official.a13da4feb。组件、源工程图形界面、指定原生参考工程、导出独立程序和构建验证分别记录，不互相替代。Windows 实机依约延期至 1.0.0，全部保持未运行；Linux 上的 EXE 资源检查不是 Windows 执行。

未完成项目：

- C-ROOT-08：component: blocked ['The required ordinary non-root user is unavailable; UID 0 mode-bit checks do not satisfy this precondition.']。
- C-ROOT-09：component: blocked ['The required ordinary non-root user is unavailable; UID 0 mode-bit checks do not satisfy this precondition.']。
- C-FILE-04：component: blocked ['The required ordinary non-root user is unavailable; UID 0 mode-bit checks do not satisfy this precondition.']。
- C-FILE-07：component: blocked ['The required ordinary non-root user is unavailable; UID 0 mode-bit checks do not satisfy this precondition.']。
- C-VAR-16：component: blocked ['The required ordinary non-root user is unavailable; UID 0 mode-bit checks do not satisfy this precondition.']。
- LNX-01：platform: blocked This environment runs UID 0 in a UID-0-only namespace. Ordinary-user precondition is not met; partial runtime observations do not pass that precondition.。
- LNX-03：component: blocked ['The required ordinary non-root user is unavailable; UID 0 mode-bit checks do not satisfy this precondition.']。
- LNX-04：component: blocked ['The required ordinary non-root user is unavailable; UID 0 mode-bit checks do not satisfy this precondition.']。
- LNX-05：component: blocked ['The required ordinary non-root user is unavailable; UID 0 mode-bit checks do not satisfy this precondition.']。
- LNX-07：platform: blocked A genuine Linux desktop Chinese IME is unavailable. Programmatic UTF-8 insertion cannot verify IME composition.。
- LNX-08：platform: blocked This environment runs UID 0 in a UID-0-only namespace. Ordinary-user precondition is not met; partial runtime observations do not pass that precondition.; Official release template clears --script; exported internal-state inspection is unavailable. This sample requires a native UI adaptation.。
- LNX-09：platform: blocked No desktop file manager is available; direct file-manager launch is not covered. Working-directory and relocation observations are partial.; Official release template clears --script; exported internal-state inspection is unavailable. This sample requires a native UI adaptation.。
- C-030-REL-03：上传字节与最终 RECORD 核对发生在四包字节冻结之后；包内保留封包时状态，最终交付回答及 RECORD 记录上传结果。

本版测试中修复了嵌套自定义信息的共享引用、原生 StringName 兼容、缓动名称大小写、原生场景 unique_id 读取，以及高亮动画在预览清理时访问失效对象导致的崩溃；场景及资源 UID 也纳入保存往返检查。相关失败与修复后复测保留在台账中。没有修改 Dialogic 插件以改变原生语义。

执行 608 在全新 NotoSansCJK 字体导入阶段出现线程通知错误和 signal 11，进程返回 -6。执行 609 从同一候选的全新解压副本重做导入、品牌同步、双平台导出、打包和实际 Linux 界面检查，全部通过。固定引擎的此类导入异常根因仍未确认；遇到导入失败时应保留日志并从全新副本完成整套验证，不能继续使用失败的导入结果。具体操作见 BUILD.md。

执行 622 在字体导入阶段记录 Variant 越界错误并未通过导入断言，原驱动未保留该子进程退出码。驱动补充退出码记录、拒绝任何 ERROR 行并在前提失败后停止依赖步骤；执行 623、624 从全新副本完整导入、双平台构建、打包及交付程序检查通过。此前成功的 15 次发布驱动导入日志补查也通过。所有异常历史保留，未使用失败导入后生成的诊断产物交付。

测试驱动的输入、夹具、原生序列化环境、选项编号、图像识别和字段读取修订均保留历史及脚本指纹。证据保存超时后先核对已有文件或保存完整恢复快照，未确认的原请求没有重试。执行 205 的旧临时工具链路径失效，恢复同版本官方引擎及图形依赖后继续；执行 206 的窗口枚举失败由缺失 libXtst 测试依赖引起。工具链与恢复记录随进度包提供。部分本地证据 ZIP 在成功保存后出现截短或字节不一致，原因尚未确定；执行 498 通过下载原已保存文件并逐成员匹配恢复，执行 564 及之后通过下载原已保存文件、核对上传前大小和 SHA256 后恢复。具体执行序号及恢复前后哈希见 evidence/ 下的检查点核对记录。最终封包重新核对全部执行检查点及持久化回执。此异常和恢复核对均保留，不以通过复测抹去。

交付 Source、Windows x86_64、Linux x86_64 与独立 Test_Progress 四包。发布说明、路线图、完整测试用例仅随 Source；测试驱动、证据和对话 RECORD 不进入 Source 或平台包。三产品包的大小及 SHA256 在回答正文提供，不将 Source 自身哈希写回包内。四包及 RECORD 另上传 firestorage.ai，并在回答提供分享链接与有效期。程序未代码签名。

角色专属样式、声音、任意自定义脚本/动画/场景仍按路线图分期实施。Layer editor 关闭时放弃未保存的场景草稿，已复制的 PNG 保留；使用边界和操作见 docs/README.md。
