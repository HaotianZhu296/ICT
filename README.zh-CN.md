# ICT · InClass Translator

[English](README.md) | **简体中文**

ICT 是一个 macOS 小工具：实时监听**麦克风**（讲座、会议、现场交谈）和/或**电脑正在播放的声音**（视频、网课、线上会议），把说话识别成文字、翻译，并以**悬浮双语字幕**显示在所有窗口上面。每次的内容都会自动存成字幕记录，可以一键总结，也可以随时问旁边的 AI 助手“刚才说了什么”。

它最初是为了在口音很重的课堂上也能用自己的语言跟上讲课而做的。

## 亮点

- **本机语音识别**：macOS 26 用 Apple `SpeechAnalyzer`，macOS 14.2–15 用 `SFSpeechRecognizer`。音频不会离开你的电脑。
- **打开就能用**：默认使用 Google 翻译（免费网页接口，不需要 API 密钥），默认英语 → 简体中文。
- **可选其他翻译**：Apple 本地翻译（离线，macOS 26）、Claude Code、自己的 API（OpenAI 兼容或 Anthropic），或通过 Ollama / LM Studio 运行的本地模型。
- **低延迟**：一口气说很长的句子时，在讲者换气处切开、提前翻译；Google 和 Apple 翻译时几句同时进行。实测一个 45 个词的长句，前半句从说完到出译文由 11.7 秒降到 0.9 秒。
- **口音纠正**（默认打开）：识别置信度变低时，让大模型按发音和上下文纠正听错的词（例如 “Chithon” → Python、“things P” → ThingSpeak）。使用 Google 或 Apple 翻译时，纠正期间临时改用 Claude Sonnet。
- **字幕记录与历史**：每句原文和译文实时写入 `~/Documents/ICT/<开始时间>.md`。历史记录窗口列出以前的全部记录，任意一份都能一键总结。
- **AI 助手**在字幕旁边：问刚才讲的内容，或者让它把要点存成文件。
- **浅色 / 深色外观**（默认跟随系统），界面有简体中文和英文。

## 运行要求

- macOS 14.2 或更新（Apple 芯片或 Intel）。

  | 功能 | macOS 14.2–15 | macOS 26 或更新 |
  |---|---|---|
  | 语音识别 | `SFSpeechRecognizer` | `SpeechAnalyzer`，延迟更低 |
  | Apple 本地翻译（离线）及出错时的备用翻译 | – | ✓ |
  | 过滤旁边的中文说话声 | – | ✓ |
  | 口音纠正 | –（旧版识别器不提供置信度） | ✓ |

- 从源码构建需要 Xcode 命令行工具（`xcode-select --install`），不需要完整的 Xcode。

## 安装（从源码构建）

```bash
git clone https://github.com/HaotianZhu296/ICT.git
cd ICT
scripts/make-signing-cert.sh    # 只需一次：创建本机签名证书“ICT Local Signing”
scripts/build-app.sh --install  # 构建，安装到 ~/Applications 并打开
```

本机证书让 App 的签名身份保持不变，重新构建后系统不会再次询问麦克风和系统录音权限。没有证书时用 ad-hoc 签名，每次重新构建都要重新授权。

## 首次使用

