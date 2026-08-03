# Pot Forge

Fork of [pot-app/pot-desktop](https://github.com/pot-app/pot-desktop) by **aabiberyi-prog**.

License: **GPL-3.0** (same as upstream).

## Branding

| | Official Pot | Pot Forge |
|--|--------------|-----------|
| Identifier | `com.pot-app.desktop` | `com.aabiber.pot-forge` |
| Config dir | `%AppData%\com.pot-app.desktop` | `%AppData%\com.aabiber.pot-forge` |
| Product name | pot | Pot Forge |

Configs do **not** conflict with the installed official Pot.

## Forge features (this branch)

1. **Window opacity slider** — Settings → General → 窗口不透明度 (15%–100%)
2. **Built-in Edge TTS** — Service → Speech → Edge TTS（少御向）
   - Default ZH: `zh-CN-XiaoxiaoNeural`
   - Default EN: `en-US-AvaNeural`
   - Rate `+0%`, pitch `+8Hz`
   - Requires local `edge-tts` CLI (`pip install edge-tts`) or set env `EDGE_TTS_PATH`

## Develop

```bash
# Requirements: Node 18+, pnpm 8+, Rust stable, VS Build Tools (Windows), WebView2
pnpm install
pnpm tauri dev
pnpm tauri build
```

## Migrate config from official Pot

Copy selected keys from:

`%AppData%\com.pot-app.desktop\config.json`

into:

`%AppData%\com.aabiber.pot-forge\config.json`

Suggested keys: `openai`, `translate_*`, `hotkey_*`, `app_language`, `app_font_size`.

Then set:

```json
"tts_service_list": ["edge_tts"],
"window_opacity": 0.92
```

## Sync upstream

```bash
git fetch upstream
git merge upstream/master
```

## About

Upstream copyright remains with pot-app contributors. This fork adds opacity control and Edge TTS integration for secondary development.
