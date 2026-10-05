# PiMic 语音草稿纠错、整理与开源模板

版本：1.2.0+11。实现位于独立 `app/packages/pimic_addons` 包；宿主、Pi
插件和 Relay 协议无需为这次更新改动。新安装仍可完全按原版流程使用。

## 手机如何使用

1. Settings → **PiMic · Voice & draft tools** → **Draft cleanup**，填写内网
   OpenAI 兼容 Base URL、模型 ID 和服务要求的可选 API key，明确启用并保存。
   STT 是另一个独立开关；输入文字或导入录音也能使用草稿工具。
2. 打开语音草稿，录音转写或输入文字。每次打开 **Optimize this draft**
   默认不勾选；关闭状态不会请求文字模型。
3. 勾选后选择 **仅纠错**（默认）或 **整理提示词**，点击 **Suggest cleanup**。
   勾选和切换模式本身不发请求；切换模式会取消旧优化并丢弃迟到结果。
4. 对照 Original text / Cleanup suggestion。数字、端口、路径、文件名、
   常见代码标识符和否定/范围限制出现变化时显示下划线、变化列表，需要
   勾选 **我已核对这些变化** 才能 **Use suggestion**。也可直接保留原稿。
5. **Use draft** 放回目标 Pi 的输入框；仍由用户按原版 Send 发送。

“仅纠错”要求最小修改明显转写错字、标点、重复口语，不加标题、不扩写。
“整理提示词”仅组织原文已有目标、范围、约束和输出要求，不补造缺失信息。
两个模式都要求保留原意、数字、路径、标识符、否定及权限；存疑词保留。
这些是模型指令，不能保证模型遵守。变化检测是文本规则：会有漏报和误报，
也不能判断相同数字/词语在不同语境中的关系；没有标记仍须复核原意。
用户项目词汇表、音频强制对齐和按声学信息重新解码尚未实现。

## Prompt Optimizer 如何整合

调研使用 [linshenkx/prompt-optimizer](https://github.com/linshenkx/prompt-optimizer)
的 `develop` 分支，参考提交
`92c5aaadc43c60243a3ba68a2016183986e04d84`（2026-09-24）。
它支持用户/系统提示词、可编辑模板、自定义模型服务及独立 MCP 服务。
其核心为未单独发布的 TypeScript 工作区包，直接嵌入 Flutter 不合适。
当前源码采用 [AGPL-3.0-only](https://github.com/linshenkx/prompt-optimizer/blob/92c5aaadc43c60243a3ba68a2016183986e04d84/LICENSE)。

本 APK 独立实现**单模板 JSON 格式兼容**，没有打包其运行时、源代码或内置
提示词文本，也不需要运行 Prompt Optimizer/MCP 才能使用。用户可在外部工具
编辑模板，再自行导入。所导入模板的内容和许可由其来源决定。

设置页展开 **Prompt Optimizer 模板（可选）**：

- **复制内置模板**：复制 PiMic 自行编写的整理规则 JSON，在外部工具导入、
  编辑和比较效果。不会导出 API key、配对身份或整个设置。
- 外部工具导出**一个用户提示词优化模板**，在手机 **导入 JSON** 中粘贴。
  校验通过后仍需 **Save settings**。导入和保存不会启用模型或调用 API。
- **复制当前模板** 可回传修改过的模板；**恢复内置模板** 清除自定义内容。
- 自定义模板只参与 **整理提示词**；**仅纠错**使用固定规则。请求仍走手机
  配置的 `/chat/completions`，不走外部工具自己的模型账号。
- 客户端总会附加原文 JSON 和保留原意规则；模板要求补造需求的指令被明确
  禁止。模型遵从度仍需实际测试，关键变化仍需用户复核。

支持的兼容范围：

| 项目 | 支持范围 |
|---|---|
| JSON 类型 | 单个对象，`metadata.templateType = userOptimize`；不接受完整备份数组或 systemOptimize |
| 字段 | `id`、`name`、`content`、`metadata`；导出时生成规范 metadata |
| 纯文本 content | 按上游行为作为字面 system 消息，不渲染变量 |
| 消息 content | 1–4 条纯 system/user 消息，每条仅 role/content |
| 占位符 | `{{originalPrompt}}` HTML 转义；`{{{originalPrompt}}}`原文 |
| JSON helper | `{{#helpers.toJson}}{{{originalPrompt}}}{{/helpers.toJson}}` |
| 未支持 | 其他变量、循环、复杂 section、assistant/tool 消息、工具调用；导入时报错，不静默忽略 |
| 大小限制 | JSON 16,384 字符；每条 content 8,192 字符 |

插入的原文不会再次展开成模板，避免用户说出的 `{{...}}` 被当作变量执行。
实现依据：[模板接口](https://github.com/linshenkx/prompt-optimizer/blob/92c5aaadc43c60243a3ba68a2016183986e04d84/packages/core/src/services/template/types.ts)、
[单模板导入导出](https://github.com/linshenkx/prompt-optimizer/blob/92c5aaadc43c60243a3ba68a2016183986e04d84/packages/core/src/services/template/manager.ts)、
[渲染规则](https://github.com/linshenkx/prompt-optimizer/blob/92c5aaadc43c60243a3ba68a2016183986e04d84/packages/core/src/services/template/processor.ts)。

[Microsoft PromptWizard](https://github.com/microsoft/PromptWizard) 更偏向借助
反馈、样例和迭代优化任务提示词，适合后续离线评估纠错规则；本次未集成。
当前短句流程继续一次文字模型请求，避免增加必需服务和额外推理轮次。

## mac5 / oMLX 配置与验收边界

mac7 继续语音转写；mac5 的桌面 oMLX 可单独提供文字模型服务。填实际
LAN Base URL 和 `/v1/models` 返回的模型 ID，凭据由用户明确配置。
优化缺失或服务失败时原稿继续可用；不依赖模型才能连接 Pi。

本次没有下载或启动 mac5 的 Qwen 模型，也没有对真实模型纠错质量作结论。
离线测试覆盖选定模式、模板格式、HTTP 请求、取消竞争、关键字段复核和 UI。
后续用经用户确认的原句与转写测试技术标识符、数字/否定保留率、误改率和
请求延迟；文字模型无法凭空恢复 STT 已丢失的声音信息。
