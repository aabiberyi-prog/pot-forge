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

## Features (this fork)

1. **Window opacity (shell only)**
   - Settings → General → 背景透明度；标题栏紧凑滑条
   - Source/target text panels always solid
2. **Compact UI (default)**
   - `ui_density=compact`, window ~300×280, font 14
   - Language switcher hidden by default (`hide_language=true`)
   - Action buttons hidden until card hover
3. **Built-in Edge TTS**（少御向）
   - ZH Xiaoxiao / EN Ava, rate `-20%`, pitch `+10Hz`
4. **Import from official Pot**
   - Settings → Backup → 从官方 Pot 导入

## Develop

```powershell
cd C:\Users\AABIBER\Documents\pot-forge
git checkout master   # or feature/forge-core

# Node 18+, pnpm 8+, Rust stable, VS Build Tools, WebView2
pnpm install
pnpm tauri dev
pnpm tauri build
```

Installer output (after build):

```text
src-tauri\target\release\bundle\nsis\
src-tauri\target\release\bundle\msi\
```

## Migrate config

**In-app (recommended):** Backup → 一键导入  

**Manual:** copy keys from official `config.json` into Forge config, then set:

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

Upstream copyright remains with pot-app contributors. This fork adds opacity control, Edge TTS, and official-config import for secondary development.
