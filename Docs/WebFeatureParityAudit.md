# Web Feature Parity Audit

Date: 2026-06-07

Scope: compare non-Discord web functionality in `/Users/wingfungwong/Downloads/time_tavern` against the native iOS app in `/Users/wingfungwong/Downloads/TimeTavern-iOS`.

## Status Legend

- Complete: iOS has an equivalent native flow and tests or build coverage.
- Partial: iOS has the main flow but misses web behavior or depth.
- Not Applicable: web server/Desktop-only or Discord-specific behavior intentionally excluded from iOS.
- Missing: no current iOS equivalent found.

## Coverage Matrix

| Web Area | iOS Status | Evidence / Notes |
| --- | --- | --- |
| DeepSeek key settings | Complete | Keychain storage, multiple DeepSeek keys, model/base URL/max tokens/temperature, connection test. |
| DeepSeek cache usage explanation | Complete | Settings copy explains cache hit/miss and AI Logs show usage summary. |
| Web `.env` editor / server restart / port | Not Applicable | iOS is standalone and should not edit `.env` or restart Node. |
| Chat send streaming | Complete | `TimeTavernStore.send`, `DeepSeekClient.streamCompletion`, VN composer send/stop UI. |
| Chat stop generation | Complete | `cancelGeneration()` and composer stop button. |
| Chat reload/regenerate latest | Complete | `regenerateLatestAssistant()` plus header action. |
| Chat replay / replay-edit branch | Complete | Message context menu branch replay with backup session. |
| Message direct edit | Complete | Added native message edit sheet and `updateMessage(id:content:)`. |
| Assistant message feedback | Complete | Added positive/negative/clear feedback storage and context menu actions. |
| Run-time auto 推演 | Complete | Native flow uses the same web `/run_time` turn prompt template, clamps to 20 turns, rejects empty/invalid requests, disallows the card-creation assistant, and runs turns serially. |
| AI logs | Complete | AI logs screen plus usage/cache summary. |
| Role card create/edit/delete/start | Complete | Characters tab, editor, delete, start role card. |
| Role card custom sections | Complete | Empty new cards, add/edit/delete, bundled defaults decode full content. |
| Role card opening dialogues | Complete | Multiple openings, delete fallback to empty opening, start uses active opening. |
| Role card lorebooks | Complete | Add/edit/delete and keyword matching in `ConversationEngine`. |
| Role card cover image | Complete | iOS supports PhotosPicker, preview, coverPosition, and a crop editor that writes the cropped JPEG back to `coverImageData` / `coverImageDataURL`, matching the web destructive crop-output model. |
| Role card JSON import/export | Complete | Native/web/SillyTavern JSON import, conflict copy, export/share. |
| Role card PNG/JPG character-card import | Complete | Settings imports JSON/PNG/JPG. PNG reads `chara` / `character` / `ccv3` / `chara_card_v2` / `sillytavern_json`; JPG reads web `TimeTavernRoleCard` APP15 metadata and comment fallback. |
| Assistant card | Complete | Separate assistant card section, default name `建立卡助手`, prompt editor/reset, start clears role card. |
| Prompt modes list/create/delete/import/export | Complete | Built-in protection, custom modes, JSON import/export. |
| Prompt mode old fields removal | Complete | Legacy fields decode only; UI hides old main/output fields. |
| Prompt preview | Complete | Local preview for reasoner and compression prompts. |
| Compression state quick edit | Complete | Prompt Lab quick section edits summary and shows compressed turn. |
| Compression profiles / 大模型 | Complete | Normal/image kind picker, expanded image settings on Prompt Lab quick edit, JSON/plain-text save behavior, trigger actions, append terms, module editors, profile import/export. |
| Compression trigger NovelAI image settings | Complete | Trigger image settings, Prompt Lab quick kind picker, and NAI model Picker are native. |
| True API-backed compression calls | Complete | iOS calls DeepSeek for normal plain-text/JSON compression profiles and image Base Prompt profiles, merges normal results, clears image profile state, calls NovelAI, saves album images, appends model-image chat messages, and now follows web `before_reasoner` / `after_assistant` trigger timing with keyword-source and skip-reasoner behavior. |
| Time tracking settings | Complete | Current day/date/period, auto period, keyword lists, keep-time directive, help text, detection tests. |
| Defaults apply/save | Complete | Local defaults save/restore; fallback bundled web defaults; preserves sessions/logs/album/keys. |
| ZIP import/export | Complete by removal | User requested removal; user-facing ZIP flow is absent. |
| Sessions save/load/delete | Complete | Archive tab supports save/load/delete. |
| Sessions rename/archive/resume/detail preview | Complete | Added rename, archive, restore from archive, and preview. |
| NovelAI status/balance | Complete | Native status button via `NovelAIClient.status`. |
| NovelAI model selection | Complete | Six model Picker options and unknown metadata fallback. |
| NovelAI base/negative prompt | Complete | Prompt panel. |
| NovelAI fixed/random snippets | Complete | Add/edit/delete, expansion and metadata decode tests. |
| NovelAI character prompts | Complete | Character captions, negative captions, order move, 5x5 position grid. |
| NovelAI Vibe / Image2Image / Precise Reference | Complete | Reference panel with image pickers and per-image settings. |
| NovelAI output settings | Complete | Size preset/custom size, steps/guidance/cfg/sampler/noise/variety/seed/samples/loop count. |
| NovelAI generate and local album | Complete | Generate saves album; history supports delete and export. |
| NovelAI metadata text import | Complete | Metadata text editor applies settings and fallback model warning. |
| NovelAI metadata image import | Complete | Output panel can pick a PNG and read web-compatible `NovelAIMetadata` / `TimeTavernNovelAIMetadata` plus NovelAI native `Comment` metadata. |
| NovelAI drag/drop target choice | Complete | Desktop drag itself is not applicable on iOS, but the web drop-choice behavior is covered by a mobile PhotosPicker target chooser for Vibe Transfer, Image2Image, Precise Reference, and metadata import. |
| NovelAI cost preview | Complete | Native Output panel estimates Anlas with the same local formula as web: size, steps, samples, Image2Image, Vibe and Precise Reference. |
| NovelAI infinite loop generate / stop loop | Complete | Output panel now has Generate and Loop Generate / Stop Loop; loop count `0` means infinite until stopped, matching web semantics. |
| UI language simple/traditional toggle | Complete | iOS persists `zh-Hant` / `zh-Hans`, uses the web phrase/character conversion table, exposes a Settings picker, syncs active display language at the app root, and wraps static Chinese SwiftUI labels with `uiStatic()`; tests assert no direct Chinese static label initializer remains. |
| Discord bot, slash commands, group/channel features | Not Applicable | Explicitly excluded from iOS plan. |

## Current Highest-Priority Gaps

No remaining high-priority non-Discord feature gaps found in this audit pass.

## Verification This Pass

- Added XCTest coverage for message edit/feedback, session rename/archive/resume/delete, run-time auto 推演 prompt semantics/validation, API-backed normal compression, API-backed image prompt request preparation, before/after compression phase semantics, skip-reasoner timing, NovelAI target-choice image import, full static UI label conversion coverage, UI language conversion/persistence, role cover cropping, safe delete offsets, and expanded Prompt Lab image settings.
- Existing XCTest suite verifies role defaults, Prompt Lab schema, NovelAI payload/settings, time tracking, JSON import/export, and app navigation.
- Latest `test_sim`: 47 passed, 0 failed, 0 warnings.
