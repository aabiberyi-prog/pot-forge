Pot Forge Selection Helper (headless)
=====================================

No separate tray icon. Use Pot Forge's tray icon only.

Behavior:
  - Alt+Q: translate current selection (any app)
  - Windows Terminal: Shift+drag select also auto-translates

Lifecycle:
  - Started with Pot Forge (after rebuild with selection_helper)
  - Or: wscript.exe "%LOCALAPPDATA%\PotTerminalHelper\Start-Helper.vbs"
  - Log: %LOCALAPPDATA%\PotTerminalHelper\helper.log

Target: D:\Pot Forge\Pot Forge.exe  port 60828
