# Time Tavern iOS

Standalone SwiftUI iOS app for Time Tavern.

- App: `Time Tavern`
- Bundle ID: `com.wingfungwong.TimeTavern`
- Minimum iOS: 17.0
- Architecture: single native app, direct DeepSeek and NovelAI API calls
- Storage: SwiftData for local state, Keychain for API keys
- Import/export: standalone JSON flows for role cards, prompt modes, and presets

Implemented native areas:

- Chat-first mobile UI with streaming DeepSeek generation, cancel, reload, replay, run-time auto 推演, model content viewer, AI logs.
- Role card manager with custom sections, multiple openings, Lorebooks, prompt mode selection.
- Prompt Lab with modes, prompt rules, compression profiles, trigger actions, append terms, prompt preview.
- Sessions archive with save/load/delete and branch backups before replay/regeneration.
- NovelAI image studio with status test, image generation, and local album.
- Settings for DeepSeek/NAI keys, model/base URLs, user profile, time tracking, JSON import/export, and defaults.

Open `TimeTavern.xcodeproj` in Xcode or build with:

```bash
xcodebuild -project TimeTavern.xcodeproj -scheme TimeTavern -destination 'platform=iOS Simulator,name=iPhone 16' build
```
