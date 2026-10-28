# 她一直都在 · Still With You

一个本机优先的 macOS 桌面陪伴程序：把人物设定、聊天原文、可纠正的关系记忆、桌面互动、计划与专注记录放在同一个可备份的应用里。

它是记录驱动的 AI 模拟，不是现实人物本人，也不应替代真实关系或现实生活。

## 下载后需要配置几步？

程序内和这里使用完全相同的 4 步编号：

1. **名字与边界（必选，约 1 分钟）**：填写对方的名字、对方如何称呼你，以及人物描述与边界。
2. **照片动画卡（可选，约 1 分钟）**：选择一张照片后先预览真实头像与动作卡，可缩放、移动取景或换照片，确认后再生成 11 组轻动画 PNG；不会用 AI 改人物姿势，也不会上传。私人数据目录会保留一份仅供再次调整的本机工作图，但导出备份不会包含它。不配置时使用内置抽象形象。
3. **聊天与记忆（可选，时间取决于资料量）**：可一次选择多个 TXT、Markdown、JSON、JPG/PNG、Word 或 PDF，并专门识别 WeFlow 的 Markdown 导出格式。图片与扫描 PDF 使用 macOS 本机 OCR；原文独立保存，不强制生成描述或总结。程序会让你确认哪一位是对方，确认前可取消并撤销本次导入。
4. **AI 与语音（可选，约 2 分钟）**：聊天可选择 DeepSeek、OpenAI 或自定义 OpenAI 兼容地址。语音默认使用免费的 macOS 系统朗读；如需复刻声音，可另行填写自己的阿里云百炼 API Key 与音色 ID。

语音也是可选项。复刻声音失败时会自动回退到 macOS 系统朗读；不开启语音不影响任何文字功能。

不配置第 2—4 步，计划、计时、桌面互动、本机记录与备份仍然可用。

## 功能

- 可拖动的桌面伙伴、动作反馈、聊天窗口和菜单栏入口
- 日计划、专注与运动计时、提前提醒、反馈与统计复盘
- 选择照片后预览、调整取景，并在本机生成头像、动作图和桌面动画图集；替换前先确认，取消或失败不会覆盖现有形象
- 导入聊天原文；支持 UTF-8 TXT / Markdown / JSON / JSONL、WeFlow Markdown、JPG / PNG / HEIC / TIFF、DOC / DOCX / RTF 和 PDF，可多选；文字文件最多 10 MB，图片和文档最多 50 MB；每次导入后确认谁是对方
- Persona 优先、Relationship Memory 次之的对话链路
- 相关记忆检索、偶尔自然提起往事、最多一件往事/回复
- 用户纠正立即生效；修改前自动存档；最多保留 20 个可回滚版本
- 回复质量守卫：拦截近期重复、无关劝睡、冒充真人、关系夸大和异常长回复，并自动重写一次
- DeepSeek、OpenAI、OpenAI 兼容 API
- macOS 系统朗读、可选百炼复刻声音、聊天 Markdown 导出、完整 JSON 备份与恢复
- 数据默认保存在 `~/Library/Application Support/StillWithYou/`

## 安装

### 下载发行包

从 GitHub Releases 下载 `Still-With-You-macOS.zip`，解压后把 `Still With You.app` 拖进“应用程序”。

这是开源的 ad-hoc 签名版本。首次打开若 macOS 提示无法验证开发者，请在 Finder 中右键应用并选择“打开”，再次确认。请只从本仓库的 Releases 下载。

要求：macOS 14 或更高版本。

### 从源码构建

```bash
git clone https://github.com/syfszt-bigbro/still-with-you.git
cd still-with-you
swift run CoreChecks
swift run CharacterAssetChecks
swift run HistoryDocumentChecks
./scripts/privacy_audit.sh
./scripts/build_app.sh
open "dist/Still With You.app"
```

构建脚本会生成：

- `dist/Still With You.app`
- `dist/Still-With-You-macOS.zip`

## 聊天记录格式

最简单的是纯文本或 Markdown。也可以直接选择 JPG/JPEG/PNG/HEIC/TIFF、Word（DOC/DOCX/RTF）或 PDF。图片和扫描型 PDF 会在本机使用 macOS Vision OCR，不上传；聊天截图中的文字会按版面保留为“左侧 / 右侧”候选，再由你确认哪一边是对方。文字型 PDF 与 Word 会先提取正文，再进入同一套说话人确认流程。

