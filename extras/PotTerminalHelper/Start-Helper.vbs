' Launch Pot Terminal Helper with no console window
Option Explicit
Dim sh, fso, pwsh, script, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

script = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\PotTerminalHelper\PotTerminalHelper.ps1")

' Prefer real PowerShell 7 path
pwsh = "C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.4.0_x64__8wekyb3d8bbwe\pwsh.exe"
If Not fso.FileExists(pwsh) Then
  pwsh = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe")
End If
If Not fso.FileExists(pwsh) Then
  pwsh = "pwsh.exe"
End If

cmd = """" & pwsh & """ -NoLogo -NoProfile -STA -WindowStyle Hidden -File """ & script & """"
' 0 = hidden window, False = do not wait
sh.Run cmd, 0, False