1. 打开 ICT，屏幕右上角出现字幕窗口（屏幕面积的 1/16，宽高比 3:1）。
2. 点中间的 **开始翻译**，按系统提示允许 **麦克风** 和/或 **系统录音**。
3. 第一次识别某种语言时，系统会下载语音识别模型（英语大约 10–20 秒）。
4. 可选：想用 Claude 做口音纠正、AI 助手和总结，安装 [Claude Code](https://claude.com/claude-code)，在终端运行 `claude`，输入 `/login` 登录一次。

## 使用

ICT 没有菜单栏图标和 Dock 图标，所有操作都在字幕窗口上。鼠标移到字幕上出现快捷按钮；停在某个按钮上时，按钮会变亮，下面显示它的功能名。

| 按钮 | 作用 |
|---|---|
| ▶ / ⏸ | 开始 / 停止 |
| 📌 | 置顶（默认打开）：字幕总在所有窗口上面。取消后可以被别的窗口盖住，点一下字幕回到最前面 |
| 🎙 | 音源：麦克风、系统音频或两者 |
| 📄 | 本次的字幕记录：生成笔记、导出 SRT/WebVTT、开始新的记录，以及打开**历史记录** |
| ✨ | 显示 / 隐藏 AI 助手 |
| ⚙︎ | 设置 |
| ✕ | 退出 |

- **⌃⌥L** 收起或显示字幕；用 Spotlight 再打开一次 ICT 也能把字幕叫回来。
- 按住字幕任意位置**拖动**；拖边框或四角**调整大小**。窗口大小只在你调整时改变，不会随字幕内容忽大忽小。
- 在字幕上**向上滚动**查看前面的句子，点“返回实时”回到最新。
- **设置**左边是侧边栏（翻译、音频、字幕、记录、高级），点一下跳到那一组。改动立即生效，可以边改边看效果；点右上角 **完成** 保留。直接关窗口时，ICT 会问你保留（完成）还是恢复到打开设置前的样子（取消）。
- **锁定**（设置 › 字幕）后字幕点不到、不挡操作。鼠标移到字幕上，点右上角的锁解锁。

## 翻译模型

| 档位 | 需要准备 | 口音纠正、AI 助手、总结 |
|---|---|---|
| 基础：Google 翻译 | 无（需要联网，文字会发送给 Google） | 装了 Claude Code 时可用 |
| 基础：Apple 本地翻译 | macOS 26 和对应语言包（ICT 会提示下载） | 装了 Claude Code 时可用 |
| 云端模型 | Claude Code，或自己的 API 密钥 | ✓ |
| 本地模型 | 在本机运行 Ollama 或 LM Studio | 取决于模型 |

Google 翻译用的是非官方的免费网页接口：不需要密钥，但没有官方保证，短时间请求太多会被限流（HTTP 429）。ICT 准备了两个接口：`gtx` 接口，以及 Chrome 词典扩展用的接口。一个被限流就换另一个，被限流的那个休息一分钟；两个都失败时等 1–4 秒再试一次。还不行时，如果本机装了 Apple 翻译语言包，就改用 Apple 本地翻译。同时最多翻译两句。

添加自己的 API 或本地模型：设置 › 翻译 › 模型服务 › **管理…** → **添加模型服务**。内置 Anthropic、OpenAI、DeepSeek、通义千问、Gemini、OpenRouter、Ollama 和 LM Studio 的模板。API 密钥保存在系统钥匙串里。

### 隐私

- 语音识别始终在本机完成，音频不会上传。
- 使用 Google 翻译、Claude 或自己的 API 时，识别出的文字会发送给对应服务。
- 使用 Apple 本地翻译或本地模型时，所有内容都留在本机。

## 工作原理

```
采集 ─▶ 识别 ─▶ 断句 ─▶ 翻译 ─▶ 显示
麦克风 /  SpeechAnalyzer  分句、换气处   Google / Apple /   悬浮字幕
系统声音  （临时+确认结果） 提前确认      Claude / API / 本地        │
                                                                    ▼
                                                     字幕记录（.md）、导出、总结
```

- **断句**（`Sources/ICTCore/2-Segmentation`）：完整的句子立即送去翻译；“Okay.”“Right?” 这类碎句和相邻句子合并；太长的字幕在逗号处拆开。讲者一直不停时，`BreathCutter` 从音量里找换气的短暂回落，`PartialCommitter` 把已经识别出的词提前确认，前半句不用等讲者停下来就能翻译。
- **识别质量**（`Sources/ICTCore/1-Recognition`）：按最近几十个词的平均置信度决定什么时候开始口音纠正（很快）、什么时候停止（连续清楚一分钟后）。
- **翻译队列**：Google 和 Apple 几句同时翻译；大模型会话带着上下文按顺序翻译。翻译跟不上时把积压的句子合并成一次请求，延迟不会越拖越长。

### 目录结构

代码按流水线环节分类：

```
Sources/ICT/
  App/                    入口、AppDelegate、设置数据、快捷键
  Pipeline/
    SubtitleController    整条流水线的总控（开始、停止、改设置后重启）
    1-Capture/            麦克风、系统声音（Core Audio process tap）、测试音频文件
    2-Recognition/        SpeechAnalyzer / SFSpeechRecognizer 识别引擎，处理识别结果
    4-Translation/        Google、Apple、Claude 命令行和 HTTP API 翻译器，翻译队列
    5-Display/            悬浮字幕窗口
    6-Transcript/         记录文件、导出、笔记，字幕记录和历史记录窗口
  Assistant/              AI 助手会话和面板
  Settings/               设置窗口和模型服务窗口
Sources/ICTCore/          纯逻辑，配单元测试，同样按环节分目录
Tests/ICTCoreTests/       单元测试（Swift Testing）
scripts/                  构建、测试、打包脚本
```

### 开发

```bash
swift build
scripts/test.sh                          # 单元测试（补上命令行工具链需要的宏插件路径）
B=.build/debug/ICT
$B --transcribe-file talk.aiff --realtime                # 识别 + 断句
$B --translate "First sentence." "Second one." --engine google
$B --export-test talk.aiff out.srt                       # 跑完整条流水线后导出 SRT
$B --render-window out.png --hover                       # 字幕窗口离屏截图
```

用 `say -o talk.aiff "..."` 生成测试音频。命令行工具链没有 SwiftUI 宏插件，界面代码不用 `@State`，改用 `@Observable` 小对象。

## 已知限制

- 用本机证书签名，没有经过 Apple 公证。
- Intel 版能编译，但还没在 Intel Mac 上实际运行过。
- macOS 14.2–15 上识别准确度较低，字幕时间轴是估计值。
- 音源选“两者”并用扬声器外放时，麦克风会把电脑声音再录一遍，可能出现重复字幕。打开麦克风降噪（回声消除）可以减轻，戴耳机则没有这个问题。

## 致谢

ICT 参考和借鉴了下面这些项目的思路：

- [LiveSub](https://github.com/ShuoYang-cs/LiveSub)：macOS 实时双语字幕应用
- [AirTranslate](https://github.com/himomohi/AirTranslate)（Apache-2.0）：基于 SpeechAnalyzer 的 macOS 字幕应用
- [LiveCaptions-Translator](https://github.com/SakiRinn/LiveCaptions-Translator)（Apache-2.0）：Google 备用接口、机器翻译的上下文处理、只保留最新结果的翻译队列
- [whisper_streaming](https://github.com/ufal/whisper_streaming)（MIT）：LocalAgreement，提前确认稳定的前缀
- [WhisperLiveKit](https://github.com/QuentinFuxa/WhisperLiveKit)（Apache-2.0）：区分已确认文字和缓冲文字
- [WhisperLive](https://github.com/collabora/WhisperLive)（MIT）：输出不再变化时确认
- [obs-localvocal](https://github.com/royshil/obs-localvocal)（GPL-2.0）：滚动字幕缓冲
- [my-translator](https://github.com/phuc-nt/my-translator)（MIT）：本地翻译的提示词设计
- [Easydict](https://github.com/tisfeng/Easydict)、[py-googletrans](https://github.com/ssut/py-googletrans)、[pot-desktop](https://github.com/pot-app/pot-desktop)：应对 Google 翻译限流的做法

同时用到了 Apple 的 Speech 与 Translation 框架、Google 翻译，以及 [Claude Code](https://claude.com/claude-code)。

ICT 是一个个人小项目，按现状分享。
