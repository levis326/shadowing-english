# Shadowing English · 影子跟读

[English](README_EN.md) · 中文

一款为真实影视素材而做的本地优先英语学习应用。导入自己拥有的视频和字幕，用「看懂 → 听清 → 跟读」的节奏，把一句句英语真正练到能开口。

> **Shadowing English（影子跟读）** 不提供任何课程或影视资源。你的学习素材始终留在自己的设备上。

![三遍学习法](assets/showcase/learning-guide.jpg)

## 为什么用它

不是背单词，也不是刷题。选择一段你愿意反复看的英文视频：

1. 先用双语字幕看懂剧情和语气。
2. 再切到英文字幕，逐句精听、反复播放、收藏表达。
3. 最后关掉中文提示，模仿角色的节奏和语调开口跟读。

你不需要一次听懂全部。每天完成几句，听力、表达与语感会一起往前走。

## 你可以做什么

- 导入本地视频与 `.srt` 字幕，按文件名自动匹配剧集
- 在播放器中逐句定位、重复播放、切换字幕模式
- 点按字幕查词，沉淀单词与常用短语
- 使用跟读模式，把每一次开口练习记录进学习进度
- 使用 AI 生成或切换字幕（需要自行配置对应服务）
- 从课程库、短语、单词和成长页持续回到下一次练习

![导入本地影视与字幕](assets/showcase/import-course.jpg)

## 开始学习

### 直接安装

前往 [Releases](https://github.com/MarkYuanGo/shadowing-english/releases) 下载适合你系统的安装包。首个正式版本发布后，这里会提供 Android、macOS、Linux 和 Windows 的构建产物。

### 从源码运行

需要 Flutter 3.44.4（项目已通过 FVM 固定版本）。

```bash
git clone https://github.com/MarkYuanGo/shadowing-english.git
cd shadowing-english
fvm flutter pub get
fvm flutter run
```

如果尚未安装 FVM，也可以使用本机 Flutter：

```bash
flutter pub get
flutter run
```

## 第一次使用

1. 打开「学习」页，选择「导入新课程」。
2. 选择你有权使用的本地视频文件夹；可选配同名的英文/中文字幕文件夹。
3. 确认自动匹配结果，建立自己的课程库。
4. 从「怎么学」按三遍学习法开始，先完成一小段，再坚持下一次。

详细的资源边界与导入说明请看 [RESOURCE_SETUP.md](RESOURCE_SETUP.md)。

## 开源与隐私

- 本项目使用 MIT License 开源。
- 仓库不包含影视、课程、商业字幕或其他第三方学习素材。
- 本地导入的媒体与学习记录由你自己的设备保存和管理。

欢迎提交 Issue，分享你最想练习的 Shadowing English（影子跟读）工作流。

