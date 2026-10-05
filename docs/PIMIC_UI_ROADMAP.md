# PiMic：可选优化、多机器和手机命令交互

调研日期：2026-10-04。下面区分已实现、已有上游能力和后续建议。

## 当前已实现

- 自定义 STT 和 Draft cleanup 接口分别配置、分别启用，默认关闭。
- 草稿页新增 **Optimize this draft** 勾选项，每次打开默认不勾选。
  不勾选不能请求优化；勾选本身不发请求，继续由 **Suggest cleanup** 触发。
  取消勾选会取消进行中的优化、清除建议，迟到结果不会重新出现。
  已编辑或采用的文本不会因取消勾选而自动回退。
- 原转写、可编辑草稿和优化前后对照保留；采用建议、放入聊天输入框、
  发送消息仍分别由用户操作。优化未配置时文字和 STT 流程继续可用。
- 默认 **仅纠错**，可选 **整理提示词**；切换模式取消旧请求。关键字段
  变化标记并须核对后采用，原稿保留。兼容 Prompt Optimizer 单模板 JSON
  导入/导出，模板仅作用于整理模式；见 [使用说明](PIMIC_OPTIMIZATION.md)。
- 版本 `1.2.0+12` 增加独立默认关闭的目标切换、按机器/项目分组、搜索和
  本次运行收藏；按稳定目标缓存文字草稿与滚动位置。顶部常驻 `/` 入口
  复用原版快捷操作。录音/转写/附件阻止切换；配置、身份或目标变化取消
  目标列表。详情和边界见 [目标工具说明](PIMIC_WORKSPACES.md)。
- 模块集中于 `pimic_addons` 与薄宿主 adapter。未修改 Pi 插件、Relay 协议
  或原版发送处理器；聊天输入栏仅增加可选草稿缓存接口。

## 准确率：先测转写，再测整理

现有实验见主项目 `docs/macmini-stt.md`：6 段真实有线录音，在每个 ANE
节点重复 3 次。mac7 热请求中位数 0.724 秒，P95 0.969 秒，包含局域网
上传和服务端返回，不包含说话、结束静音和手机轮询。样本较少，不能代表
未来所有录音；新 APK 的手动录音流程也没有 VAD 静音等待。

Mac 转写识别到了 `readme`、`package json`、`docker` 和 `17891`，也保留了
“不要执行命令，也不要删除文件”，仍出现“只报告”→“指报告”和繁简混用。
没有独立逐字人工标注，不提供准确率百分比或正式 CER/WER。UI 本身不会
提高声学识别准确率；声级/实际路由显示可帮助发现错误输入、噪声和削波。

建议用 20–30 条经用户确认的真实录音建立验收集：普通中文、中文夹英文、
路径/文件名、数字/端口、否定和停止指令；分别使用内置/有线麦克风、安静/
噪声环境。保留原 WAV、人工原句、原始转写、整理结果和各阶段耗时。
统计中文 CER、技术标识符正确率、否定/数字保留率、整理新增或丢失要求率、
热请求中位数/P95；繁简和标点归一化须提前约定，不能改写数字/标识符。

## mac5 的 Qwen 提示词整理配置

用户所指型号可对应官方 [Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B)。
以 oMLX 实际 `/v1/models` 返回的模型 ID 为准；MLX 转换或量化目录名
可能与官方 Transformers 仓库名不同。版本 12 检查到 mac5 现有
`Qwen3.8-27B-oQ4e-fp16-mtp`、`Qwen3.8-27B-DFlash2` 与
`incoai--Qwen3.8-27B-DFlash2`。当前仅监听本机 `127.0.0.1:18082`，
手机整理仍关闭；没有下载权重或更改现有服务认证、监听和模型设置。
本轮已在 Mac 本机测试该模型：三条文字、两种模式，最终热请求仅纠错
中位 1.313 秒、整理中位 4.963 秒；首次冷加载约 64.5 秒。整理曾改变语言
和补写，规则已加强，但仍须人工对照。不是手机端延迟或正式准确率评估。
实测条件见 [目标工具说明](PIMIC_WORKSPACES.md)。

建议保持 mac7 专职 STT，mac5 的桌面 oMLX 专职文字整理：

```text
手机音频 → mac7 STT → 可编辑转写
                         ↓ 用户勾选并请求优化
                    mac5 oMLX → 对照 → 用户采用 → 目标 Pi 输入框
```

