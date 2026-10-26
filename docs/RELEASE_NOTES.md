# PAGE Editor 0.4.0 发布说明

日期：2026-10-26（UTC+8）。固定 Godot 4.7.1 Standard / Dialogic 2.0-alpha-20，基于正式 0.3.0 Source。

## 本版功能

- Text 全属性、原生 BBCode、文本效果和随机文本；Style、Setting、Wait、WaitInput、Clear、TextInput 的属性编辑与运行预览。
- Style 面板管理原生预设、布局层公开属性、继承、默认样式和字体/图片；Character 提供角色专属样式、前缀及后缀。
- Settings 面板编辑原生文本配置和运行默认项；预览支持实际字符串输入、Auto/Skip，结束后恢复应用设置和资源索引。
- 保留变量、表达式、条件、选项、跨时间线流程、角色与立绘；新增 text_style_story 示例。

根目录 README 保留用户原字节；原始 main.tscn、主题和 Dialogic 插件完整性已核对，未修改插件语义。媒体和存储状态属于 0.5.0，宿主脚本和自定义扩展属于 0.7.0；完整路线图见 ROADMAP.md。本次授权不延伸至下一版本。

## 使用边界与已知问题

1. 原始参考工程中，TextInput 刚出现且文本框隐藏动画尚未结束时立即确认，可能使后续文本停在揭示状态。等待动画完成的正常输入路径通过，快速确认边界未完成，C-040-EVENT-02、C-040-REF-01 保持未运行。
2. 无等待的立绘切换紧接 extra_data，原始参考工程与原始工程重放出现差异。显式等待的稳定样本通过；原边界未修复，C-040-REF-03 保持未运行。
3. Setting 字面字符串含嵌入引号或反斜杠时，Alpha 20 不能无损往返，本版检测不一致并拒绝改写，可使用字符串变量。内容工程 InputMap 不自动导入应用预览。
4. 任意自定义脚本/场景/资源依赖、媒体、术语和翻译按路线图实施；不支持的依赖明确诊断并保留内容。容量限制见 README.md，不构成性能承诺。

## 测试与交付

TC-0.4.0-r1 独立全量 430 条：共有 410、Linux 专用 10、Windows 专用 10。完整设计在生成工程代码前保存。每项执行先保存结果及证据、确认保存成功，再更新状态和执行下一项。已运行要求全部必要阶段通过；失败、阻塞、中断或部分完成均记未运行。

| 范围 | 已运行 | 未运行 |
|---|---:|---:|
| 共有 · Linux | 399 | 11 |
| Linux 专用 | 3 | 7 |
| 共有 · Windows | 0 | 410 |
| Windows 专用 | 0 | 10 |

上述为封包状态，执行台账截至序号 629；执行次数包括不同验证阶段、失败和重跑，不等于独立用例数。封包后的进度包和上传字节核对，由最终回答及 RECORD 补记；不倒写已冻结包内状态。

实际环境：Linux x86_64 / X11 虚拟显示 / Mesa llvmpipe / UID 0，Godot 4.7.1.stable.official.a13da4feb。组件、源工程 GUI、指定原生参考工程、导出独立程序和构建验证分别记录。Windows 两个类别均保持未运行，实机依约延至 1.0.0；Linux 上的 Windows EXE 检查仅为静态验证。

尚未完成的用例：

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
- C-030-REL-03：进度包冻结或最终上传验证需在四包冻结后完成；最终回答和 RECORD 另记结果。
- C-040-EVENT-02：未完成边界：固定原生隐藏动画尚未结束时提前确认，后续文本可能停住；已保留 PAGE 与原始参考失败记录。动画完成后的正常确认已通过，不能覆盖此前失败边界。。
- C-040-REF-01：未完成边界：固定原生隐藏动画尚未结束时提前确认，后续文本可能停住；已保留 PAGE 与原始参考失败记录。动画完成后的正常确认已通过，不能覆盖此前失败边界。。
- C-040-REF-03：未完成边界：无等待的 portrait→extra_data 组合在两次原始工程运行间出现分层状态差异；加入显式等待后的顺序效果已通过，无等待原生边界仍未完成。。
- C-040-REL-03：进度包冻结或最终上传验证需在四包冻结后完成；最终回答和 RECORD 另记结果。
- C-040-REL-04：进度包冻结或最终上传验证需在四包冻结后完成；最终回答和 RECORD 另记结果。

## 异常历史与恢复

首次字体导入出现线程通知错误和 signal 11，原始日志保留在 build_logs/。执行 442 从全新 Source 解压副本完成无错误导入、品牌同步、双平台实际导出与打包；这些程序用于独立程序验收。本轮其他全新副本的导入也有异常退出，具体序号及返回码由下方台账摘要列明。所有失败和后续重跑独立留痕。固定引擎导入异常的根因未确认；失败后应保留日志，从全新副本重新验证，不继续使用失败导入结果发布。

执行 575 的原生流程回放在退出时报告 ObjectDB/resource 泄漏；24 个样本的三方运行值和文本均匹配，但退出检查失败。执行 576 保持同样样本、预期及产品字节，仅增加 verbose 日志后完整通过；未复现不表示已确认或修复根因。

执行 359、379、538 的本地检查点在保存后出现截短或字节不一致，核对立即阻止状态提交和下一项执行。保留截短副本，从已保存的同一文件下载，核对上传前字节数、SHA256 和 ZIP CRC，再恢复提交。前 273 项均作远端下载核对；其后常规检查使用成功保存回执、精确字节数、本地哈希/CRC 和身份信息，不声称每项均远端回读。最终五项正式文件另作远端字节核对。

测试定义仅 C-COND-15 澄清原生标签分类，初版、修订和影响比较均保留；其余 429 条定义不变。测试脚本修订、产品修复、失败及重跑均留痕；当前通过记录对应现有源码或相同导出程序。完整台账、断言和恢复说明见独立 Test_Progress。

## 交付内容

Source、Windows x86_64、Linux x86_64 和独立 Test_Progress 四包。发布说明、路线图和全量用例仅随 Source；测试脚本、证据和 RECORD 不进入产品包。Source 不含引擎、导出模板、导入缓存或编译程序；平台包提供实际程序、说明、示例及许可。程序未签名。

三产品包的最终字节数和完整 SHA256 在回答中列出，不将 Source 自身哈希写回包内。四包及 RECORD 另上传 firestorage.ai，提供分享链接和有效期，核对上传字节一致。

本版发布驱动导入异常摘要：608（C-BRAND-03，退出码 -11）；610（C-BRAND-04，退出码 -11）；612（C-BRAND-05，退出码 -11）。完整日志及成功重跑见进度包。
