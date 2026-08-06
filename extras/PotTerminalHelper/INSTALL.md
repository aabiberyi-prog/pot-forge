# Pot Terminal / Global Selection Helper

Install to the user machine:

```powershell
$dest = Join-Path $env:LOCALAPPDATA "PotTerminalHelper"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Force "$PSScriptRoot\*" $dest -Exclude "*.md"
wscript.exe (Join-Path $dest "Start-Helper.vbs")
```

**Alt+Q** (global): translate the current selection in any app (Chrome inputs, etc.).

**Shift-drag** (Windows Terminal only): auto-translate on mouse release.

Target app: `D:\Pot Forge\Pot Forge.exe` HTTP `127.0.0.1:60828`
