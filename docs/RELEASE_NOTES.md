# PAGE Editor 0.5.0 发布说明

日期：2026-10-26（UTC+8）。固定 Godot 4.7.1 Standard / Dialogic 2.0-alpha-20，基于正式 0.4.0 Source。

## 本版功能

- Background、Audio、Voice、History、Save 五类事件的原生字段编辑、内容读写和运行预览，保留音频通道默认值与逐项覆盖语义。
- 运行时背景图片和 WAV / OGG / MP3，角色打字声音、声音 mood、音频通道及媒体设置；提供 media_state_story 示例。
- 预览历史、存档槽创建、覆盖、删除、加载及状态恢复；恢复后继续执行，内容根之间隔离。使用原生状态容器及原生加密配置。
- 保留文本、样式、变量、表达式、条件、选项、跨时间线流程、角色及立绘功能；相应回归与新增用例分别保留实际证据。

根 README 由用户维护并保留原字节；原始主场景、主题、固定 Dialogic 插件源码及原始资源保持字节一致；141个由引擎重建的 .import 元数据差异单独记录。目标内容根与应用资源根分离，不建立私有变量权威配置。下一功能版本为 0.6.0「术语与多语言」，本次授权不延伸至下一版本。

## 使用边界

预览存档中的稳定资源引用适配专用于 PAGE 预览，不能当作目标游戏可直接读取的存档。存档保存固定插件支持的变量、位置、Jump 栈、立绘、样式、背景、音频和历史；不承诺插件未保存的精确音频播放时刻或半字揭示进度。

修改密码或“仅导出加密”策略不会自动迁移已有槽和全局索引。原索引格式与新策略不一致时可能拒绝写入；可恢复原设置使用原槽，或在独立内容副本中验证新策略。失败写入的旧槽保护有实际样本；普通用户只读权限、真实磁盘满或断电恢复未完成的部分不能据此宣称通过。

自定义脚本、任意音频效果和未支持资源依赖会明确诊断，不执行未知依赖。事件、角色和项目配置仍使用固定版本原生内容格式。容量、路径及槽名限制详见 docs/README.md。

较大的数值 PackedByteArray 字体文本存在明显加载等待。本次未导入 FontFile 样本含171272字节字体数据，修复后从F5到自动检测到首条预览约27秒；其中包含界面观察开销，不能当作通用性能指标。直接字体文件和其他输入的耗时不由该数值代表。

## 已知问题

- C-050-REF-01：固定 Dialogic 2.0-alpha-20 的 Save.to_text() 省略显式 Default 槽，重新解析后 slot_name 变为空字符串，不能保证该样本双向字段保真。保留原始插件及失败记录。
- C-050-HISTORY-03：固定 Dialogic 2.0-alpha-20 的原生 get_full_state 仍包含 simple/full History 数组，即使相应 save 开关为 false；实际存档加载也恢复这些条目。四组合已执行，关闭开关的预期不满足，保留未运行。
- C-050-SAVE-07：准备阶段失败、实际状态暂存后的写入失败、索引提交失败及外部内容修改拒绝均已验证，旧槽和索引保留且可加载；当前 UID 映射无法建立普通用户只读目录前置条件，因此完整用例仍未运行。
- C-040-REF-01：固定 Dialogic 2.0-alpha-20 的原生事件目录顺序未保证 Setting 先于 Variable；本次全新原始参考工程把 setting 识别成 set 变量事件，字段中出现 ting 前缀。PAGE 应用层已修正识别顺序并通过专门用例，但不修改固定插件，不能声称原生双向兼容样本通过。

## 测试与交付

TC-0.5.0-r1 独立全量 482 条：共有 462、Linux 专用 10、Windows 专用 10。完整设计在工程编码前保存。每项执行先保存实际证据、确认成功，再更新状态并推进下一项。失败、阻塞、中断、缺少必要阶段或样本均记“未运行”。执行次数与独立用例数分别统计。

| 范围 | 已运行 | 未运行 |
|---|---:|---:|
| 共有 · Linux | 448 | 14 |
| Linux 专用 | 3 | 7 |
| 共有 · Windows | 0 | 462 |
| Windows 专用 | 0 | 10 |

以上为封包状态，台账截至执行序号 697。封包后的进度包及最终分发核对另由交付回答和 RECORD 记录，不倒写冻结包内状态。

实际环境为 Linux x86_64、虚拟 X11、Mesa llvmpipe、Dummy 音频驱动、UID 0。源码组件、GUI、指定原始参考工程与导出程序的测试方式分别记录。音频验证依据原生播放器状态、时序及文件，不声称已通过物理扬声器听音。Windows 已导出及静态检查，实机测试按约定延后到 1.0.0，状态保持未运行。

尚未完成的 Linux 用例：

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
- C-030-REL-03：需在四包冻结后核对进度包或最终分发；结果由交付回答与 RECORD 补记。
- C-040-REF-01：native_presentation: failed ；未完成边界：固定 Dialogic 2.0-alpha-20 的原生事件目录顺序未保证 Setting 先于 Variable；本次全新原始参考工程把 setting 识别成 set 变量事件，字段中出现 ting 前缀。PAGE 应用层已修正识别顺序并通过专门用例，但不修改固定插件，不能声称原生双向兼容样本通过。。
- C-040-REL-03：需在四包冻结后核对进度包或最终分发；结果由交付回答与 RECORD 补记。
- C-040-REL-04：需在四包冻结后核对进度包或最终分发；结果由交付回答与 RECORD 补记。
- C-050-HISTORY-03：media_runtime: failed ；未完成边界：固定 Dialogic 2.0-alpha-20 的原生 get_full_state 仍包含 simple/full History 数组，即使相应 save 开关为 false；实际存档加载也恢复这些条目。四组合已执行，关闭开关的预期不满足，保留未运行。。
- C-050-SAVE-07：未完成边界：准备阶段失败、实际状态暂存后的写入失败、索引提交失败及外部内容修改拒绝均已验证，旧槽和索引保留且可加载；当前 UID 映射无法建立普通用户只读目录前置条件，因此完整用例仍未运行。；待核对 complete_050_samples。
- C-050-REF-01：native_media: failed ；未完成边界：固定 Dialogic 2.0-alpha-20 的 Save.to_text() 省略显式 Default 槽，重新解析后 slot_name 变为空字符串，不能保证该样本双向字段保真。保留原始插件及失败记录。；待核对 complete_050_samples。
- C-050-REL-02：需在四包冻结后核对进度包或最终分发；结果由交付回答与 RECORD 补记。
- C-050-REL-03：需在四包冻结后核对进度包或最终分发；结果由交付回答与 RECORD 补记。

