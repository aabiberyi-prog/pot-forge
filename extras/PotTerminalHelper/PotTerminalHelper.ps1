# Pot Forge Selection Helper
# Primary global shortcut: Alt+Q → copy current selection → auto translate (any app)
#   - Chrome / inputs / docs: Ctrl+C
#   - Windows Terminal: Ctrl+Shift+C
# Bonus (Terminal only): Shift + drag-select → on release → auto translate
# Does NOT open new console/terminal windows.

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class PotNative
{
    public const int VK_SHIFT = 0x10;
    public const int VK_LBUTTON = 0x01;
    public const int VK_MENU = 0x12;
    public const int VK_Q = 0x51;
    public const uint KEYEVENTF_KEYUP = 0x0002;

    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint id);
    [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
"@

$helperDir = Split-Path -Parent $PSCommandPath
$logPath = Join-Path $helperDir 'helper.log'
$potPort = 60828
$pollMs = 50
$debounceMs = 400
$minSelectMs = 100
# Processes where shift-select auto-translate is skipped (self / noise)
$skipFgNames = @(
    'pot forge', 'pot-forge', 'pot',
    'potterminalhelper'
)

$script:lastTriggerUtc = [datetime]::MinValue
$script:shiftSelectActive = $false
$script:selectStartedUtc = [datetime]::MinValue
$script:selectWasTerminal = $false
$script:prevLButtonDown = $false
$script:prevQDown = $false
$script:busy = $false

function Write-HelperLog([string]$Message) {
    try {
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Add-Content -LiteralPath $logPath -Encoding utf8
    } catch {}
}

function Get-PotExePath {
    foreach ($c in @(
            'D:\Pot Forge\Pot Forge.exe',
            'C:\Program Files\Pot Forge\Pot Forge.exe'
        )) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Test-PotServer {
    # Prefer process check — avoids false "down" while port is busy
    if (Get-Process -Name 'Pot Forge' -ErrorAction SilentlyContinue) {
        $client = $null
        try {
            $client = [Net.Sockets.TcpClient]::new()
            $t = $client.ConnectAsync('127.0.0.1', $potPort)
            if ($t.Wait(300) -and $client.Connected) { return $true }
        } catch {}
        finally { if ($client) { $client.Dispose() } }
    }
    return $false
}

function Ensure-PotServer {
    if (Test-PotServer) { return $true }
    $exe = Get-PotExePath
    if (-not $exe) {
        Write-HelperLog 'Pot Forge.exe not found on D: or Program Files.'
        return $false
    }
    if (Get-Process -Name 'Pot Forge' -ErrorAction SilentlyContinue) {
        # Process exists but port not ready yet
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Milliseconds 200
            if (Test-PotServer) { return $true }
        }
        return $false
    }
    try {
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $exe
        $psi.UseShellExecute = $true
        $psi.WindowStyle = [Diagnostics.ProcessWindowStyle]::Normal
        [Diagnostics.Process]::Start($psi) | Out-Null
        Write-HelperLog "Started Pot Forge: $exe"
        for ($i = 0; $i -lt 40; $i++) {
            Start-Sleep -Milliseconds 250
            if (Test-PotServer) { return $true }
        }
        Write-HelperLog 'Pot Forge started but :60828 not ready.'
    } catch {
        Write-HelperLog "Start Pot Forge failed: $($_.Exception.Message)"
    }
    return $false
}

function Test-IsTerminalHost([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    $n = $Name.ToLowerInvariant()
    # WindowsTerminal = frame; OpenConsole = tab host (often the focused process)
    return @('windowsterminal', 'windowsterminalpreview', 'openconsole', 'wt') -contains $n
}

function Get-ForegroundProcessName {
    $hwnd = [PotNative]::GetForegroundWindow()
    $fgId = [uint32]0
    [void][PotNative]::GetWindowThreadProcessId($hwnd, [ref]$fgId)
    if ($fgId -eq 0) { return '' }
    try { return (Get-Process -Id $fgId -ErrorAction Stop).ProcessName } catch { return '' }
}

function Test-KeyDown([int]$Vk) {
    return ([PotNative]::GetAsyncKeyState($Vk) -band 0x8000) -ne 0
}

function Send-Key([byte]$vk, [bool]$up = $false) {
    $flags = if ($up) { [PotNative]::KEYEVENTF_KEYUP } else { [uint32]0 }
    [PotNative]::keybd_event($vk, 0, $flags, [UIntPtr]::Zero)
}

function Release-Modifiers {
    # Prevent Alt/Ctrl/Shift still held (from Alt+Q) from breaking Ctrl+C in browsers/inputs
    foreach ($vk in @(0x12, 0x11, 0x10, 0x5B, 0x5C)) { # Alt, Ctrl, Shift, LWin, RWin
        Send-Key $vk $true
    }
    Start-Sleep -Milliseconds 30
}

function Send-TerminalCopy {
    # Ctrl+Shift+C — Windows Terminal "copy selection"
    # Use keybd_event only (broken SendInput struct was spawning rogue keystrokes / new tabs)
    Release-Modifiers
    Send-Key 0x11 $false
    Send-Key 0x10 $false
    Send-Key 0x43 $false
    Start-Sleep -Milliseconds 40
    Send-Key 0x43 $true
    Send-Key 0x10 $true
    Send-Key 0x11 $true
}

function Send-StandardCopy {
    # Ctrl+C — works for most apps including Chrome omnibox / <input> / contenteditable
    Release-Modifiers
    Send-Key 0x11 $false   # Ctrl down
    Start-Sleep -Milliseconds 20
    Send-Key 0x43 $false   # C down
    Start-Sleep -Milliseconds 40
    Send-Key 0x43 $true    # C up
    Send-Key 0x11 $true    # Ctrl up
}

function Wait-ClipboardChange([uint32]$Before, [int]$TimeoutMs = 1000) {
    $deadline = [datetime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([datetime]::UtcNow -lt $deadline) {
        if ([PotNative]::GetClipboardSequenceNumber() -ne $Before) { return $true }
        Start-Sleep -Milliseconds 25
    }
    return $false
}

function Get-SelectionText([string]$Mode = 'auto') {
    # Mode: auto | terminal | standard
    $prevText = ''
    try {
        if ([Windows.Forms.Clipboard]::ContainsText()) {
            $prevText = [Windows.Forms.Clipboard]::GetText()
        }
    } catch {}

    $before = [PotNative]::GetClipboardSequenceNumber()

    # If app already pushed selection to clipboard (copy-on-select), use it
    Start-Sleep -Milliseconds 40
    if ([PotNative]::GetClipboardSequenceNumber() -ne $before) {
        $t = Get-ClipboardTextSafe
        if (-not [string]::IsNullOrWhiteSpace($t) -and $t -ne $prevText) {
            return $t.Trim()
        }
    }

    $proc = Get-ForegroundProcessName
    $inTerm = Test-IsTerminalHost $proc
    $useTerminalCopy = ($Mode -eq 'terminal') -or ($Mode -eq 'auto' -and $inTerm)

    $before2 = [PotNative]::GetClipboardSequenceNumber()
    if ($useTerminalCopy) {
        Send-TerminalCopy
    } else {
        Send-StandardCopy
    }

    if (-not (Wait-ClipboardChange $before2 1200)) {
        # Retry the other copy method once (Chrome inputs sometimes ignore first attempt)
        $before3 = [PotNative]::GetClipboardSequenceNumber()
        if ($useTerminalCopy) { Send-StandardCopy } else { Send-TerminalCopy }
        if (-not (Wait-ClipboardChange $before3 800)) {
            return ''
        }
    }

    # Wait for clipboard to settle
    $last = [PotNative]::GetClipboardSequenceNumber()
    $stable = 0
    for ($i = 0; $i -lt 24 -and $stable -lt 4; $i++) {
        Start-Sleep -Milliseconds 20
        $cur = [PotNative]::GetClipboardSequenceNumber()
        if ($cur -eq $last) { $stable++ } else { $last = $cur; $stable = 0 }
    }

    $text = Get-ClipboardTextSafe
    if ([string]::IsNullOrWhiteSpace($text)) { return '' }
    return $text.Trim()
}

function Get-ClipboardTextSafe {
    for ($i = 0; $i -lt 12; $i++) {
        try {
            if ([Windows.Forms.Clipboard]::ContainsText()) {
                return [Windows.Forms.Clipboard]::GetText()
            }
        } catch {}
        Start-Sleep -Milliseconds 30
    }
    return ''
}

function Get-TerminalSelectionText {
    return Get-SelectionText -Mode 'terminal'
}

function Show-PotForgeWindow {
    # Bring Pot Forge windows (translate popup) to the front
    $procs = @(Get-Process -Name 'Pot Forge' -ErrorAction SilentlyContinue)
    foreach ($proc in $procs) {
        $h = $proc.MainWindowHandle
        if ($h -ne [IntPtr]::Zero -and $h -ne 0) {
            if ([PotNative]::IsIconic([IntPtr]$h)) {
                [void][PotNative]::ShowWindow([IntPtr]$h, 9) # SW_RESTORE
            } else {
                [void][PotNative]::ShowWindow([IntPtr]$h, 5) # SW_SHOW
            }
            [void][PotNative]::SetForegroundWindow([IntPtr]$h)
        }
    }
}

function Invoke-Translate([string]$Text, [string]$Reason) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-HelperLog "Skip ($Reason): empty selection."
        return
    }
    # Ignore single-char accidents only
    if ($Text.Length -lt 2 -and $Reason -like 'shift*') {
        Write-HelperLog "Skip ($Reason): too short ($($Text.Length))."
        return
    }
    $now = [datetime]::UtcNow
    if (($now - $script:lastTriggerUtc).TotalMilliseconds -lt $debounceMs) {
        Write-HelperLog "Skip ($Reason): debounce."
        return
    }
    if (-not (Ensure-PotServer)) {
        Write-HelperLog "Abort ($Reason): Pot Forge not ready."
        return
    }
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:$potPort/translate" -Method Post `
            -ContentType 'text/plain; charset=utf-8' -Body $Text -TimeoutSec 20 | Out-Null
        $script:lastTriggerUtc = $now
        Start-Sleep -Milliseconds 120
        Show-PotForgeWindow
        Write-HelperLog "OK ($Reason) chars=$($Text.Length) preview=$($Text.Substring(0, [Math]::Min(40, $Text.Length)))"
    } catch {
        Write-HelperLog "Fail ($Reason): $($_.Exception.Message)"
    }
}

