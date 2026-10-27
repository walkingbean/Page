# PAGE Editor 0.6.0 字符串变量示例

1. 把本目录复制到可写位置。
2. 在 PAGE Editor 中将本目录选择为 **Content Folder**。
3. 打开 **Variables**，查看 player_name、greeting 和 empty_value；修改 player_name 的字符串初值并保存。
4. 在 **Timeline** 打开 conversation.dtl，按 **Play / F5**。台词显示保存后的称呼，空值正常显示为空字符串。
5. 停止预览、关闭并重新打开该内容目录，验证保存的初值仍可使用。Restart 从已保存初值开始，预览不改写磁盘初值。

project.godot 只保存本示例的原生 dialogic/variables 设置，没有主场景、脚本、插件或运行工程配置。它不是可直接运行的完整游戏工程。

向安装了 Dialogic 2.0-alpha-20 的 Godot 4.7.1 工程移交时，复制 conversation.dtl，并把 variables 字典合入目标 project.godot 的 [dialogic] 设置；不要覆盖整个目标工程配置。原生设置中保存 String 初值，时间线保留变量引用。

本示例仅演示字符串初值和简单文本引用，不包含赋值事件、表达式、条件或变量文件夹。变量改名不会自动改写时间线引用。