## 异常历史与恢复

失败、修复、重跑、原生差异和测试脚本修订全部保留在独立 Test_Progress 中。早于当前源码的成功记录不能自动计入当前通过状态。导入、构建或退出异常也须按实际返回码和日志记录，不能用功能断言通过掩盖异常退出。

本版在执行159之后遭遇环境中断，已恢复源码和全部159个检查点，逐一实际回读并核对原回执 SHA256 与 ZIP CRC。第66项首次恢复下载不完整，重取后核对一致；原异常记录保留。恢复后的161在应用启动前因显示服务缺少 xkbcomp 路径失败，恢复相同工具后按原样本重跑。产品源码未因环境恢复而改变。随后扩充原定状态恢复样本，304 确认非空应用历史在进入预览前丢失；306 修复通过，四种生命周期场景同时验证历史隔离、原设置与音频总线、Save 对象和目标磁盘字节恢复。早期结果仅在明确的源码影响评估范围内采用，新增媒体运行和最终程序重新验证。

436 的测试驱动在应用启动前读到不完整本地台账，提交也被完整性校验阻止；已保留原字节，从435/436保存记录恢复完整台账，实际回读436核对一致后补记该次失败。后续执行台账写入采用原子替换、fsync 和字节核对，保存助手等待命令完整结束。

504 发现合法 Setting 被固定插件的 set 前缀识别器先命中。505 保存了两种事件目录顺序的失败复现，506 在应用结构扫描层将 Setting 调整为先于 Variable 识别，同组样本随后通过，包含设置/单项重置/全部重置、普通 SET、嵌套条件与 Jump 子时间线；其余识别器的相对顺序保留，插件文件未修改。最终程序在该修正后重新构建。

544/545 的实际节点、像素和过渡中关闭检查复现重复颜色背景为空及过渡残留。应用清理层在移除布局前取消背景过渡，原生清理后清空背景身份；547–551 全部背景用例复测通过，包含 28 组图像/颜色/淡变/等待组合、过渡中关闭、真实 Restart 和切换内容根。插件源码及原始资源字节保持。

614 在未修改的原始参考工程中复现 Setting 被 Variable 前缀识别器先命中，该原生双向兼容用例保留未运行。616 的50毫秒自动推进样本因轮询采样间隔过长，连两次原生运行也抓到不同帧；改为在原生文本完成信号上同步记录并强制校验全部四条完成状态后，617完整17组效果对照通过。此项仅修正只读观察方式，产品及插件未变。

627–629 导出程序的外部 FontFile 检查暴露较大数值 PackedByteArray 的解析开销，120秒观察窗口仍未完成打开。630 将171272字节真实字体表示为685035字节数值构造文本，单次解码约28.08秒，并复现嵌套类型数组的范围校验错误。应用解码器改为复制连续原文片段，并仅校验当前类型数组包装范围；631 相同字体字节校验通过，单次约0.95秒，原构造器白名单和无效输入拒绝保留。耗时仅代表当前样本与环境，不构成性能保证；两平台程序在修正后重新构建并重新验证。

后续导出程序复测修订了测试观察方式：等待实际画面与保存字节而非窗口标题；对白使用实际面板区域OCR；预览控件识别不依赖换行文本邻接；侧栏按钮在两次位置稳定观察后点击。原整图、失败、坐标和完整重跑均保留，产品源码未因这些观察修订改变。

691 的全新 Source 导入在开始处理 NotoSansCJKsc-Regular.otf 时以信号11退出，后续导出停止。相同源码、相同测试驱动及命令在新目录完整重跑692通过，后续693/695/697的全新构建也通过；根因未定位，不宣称修复了引擎崩溃。原失败和完整日志保留。依赖元数据曾遗留0.4.0/0.3.0标记，已修正为本版0.5.0及实际0.4.0基础包的大小、SHA256，并重新通过文档复核。

常规新检查点采用服务成功回执、准确字节数、上传前后本地哈希及 ZIP CRC 确认，不将此等同于全部检查点都已远端回读。最终正式分发文件另核对实际下载字节。完整命令、原始输出、对象指纹、证据位置与恢复步骤见独立进度包。

## 交付内容

提供 Source、Windows x86_64、Linux x86_64 和独立 Test_Progress 四包。发布说明、路线图及完整用例仅随 Source；测试证据和 RECORD 不进入 Source 或平台包。Source 不包含引擎、导出模板、导入缓存或编译程序。平台包包含实际可执行程序、使用说明、示例和许可，程序未签名。

Source、Windows、Linux 三包的最终字节数及完整 SHA256 在交付回答中提供，不写回 Source 内部形成循环校验。四包及交付 RECORD 另上传 firestorage.ai，分享链接和有效期以最终回答为准。
