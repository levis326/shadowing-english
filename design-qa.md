# Design QA — 逐词全文窗体

- Source visual truth: `/var/folders/sc/wx8s3lns5hl1l1grfqvgkvbr0000gn/T/codex-clipboard-1715addc-a232-4dfc-a33f-5118d9eb1f8d.png`
- Implementation screenshot: `/Users/longpc/.codex/visualizations/2026/07/15/019f6505-402c-7903-86b8-61d63c6b7616/full-transcript-reader-paragraphs.png`
- Full-view comparison: `/Users/longpc/.codex/visualizations/2026/07/15/019f6505-402c-7903-86b8-61d63c6b7616/full-transcript-reader-paragraphs-comparison.png`
- Focused comparison: the changed content region is readable at full size in the 1880 × 760 comparison, so a separate crop was not needed.
- Viewport: 940 × 760 desktop reader window
- State: full transcript loaded, second sentence active, current word boxed

## Findings

- No actionable P0/P1/P2 differences remain.
- Fonts and typography: English words and their smaller meanings keep the existing reader hierarchy. The golden capture loads Nunito for layout fidelity; CJK glyphs and Material icons use test fallbacks, while the supplied live screenshot confirms their production rendering.
- Spacing and layout rhythm: each subtitle sentence is now an independent paragraph with 14 px separation, 18–20 px internal breathing room, and a bottom divider. Sentence boundaries remain clear after word wrapping.
- Colors and tokens: alternating paragraphs use a subtle white wash instead of competing text colors. The current sentence uses a pale green surface and a green left rule, while the current word keeps its existing green box.
- Image quality and assets: this screen contains no required raster imagery. Material icons are used for the book and close controls.
- Copy and content: the header identifies the course, episode, and reading mode. It also provides translation visibility and current-word location controls. Missing dictionary entries display `—`.

## Comparison history

- Initial implementation: words flowed continuously and subtitle sentence boundaries were difficult to scan after wrapping.
- Paragraph pass: added paragraph spacing, dividers, alternating subtle surfaces, and a current-sentence left rule. The post-fix comparison shows clear sentence grouping without changing word colors or obscuring the active-word box.

## Interaction verification

- Widget tests verify glossary priority, offline fallback, missing meanings, serialization, full-word rendering, video-time-driven active-word movement, translation visibility, manual current-word location, paragraph separation, alternating surfaces, dividers, and the current-sentence marker.
- A native macOS smoke run created a second Flutter engine/window and acknowledged that a subsequent progress update was applied as line 2, word 1 through the window channel.
- The host screen-capture API returned a black native Flutter surface in this environment, so visual comparison used the Flutter-rendered component capture; native creation and channel synchronization were verified separately from the visual capture.

## Follow-up polish

- P3: ordinary SRT subtitles without word timestamps use the player's existing sentence-duration estimate, so their word box timing is less precise than AI-generated word-level subtitles.

final result: passed