function Invoke-AutoCapture([string]$Reason, [string]$Mode = 'auto') {
    if ($script:busy) { return }
    $script:busy = $true
    try {
        $text = Get-SelectionText -Mode $Mode
        Write-HelperLog "Capture ($Reason) len=$($text.Length) fg=$(Get-ForegroundProcessName) mode=$Mode"
        if ([string]::IsNullOrWhiteSpace($text)) {
            Write-HelperLog "No selection text ($Reason) — select text in the field, then Alt+Q again."
            return
        }
        Invoke-Translate -Text $text -Reason $Reason
    } catch {
        Write-HelperLog "Auto error: $($_.Exception.Message)"
    } finally {
        $script:busy = $false
    }
}

function Invoke-AutoFromTerminal([string]$Reason) {
    Invoke-AutoCapture -Reason $Reason -Mode 'terminal'
}

function Test-SkipForeground([string]$ProcName) {
    if ([string]::IsNullOrWhiteSpace($ProcName)) { return $false }
    $n = $ProcName.ToLowerInvariant()
    foreach ($s in $skipFgNames) {
        if ($n -eq $s -or $n.Contains($s)) { return $true }
    }
    return $false
}

function Update-InputState {
    try {
        $proc = Get-ForegroundProcessName
        $inTerm = Test-IsTerminalHost $proc
        $shift = Test-KeyDown ([PotNative]::VK_SHIFT)
        $lbtn = Test-KeyDown ([PotNative]::VK_LBUTTON)
        $alt = Test-KeyDown ([PotNative]::VK_MENU)
        $q = Test-KeyDown ([PotNative]::VK_Q)

        # ---- Primary global: Alt+Q → translate selected text (any app) ----
        if ($alt -and $q -and -not $script:prevQDown) {
            if (-not (Test-SkipForeground $proc)) {
                # Wait until Alt/Q released so Ctrl+C is not blocked
                $waited = 0
                while ((Test-KeyDown ([PotNative]::VK_MENU) -or Test-KeyDown ([PotNative]::VK_Q)) -and $waited -lt 40) {
                    Start-Sleep -Milliseconds 25
                    $waited++
                }
                Release-Modifiers
                Start-Sleep -Milliseconds 50
                if ($inTerm) {
                    Invoke-AutoCapture -Reason 'altq' -Mode 'terminal'
                } else {
                    Invoke-AutoCapture -Reason 'altq' -Mode 'standard'
                }
            }
        }
        $script:prevQDown = $q

        # ---- Terminal only: Shift + drag-select auto (unchanged habit in WT) ----
        if ($inTerm -and $shift -and $lbtn) {
            if (-not $script:shiftSelectActive) {
                $script:shiftSelectActive = $true
                $script:selectStartedUtc = [datetime]::UtcNow
            }
        }

        if ($script:prevLButtonDown -and -not $lbtn) {
            if ($script:shiftSelectActive -and $inTerm) {
                $held = ([datetime]::UtcNow - $script:selectStartedUtc).TotalMilliseconds
                if ($held -ge $minSelectMs) {
                    Start-Sleep -Milliseconds 80
                    Invoke-AutoCapture -Reason 'shift-select' -Mode 'terminal'
                }
            }
            $script:shiftSelectActive = $false
        }

        if (-not $inTerm) { $script:shiftSelectActive = $false }
        $script:prevLButtonDown = $lbtn
    } catch {
        Write-HelperLog "Tick error: $($_.Exception.Message)"
    }
}

