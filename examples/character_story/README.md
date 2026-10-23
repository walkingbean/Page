# PAGE Editor 0.0.1 双角色示例

在程序中选择 `examples/character_story` 作为 **Content folder**，然后打开其中的 `conversation.dtl` 并启动 Preview。内容根目录是同时包含 `characters`、`portraits` 和 `conversation.dtl` 的这一层，不是 `characters` 子目录。

示例包含两份原生 `.dch`、两张静态 PNG 和一份 `.dtl`。时间线演示角色对白、姓名颜色、旁白、注释、左右入场和逐一离场。可以整体复制或移动这个目录；PNG 路径始终相对于内容根目录解析。

导入原版 Godot / Dialogic 工程时，将此目录中的 `characters`、`portraits` 和 `conversation.dtl` 复制到目标工程根目录，等待 Godot 完成导入，并在 Dialogic 的资源引用管理中确认 `jane` 与 `antonio` 对应正确的 `.dch`。如果目标工程已有同名文件，请先处理命名冲突；本示例不要求修改目标工程的插件代码。

立绘直接复制自用户提供的 Dialogic 2.0 Alpha 20 包：

- `addons/dialogic/Example Assets/portraits/Jane/pl3 happy.png` → `portraits/jane.png`
- `addons/dialogic/Example Assets/portraits/Antonio/pl5.png` → `portraits/antonio.png`

图片保持原始字节，未重绘。Dialogic 的 MIT 许可证随附于 `DIALOGIC_LICENSE.txt`。角色与时间线使用本版支持的原生格式；示例内容可按需编辑。
