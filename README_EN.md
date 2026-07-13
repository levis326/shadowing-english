# Shadowing English · 影子跟读

[中文](README.md) · English

A local-first English learning app built for real video material. Import videos and subtitles you already own, then turn every scene into a deliberate loop: understand it, hear it, and say it out loud.

> **Shadowing English** does not distribute courses or media. Your study materials stay on your own device.

![The three-pass method](assets/showcase/learning-guide.jpg)

## Why Shadowing English

This is not a flashcard app or a test feed. Pick a short scene you genuinely want to revisit:

1. Watch once with bilingual subtitles to understand the story and emotion.
2. Switch to English subtitles, listen sentence by sentence, replay difficult lines, and save useful phrases.
3. Hide the Chinese help and shadow the speaker's timing, rhythm, and tone.

You do not need to understand everything at once. A few spoken lines each day build listening, expression, and instinct together.

## What you can do

- Import local videos and `.srt` subtitles; match episodes by filename
- Navigate and replay line by line in the player, with subtitle modes
- Tap subtitles for word lookup and save words or useful phrases
- Use Shadowing mode to make speaking practice part of your learning progress
- Generate or switch AI subtitles with your own provider configuration
- Continue through your library, phrases, words, and learning journey

![Import local video and subtitles](assets/showcase/import-course.jpg)

## Get started

### Install an app package

Visit [Releases](https://github.com/MarkYuanGo/shadowing-english/releases) to download a package for your platform. Once the first stable release is available, Android, macOS, Linux, and Windows builds will appear there.

### Run from source

Flutter 3.44.4 is required and pinned through FVM.

```bash
git clone https://github.com/MarkYuanGo/shadowing-english.git
cd shadowing-english
fvm flutter pub get
fvm flutter run
```

If you do not use FVM, run the same commands with your local Flutter installation:

```bash
flutter pub get
flutter run
```

## Your first session

1. Open **Learn** and choose **Import a course**.
2. Select a folder containing video files, then optionally a folder of matching English or bilingual subtitles.
3. Review the matches and create your personal library.
4. Open **How to learn** and use the three-pass method for one short scene.

See [RESOURCE_SETUP.md](RESOURCE_SETUP.md) for the media boundary and import details.

## Open source and privacy

- Shadowing English is released under the MIT License.
- This repository contains no third-party videos, courses, commercial subtitle packs, or other study media.
- Imported media and learning records are kept and managed on your own device.

Issues and ideas for better shadowing workflows are welcome.