# ---- main ----
$mutex = $null
$timer = $null
$form = $null

try {
    $mutex = [Threading.Mutex]::new($false, 'Local\PotTerminalHelper')
    $owned = $false
    try { $owned = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] {
        $owned = $true
        Write-HelperLog 'Took abandoned mutex.'
    }
    if (-not $owned) {
        Write-HelperLog 'Already running; exit.'
        exit 0
    }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'PotTerminalHelper'
    $form.ShowInTaskbar = $false
    $form.FormBorderStyle = 'FixedToolWindow'
    $form.Opacity = 0
    $form.ShowIcon = $false
    $form.Size = New-Object System.Drawing.Size(0, 0)
    $form.Location = New-Object System.Drawing.Point(-10000, -10000)
    $form.StartPosition = 'Manual'
    $form.Add_Shown({ $form.Hide(); $form.Visible = $false })

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $pollMs
    $timer.Add_Tick({ Update-InputState })
    $timer.Start()

    $ready = Ensure-PotServer
    Write-HelperLog "Helper READY altq-global=ON term-shift-select=ON potReady=$ready exe=$(Get-PotExePath)"

    [System.Windows.Forms.Application]::Run($form)
} catch {
    Write-HelperLog "Fatal: $($_.Exception.Message)"
    exit 1
} finally {
    try { if ($timer) { $timer.Stop(); $timer.Dispose() } } catch {}
    try { if ($form) { $form.Dispose() } } catch {}
    if ($mutex) {
        try { $mutex.ReleaseMutex() } catch {}
        try { $mutex.Dispose() } catch {}
    }
    Write-HelperLog 'Helper stopped.'
}