JSON 可使用数组，或包含 `messages` 数组：

```json
[
  {"timestamp":"2025-05-01 19:20","speaker":"她","text":"下雨了，先躲一下"},
  {"timestamp":"2025-05-01 19:21","speaker":"我","text":"好"}
]
```

也支持 `role/content` 字段，以及 TXT/Markdown 中的 `我：…`、`她：…` 等明确说话人格式。WeFlow 文件会按 `## 日期 时间 说话人` 读取消息，文件头、引用和链接不会被当成人名；会话 ID 与消息序号用于在群聊/私聊之间准确去重。导入后会显示 AI/本机识别建议和少量原文样例，并要求你亲自确认哪位是对方。如果候选不对，可“取消并撤销本次导入”，不会删除以前的记录。导入只保存原文，不会自动制造总结。

## 对话为什么比普通角色提示更稳

每轮按固定顺序工作：

1. Persona 决定身份、硬规则、说话方式、情感表达和关系行为。
2. 只检索与本轮相关且至少有一条原文证据的 Relationship Memory。
3. 用户纠正覆盖旧总结和旧对话。
4. 普通生活问题优先回答眼前的话；往事只是可选素材。
5. 回复显示前经过质量守卫；不合格时自动要求模型重写一次。

模型每轮最多看到最近 24 条应用内对话和少量相关记忆，不会把整个资料库发送给 API。只有用户询问往事时，才额外检索最多 4 个相关命中及其相邻句（最多约 12 段，每段截取 450 字）；说话人识别每次最多发送 20 个候选、每人最多 3 条 160 字样例。

## 隐私与费用

- 代码仓库不包含任何示例真人照片、聊天记录、API Key 或专用音色 ID。
- 名字、聊天、照片动作包、取景工作图、计划、纠正和版本默认只保存在本机；取景工作图不进入导出备份。
- API Key 只保存在 macOS 钥匙串，不进入状态文件或备份。
- 只有开启 AI 后，当前请求所需的最近对话、相关证据记忆和必要任务资料才会发给你选择的服务商。导入后识别说话人时，只发送候选名称和每人最多 3 条短样例，并仍需人工确认。
- 选择百炼复刻声音后，待朗读文字会发送到阿里云百炼；公开程序不包含任何私有音色 ID，配置失败会回退系统朗读。
- API 和模型费用由服务商收取；程序会累计显示成功请求次数与 token 数。
- 运行 `./scripts/privacy_audit.sh` 可扫描工作区和 Git 历史中的常见凭据、旧项目标记与异常媒体文件。

## 测试

```bash
swift run CoreChecks
swift run CharacterAssetChecks
swift run HistoryDocumentChecks
swift build -c release
./scripts/privacy_audit.sh
```

核心检查覆盖计时、迁移、备份、聊天导入、证据记忆、Persona 顺序、相关检索、纠正与回滚、API 配置持久化，以及重复/劝睡/身份与关系夸大的回复质量守卫。照片动画检查会验证默认取景保留完整画面、调整取景确实改变结果、工作图和参数可供再次编辑，以及 11 个动作文件完整生成。文档导入检查会现场生成虚构 JPG、扫描 PDF 和 DOCX，验证本机 OCR、左右说话人、Word 提取与来源去重标识。

## 设计来源与许可

项目借鉴了 [therealXiaomanChu/ex-skill](https://github.com/therealXiaomanChu/ex-skill) 的 Persona / Relationship Memory 分层、纠正层和版本演进思路，并重新实现为本机 macOS 应用。原项目及本项目均采用 MIT License；详见 [LICENSE](LICENSE)。

## 写在最后

你喜欢过的人，不论你们有没有真正走到一起，也不论那段同行持续了多久，都可能在你身上留下不可磨灭的痕迹。

这个程序不是为了把谁困在过去，也不是让一段模拟替代真实的人。它只是帮你把那些聊天、照片、习惯和片段妥善收好，让你有机会看清：那段情感给过你什么，你又因此成为了怎样的人。

我们不应把记忆变成执念。真正好的情感，即使没有结局，也应当让人更坦荡、更温柔、更有勇气向前。愿你保存那些照亮过你的部分，也把自己带往更明亮的生活。

这就是“她一直都在”的初衷：不是让她永远停在这里，而是让被她改变过的你，继续向阳而行。
