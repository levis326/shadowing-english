<p align="center">
  <img src="assets/img/app_icon.png" alt="Shadowing English app icon" width="112" />
</p>

<h1 align="center">Shadowing English</h1>

> A local-first English shadowing app for listening and speaking practice with your own videos and subtitles.

> 使用自己的视频和字幕，通过逐句精听、重复播放和影子跟读练习英语听力与口语。

[English](README_EN.md) · 中文

[![License: MIT](https://img.shields.io/badge/License-MIT-0F766E.svg)](LICENSE)
[![CI](https://github.com/MarkYuanGo/shadowing-english/actions/workflows/lint.yaml/badge.svg)](https://github.com/MarkYuanGo/shadowing-english/actions/workflows/lint.yaml)
[![Flutter 3.44.4](https://img.shields.io/badge/Flutter-3.44.4-02569B?logo=flutter&logoColor=white)](.fvmrc)
[![Latest release](https://img.shields.io/github/v/release/MarkYuanGo/shadowing-english?display_name=tag&sort=semver)](https://github.com/MarkYuanGo/shadowing-english/releases/latest)
[![Release platforms](https://img.shields.io/badge/Release-Android%20%7C%20macOS%20%7C%20Linux%20%7C%20Windows-475569)](https://github.com/MarkYuanGo/shadowing-english/releases/latest)
[![GitHub stars](https://img.shields.io/github/stars/MarkYuanGo/shadowing-english?style=flat)](https://github.com/MarkYuanGo/shadowing-english/stargazers)
[![GitHub issues](https://img.shields.io/github/issues/MarkYuanGo/shadowing-english)](https://github.com/MarkYuanGo/shadowing-english/issues)

[下载最新版](https://github.com/MarkYuanGo/shadowing-english/releases/latest) · [从源码运行](#从源码运行) · [导入学习素材](#导入学习素材)

## 功能截图

| 播放与逐句精听 | 导入本地视频与字幕 |
| :---: | :---: |
| <img src="assets/showcase/player.png" alt="逐句精听、播放控制和字幕面板" width="100%" /> | <img src="assets/showcase/import-course.jpg" alt="导入本地视频与字幕的流程" width="100%" /> |
| 点按字幕、循环难句，在视频与原句之间保持专注。 | 选择自己的媒体与字幕，确认匹配后开始学习。 |
| 三遍学习法 | 学习成长与等级 |
| <img src="assets/showcase/learning-guide.jpg" alt="Shadowing English 的三遍学习法页面" width="100%" /> | <img src="assets/showcase/growth.png" alt="学习成长、等级和学习路线" width="100%" /> |
| 先理解，再精听，最后跟读。 | 记录练习、积累经验，清楚看到下一步。 |
| 单词本 | 短语复习 |
| <img src="assets/showcase/words.jpg" alt="单词本与词义查看" width="100%" /> | <img src="assets/showcase/phrases.jpg" alt="短语收藏与复习空间" width="100%" /> |
| 将查过的重点单词留在语境中继续复习。 | 收藏值得反复开口练习的表达。 |
| 字幕、翻译与播放设置 | |
| <img src="assets/showcase/settings.jpg" alt="字幕、翻译和播放相关设置" width="100%" /> | |
| 按自己的学习方式配置字幕与辅助能力。 | |

Shadowing English 是一个 English shadowing app：你导入自己有权使用的本地视频和字幕，用真实场景完成听懂、重复、模仿和开口表达。项目不提供任何影视、课程或字幕资源；学习素材保留在你的设备上。

## 什么是 Shadowing English

影子跟读不是只跟着念一遍台词。它把英语听力练习和英语口语练习放在同一段真实视频里：先理解内容，再辨认声音，最后模仿说话者的节奏、连读、语调和发音。

你可以把自己想看的内容变成字幕英语学习材料。单词和短语不会脱离语境，下一次也能回到原来的句子继续练。

## 影子跟读怎么学

1. **理解 Understand**：打开双语字幕，先了解剧情、人物关系和说话语气。
2. **精听 Listen**：切换到英文字幕，逐句定位、重复播放，把难句听清楚。
3. **跟读 Shadow**：减少字幕辅助，模仿原声的节奏、连读、重音与语调。

短句循环让听觉识别和口语输出不断衔接。每次只练几句，也能逐步从“看懂字幕”走到“听懂并说出来”。

## 核心功能

- **本地视频导入**：从设备选择自己的视频文件夹，建立个人课程库。
- **字幕导入与匹配**：导入 `.srt` 或 `.vtt` 字幕，按文件名和集数标记匹配视频与字幕。
- **逐句字幕导航**：点按字幕定位播放位置，在完整视频中专注当前句子。
- **单句重复播放**：快速重播当前句子，并可开启单句循环。
- **字幕显示模式**：根据学习阶段切换英文、双语或隐藏字幕。
- **字幕查词**：点按字幕中的单词查看释义，并保留在原始语境里。
- **单词与短语收藏**：将值得复习的单词和表达保存到单词本、短语库。
- **Shadowing 跟读模式**：记录每次跟读练习，让开口练习进入学习进度。
- **学习成长**：查看学习时长、句子、短语、课程进度、等级与成就。
- **可选 AI 字幕**：为没有现成字幕的视频生成或切换字幕，需要自行配置服务商。
- **本地优先**：视频、字幕和学习记录以设备本地内容为中心。

## 为什么使用它

- **从你真正想看的视频开始**：看视频学英语不必依赖固定课程包。
- **让表达留在场景中**：单词、句子和短语来自真实对话，而不是孤立列表。
- **同一句可以反复练**：逐句定位与循环播放适合精听和 English shadowing practice。
- **听力和口语一起练**：先听懂，再跟读，减少“认识但说不出”的断层。
- **素材由你掌控**：本地视频和字幕不会被项目服务器收集或分发。

## 开始使用

### 下载应用

最新版为 [v0.1.1](https://github.com/MarkYuanGo/shadowing-english/releases/tag/v0.1.1)，已提供以下安装包：

- Android：APK
- macOS：DMG
- Linux：x64 `.tar.gz`
- Windows：x64 `.zip`

前往 [Releases](https://github.com/MarkYuanGo/shadowing-english/releases/latest) 选择对应平台下载。

从 v0.1.2 起，每个版本附带 `SHA256SUMS.txt`，可用于校验下载文件是否完整。

桌面安装包内置了用于本地音频提取的精简版 FFmpeg，无需用户额外安装；许可证和构建信息会随应用一起发布。

### 从源码运行

需要 Flutter 3.44.4；仓库通过 FVM 固定版本。首次使用请先安装 [FVM](https://fvm.app/documentation/getting-started/installation)。

```bash
git clone https://github.com/MarkYuanGo/shadowing-english.git
cd shadowing-english
fvm use 3.44.4
fvm flutter pub get
fvm flutter run
```

在 VS Code 中安装 Flutter 与 Dart 扩展，打开项目根目录后，选择运行和调试配置 `Flutter - Prod (select device)`，再按 F5。项目会通过 `.fvm/flutter_sdk` 使用固定的 Flutter 版本；请不要提交本机 SDK 路径、设备 ID 或密钥。

如果使用自己的 Flutter 环境，也可以执行：

```bash
flutter pub get
flutter run
```

## 导入学习素材

推荐让视频与字幕使用相同的集数命名，例如：

```text
Friends-S01E01.mp4
Friends-S01E01.en.srt
Friends-S01E01.zh.srt
```

英文字幕可以是同名的 `Friends-S01E01.srt`，也可以通过 `.en`、`_en`、`english` 等文件名标记识别。导入前请确认你拥有相应媒体和字幕的使用权。

更多说明见 [RESOURCE_SETUP.md](RESOURCE_SETUP.md)。仓库不附带影视内容、商业字幕或未经授权的学习资源。

## 隐私

- 视频、字幕和学习记录以本地设备为中心保存和管理。
- 项目不会提供或托管你的课程资源。
- 如果你启用 AI 字幕或翻译，会使用你自行配置的第三方服务；相应请求由该服务商处理。

## 参与贡献

欢迎提交 [Issue](https://github.com/MarkYuanGo/shadowing-english/issues)，尤其是字幕匹配、播放器与跨平台问题。准备 Pull Request 前，建议先开 Issue 讨论；请不要提交未经授权的视频、字幕或课程资源。

## License

Shadowing English 使用 [MIT License](LICENSE) 开源。

如果你正在寻找一个用本地视频练习英语听力、英语跟读和英语口语表达的工具，欢迎试试 Shadowing English。
