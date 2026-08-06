Pot Forge Selection Helper
==========================

Global shortcut (primary):
  1. Select text (Chrome search box, page, input, Word, etc.)
  2. Press Alt+Q
  3. Pot auto-translates the selection

Windows Terminal bonus:
  Shift + drag-select → release mouse → auto translate
  (Alt+Q also works in Terminal)

Does not:
  - Open new Terminal windows (start via Start-Helper.vbs)
  - Open OCR when selection is empty
  - Trigger when Pot Forge itself is focused

Target: D:\Pot Forge\Pot Forge.exe  port 60828

Start:
  wscript.exe "%LOCALAPPDATA%\PotTerminalHelper\Start-Helper.vbs"

Log:
  %LOCALAPPDATA%\PotTerminalHelper\helper.log
