# PAGE Editor 0.2.0 流程示例

选为 Content Folder 后打开 conversation.dtl。默认 ready=true、score=2：前往大厅再查看书籍可得分5；看看窗外保持2；留在原地不进入大厅。将 ready 保存为 false 后，大厅选项显示“尚未准备”且不可选择。每次 Restart 从已保存初值开始。

包含基础角色与默认 PNG、条件选项、嵌套条件、跨时间线标签跳转、Return 和 End。原生目录映射及变量放在 project.godot；移交目标 Godot 工程时合并相应 dialogic 配置，保持相对目录，不覆盖整个目标工程配置。