oMLX 0.7.0 提供 OpenAI 兼容 `/v1/chat/completions`，管理界面可配置模型
别名、驻留及 chat template kwargs。手机填 `http://<mac5-LAN-host>:<port>/v1`
和实际模型 ID，并配置该服务要求的 API key。以实际桌面 App 的端口、
监听地址和凭据为准，不填手机本机的 `localhost`，不用恢复 Homebrew 安装。
[oMLX 0.7.0 文档](https://github.com/jundot/omlx/tree/v0.7.0#api-compatibility)

Qwen3.8 默认启用思考；语音整理建议在服务端模型配置中设置
`enable_thinking=false`，避免短句整理产生长思考。先测试保守纠错，再选择
4-bit/6-bit MLX 量化和驻留设置；不能仅凭参数量保证准确率或响应时间。
[官方非思考模式说明](https://huggingface.co/Qwen/Qwen3.8-27B#instruct-or-non-thinking-mode)

版本 11 已将模式分成 **仅纠错**（默认）和 **整理提示词**（用户选择）：

- 仅纠错：标点、明显错字和重复口语；存疑词要求保留。项目词汇表尚未实现。
- 整理提示词：把明确说出的目标、范围、约束和输出要求组织清楚。
  不补造需求，不把“检查”改成“修改”，不删除否定、改变数字、路径或标识符。
- 原始音频未提供给文字模型时，模型只能根据文本推断，不能恢复已丢失的
  声学信息。词汇上下文也应由用户选择，不自动上传整段项目历史。
- 高风险变化标出并保留原稿；优化失败应能直接使用原稿。
- 斜杠/停止/取消等控制指令继续走独立路径，绕过文字优化。

## 多机器：目标选择与历史恢复分开

建议聊天页顶部常驻目标按钮，展示 **机器 / 项目目录 / 房间**、在线状态，
抽屉按机器和项目分组、搜索、收藏。沿用现有配对和路由；从 mac7 切到 mac5
不应要求改变 STT/优化服务。每台 Pi 仍需自己的首次配对。

目标以稳定 `peer identity + room identity` 标识，不能仅靠展示名称或 cwd。
A→B→A 保留各自草稿和滚动位置；切换不停止 A 的后台工作。录音或待发送媒体
切换时明确处理，绝不能误投 B。已有实现会在目标失效时取消语音草稿任务。

**切换在线机器/房间**和**在同一 Pi 中恢复历史 JSONL 会话**是不同操作。
后者需要受控会话目录枚举、稳定会话 ID 及明确的切换确认；不让手机传入
任意文件路径。当前社区对应需求仍开放：

- [#223：聊天内按项目分组切换](https://github.com/jacobaraujo7/remote_pi/issues/223)
- [#194：浏览和恢复保存的会话](https://github.com/jacobaraujo7/remote_pi/issues/194)

长期在线可采用上游 `pi-supervisord` 的后台模式；它解决 Pi 进程生命周期，
本身不会补齐手机的历史会话列表或命令菜单。
[上游 daemon 文档](https://github.com/jacobaraujo7/remote_pi/blob/main/pi-extension/README.md#daemon-mode)

## `/` 命令与交互表单

原版输入栏的 Quick Actions 只在输入框空、无附件且会话可交互时显示；提供
压缩上下文、新会话、模型和思考级别。版本 12 开启目标工具后另有顶部常驻
入口，输入文字后仍可见。离线、连接未就绪或运行中禁用并提供原因；没有
变更原版操作菜单和能力协议。
[上游快捷操作](https://github.com/jacobaraujo7/remote_pi/blob/main/pi-extension/README.md#mobile-app-actions)

不能将任意 `/...` 当普通聊天文字发送就认为执行成功。社区
[#176](https://github.com/jacobaraujo7/remote_pi/issues/176) 仍开放，指出扩展
命令输出、失败和没有 agent turn 的完成反馈都需要处理。
[#32](https://github.com/jacobaraujo7/remote_pi/issues/32) 的旧自动补全请求
关闭为 not planned。其旧 SDK 解释不能直接代表当前 Pi：本机 SDK 已有
`pi.getCommands()`，当前官方 RPC 也支持 `get_commands`。

建议新增可选宿主插件 + 手机独立控制模块，按能力声明展示菜单：

1. 内置操作（新会话、压缩、模型等）继续调用已存在的 typed action。
2. 扩展命令/技能/模板：宿主枚举当前可用目录，返回来源与可执行方式；先
   验证实际 Pi 版本的分发路径和结果，再开放执行，不只添加补全 UI。
3. RPC 宿主可用 `get_commands` + `prompt` 调用注册命令；每次操作必须有
   request ID 和 accepted/completed/error 结果，支持无模型回合的命令。
4. `/settings`、`/hotkeys` 等 TUI 内置命令不在 RPC 命令目录中，不能经
   `prompt` 原样执行；应映射成手机设置 UI 或明确标示桌面专用。
5. 新协议使用能力协商/可选消息，旧宿主缺失能力时退回现有快捷操作，
   未启用控制扩展时保留原版行为。

[Pi RPC 命令文档](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc-commands.md#get_commands)

结构化问答优先复用上游推荐的可选 `@eko24ive/pi-ask`：手机原生呈现选择、
多选和预览，桌面流程获得答案。fork 已包含该桥接，但仍需在实际目标 Pi
安装匹配版本并做端到端测试，不能宣称所有扩展对话框都自动兼容。
[Remote Pi 推荐说明](https://github.com/jacobaraujo7/remote_pi#recommended-companion-eko24ivepi-ask)

通用 RPC `select/confirm/input/editor` 可以映射到手机表单；任意终端
`ctx.ui.custom()` 在 RPC 返回 undefined，必须由插件提供标准表单/文字
回退或另用终端界面。
[Pi RPC UI 边界](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc-extension-ui.md#limitations)

## 建议实施顺序

已完成可选优化勾选项、两种模式、关键变化复核、模板导入和版本 12 目标
入口/按机器分组/草稿隔离/常驻原版操作。mac5 的手机可访问接口和真实
手机整理验收仍需继续，再补命令目录和明确执行结果、pi-ask 真机验收。
历史会话恢复最后作为独立能力实现，避免一次改动侵入上游核心流程。
