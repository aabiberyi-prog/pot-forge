Option Explicit
Dim sh, fso, ps, script, cmd, logf, ts
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
script = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\PotTerminalHelper\PotTerminalHelper.ps1")
logf = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\PotTerminalHelper\helper.log")
ps = sh.ExpandEnvironmentStrings("%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe")
cmd = """" & ps & """ -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & script & """"
On Error Resume Next
Set ts = fso.OpenTextFile(logf, 8, True)
ts.WriteLine "[" & Year(Now) & "-" & Right("0"&Month(Now),2) & "-" & Right("0"&Day(Now),2) & " " & Right("0"&Hour(Now),2) & ":" & Right("0"&Minute(Now),2) & ":" & Right("0"&Second(Now),2) & "] VBS launch"
ts.Close
On Error GoTo 0
sh.Run cmd, 0, False
