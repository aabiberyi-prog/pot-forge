# Pot Forge Selection Helper (headless — no tray icon; lives under Pot Forge lifecycle)
# Alt+Q (global hotkey): translate selected text
# Terminal Shift+drag: auto-translate on mouse release

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$helperDir = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path $env:LOCALAPPDATA 'PotTerminalHelper' }
$logPath = Join-Path $helperDir 'helper.log'
$potPort = 60828
$debounceMs = 450
$minSelectMs = 100

function Write-HelperLog([string]$Message) {
    try {
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" | Add-Content -LiteralPath $logPath -Encoding utf8
    } catch {}
}

$cs = @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class PotHelperForm : Form {
    public const int HOTKEY_ALTQ = 9001;
    public const int MOD_ALT = 0x0001;
    public const int MOD_NOREPEAT = 0x4000;
    public const int WM_HOTKEY = 0x0312;
    public const int VK_Q = 0x51;
    public const uint KEYEVENTF_KEYUP = 0x0002;

    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, int fsModifiers, int vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vKey);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);

    public event EventHandler AltQPressed;
    public bool HotKeyOk = false;

    public PotHelperForm() {
        this.ShowInTaskbar = false;
        this.FormBorderStyle = FormBorderStyle.FixedToolWindow;
        this.Opacity = 0;
        this.Size = new System.Drawing.Size(1, 1);
        this.StartPosition = FormStartPosition.Manual;
        this.Location = new System.Drawing.Point(-32000, -32000);
        this.Text = "PotTerminalHelper";
    }

    protected override void OnHandleCreated(EventArgs e) {
        base.OnHandleCreated(e);
        HotKeyOk = RegisterHotKey(this.Handle, HOTKEY_ALTQ, MOD_ALT | MOD_NOREPEAT, VK_Q);
        if (!HotKeyOk) {
            HotKeyOk = RegisterHotKey(this.Handle, HOTKEY_ALTQ, MOD_ALT, VK_Q);
        }
    }

    protected override void OnFormClosed(FormClosedEventArgs e) {
        try { UnregisterHotKey(this.Handle, HOTKEY_ALTQ); } catch {}
        base.OnFormClosed(e);
    }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && m.WParam.ToInt32() == HOTKEY_ALTQ) {
            var h = AltQPressed;
            if (h != null) h(this, EventArgs.Empty);
            return;
        }
        base.WndProc(ref m);
    }

    public static void KeyEvent(byte vk, bool up) {
        uint flags = up ? KEYEVENTF_KEYUP : 0;
        keybd_event(vk, 0, flags, UIntPtr.Zero);
    }

    public static bool IsDown(int vk) {
        return (GetAsyncKeyState(vk) & 0x8000) != 0;
    }
}
"@

try {
    Add-Type -TypeDefinition $cs -ReferencedAssemblies System.Windows.Forms, System.Drawing -ErrorAction Stop
} catch {
    if ($_.Exception.Message -notmatch 'already exists|already been defined') {
        Write-HelperLog "Add-Type failed: $($_.Exception.Message)"
        throw
    }
}

$script:lastTriggerUtc = [datetime]::MinValue
$script:shiftSelectActive = $false
$script:selectStartedUtc = [datetime]::MinValue
$script:prevLButtonDown = $false
$script:prevAltQDown = $false
$script:busy = $false
$script:hotkeyRegistered = $false

function Get-PotExePath {
    foreach ($c in @('D:\Pot Forge\Pot Forge.exe', 'C:\Program Files\Pot Forge\Pot Forge.exe')) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Test-PotServer {
    if (-not (Get-Process -Name 'Pot Forge' -ErrorAction SilentlyContinue)) { return $false }
    try {
        $client = [Net.Sockets.TcpClient]::new()
        $t = $client.ConnectAsync('127.0.0.1', $potPort)
        $ok = $t.Wait(400) -and $client.Connected
        $client.Dispose()
        return $ok
    } catch { return $false }
}

function Ensure-PotServer {
    if (Test-PotServer) { return $true }
    $exe = Get-PotExePath
    if (-not $exe) { Write-HelperLog 'Pot Forge.exe not found'; return $false }
    try {
        Start-Process -FilePath $exe | Out-Null
        Write-HelperLog "Started Pot: $exe"
        for ($i = 0; $i -lt 40; $i++) {
            Start-Sleep -Milliseconds 250
            if (Test-PotServer) { return $true }
        }
    } catch {
        Write-HelperLog "Start pot failed: $($_.Exception.Message)"
    }
    return $false
}

function Get-ForegroundProcessName {
    try {
        $hwnd = [PotHelperForm]::GetForegroundWindow()
        $fgPid = [uint32]0
        [void][PotHelperForm]::GetWindowThreadProcessId($hwnd, [ref]$fgPid)
        if ($fgPid -eq 0) { return '' }
        return (Get-Process -Id $fgPid -ErrorAction Stop).ProcessName
    } catch { return '' }
}

function Test-IsTerminalHost([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return @('windowsterminal', 'windowsterminalpreview', 'openconsole', 'wt') -contains $Name.ToLowerInvariant()
}

function Release-Modifiers {
    foreach ($vk in @(0x12, 0x11, 0x10, 0x5B, 0x5C)) {
        [PotHelperForm]::KeyEvent([byte]$vk, $true)
    }
    Start-Sleep -Milliseconds 20
}

function Get-ClipboardTextSafe {
    for ($i = 0; $i -lt 15; $i++) {
        try {
            if ([Windows.Forms.Clipboard]::ContainsText()) {
                return [Windows.Forms.Clipboard]::GetText()
            }
        } catch {}
        Start-Sleep -Milliseconds 25
    }
    return ''
}

function Wait-ClipChange([uint32]$Before, [int]$Ms = 900) {
    $end = [datetime]::UtcNow.AddMilliseconds($Ms)
    while ([datetime]::UtcNow -lt $end) {
        if ([PotHelperForm]::GetClipboardSequenceNumber() -ne $Before) { return $true }
        Start-Sleep -Milliseconds 20
    }
    return $false
}

function Send-CtrlC {
    Release-Modifiers
    [PotHelperForm]::KeyEvent(0x11, $false)
    Start-Sleep -Milliseconds 15
    [PotHelperForm]::KeyEvent(0x43, $false)
    Start-Sleep -Milliseconds 45
    [PotHelperForm]::KeyEvent(0x43, $true)
    [PotHelperForm]::KeyEvent(0x11, $true)
}

function Send-CtrlShiftC {
    Release-Modifiers
    [PotHelperForm]::KeyEvent(0x11, $false)
    [PotHelperForm]::KeyEvent(0x10, $false)
    [PotHelperForm]::KeyEvent(0x43, $false)
    Start-Sleep -Milliseconds 45
    [PotHelperForm]::KeyEvent(0x43, $true)
    [PotHelperForm]::KeyEvent(0x10, $true)
    [PotHelperForm]::KeyEvent(0x11, $true)
}

function Send-CtrlInsert {
    Release-Modifiers
    [PotHelperForm]::KeyEvent(0x11, $false)
    [PotHelperForm]::KeyEvent(0x2D, $false)
    Start-Sleep -Milliseconds 40
    [PotHelperForm]::KeyEvent(0x2D, $true)
    [PotHelperForm]::KeyEvent(0x11, $true)
}

function Get-SelectionText([bool]$Term) {
    $before = [PotHelperForm]::GetClipboardSequenceNumber()
    Start-Sleep -Milliseconds 35
    if ([PotHelperForm]::GetClipboardSequenceNumber() -ne $before) {
        $t = Get-ClipboardTextSafe
        if (-not [string]::IsNullOrWhiteSpace($t)) { return $t.Trim() }
    }

    $acts = if ($Term) { @({ Send-CtrlShiftC }, { Send-CtrlC }) } else { @({ Send-CtrlC }, { Send-CtrlInsert }, { Send-CtrlShiftC }) }
    foreach ($a in $acts) {
        $b = [PotHelperForm]::GetClipboardSequenceNumber()
        & $a
        if (Wait-ClipChange $b 900) {
            Start-Sleep -Milliseconds 40
            $text = Get-ClipboardTextSafe
            if (-not [string]::IsNullOrWhiteSpace($text)) { return $text.Trim() }
        }
    }
    return ''
}

function Show-PotWindow {
    foreach ($p in @(Get-Process -Name 'Pot Forge' -ErrorAction SilentlyContinue)) {
        $h = $p.MainWindowHandle
        if ($h -ne 0) {
            if ([PotHelperForm]::IsIconic([IntPtr]$h)) { [void][PotHelperForm]::ShowWindow([IntPtr]$h, 9) }
            else { [void][PotHelperForm]::ShowWindow([IntPtr]$h, 5) }
            [void][PotHelperForm]::SetForegroundWindow([IntPtr]$h)
        }
    }
}

function Invoke-Translate([string]$Text, [string]$Reason) {
    if ([string]::IsNullOrWhiteSpace($Text)) {
        Write-HelperLog "Skip ($Reason): empty fg=$(Get-ForegroundProcessName)"
        return
    }
    $now = [datetime]::UtcNow
    if (($now - $script:lastTriggerUtc).TotalMilliseconds -lt $debounceMs) {
        Write-HelperLog "Skip ($Reason): debounce"
        return
    }
    if (-not (Ensure-PotServer)) {
        Write-HelperLog "Abort ($Reason): pot not ready"
        return
    }
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers[[System.Net.HttpRequestHeader]::ContentType] = 'text/plain; charset=utf-8'
        $null = $wc.UploadData("http://127.0.0.1:$potPort/translate", 'POST', [Text.Encoding]::UTF8.GetBytes($Text))
        $wc.Dispose()
        $script:lastTriggerUtc = $now
        Start-Sleep -Milliseconds 80
        Show-PotWindow
        $pv = ($Text.Substring(0, [Math]::Min(50, $Text.Length)) -replace '[\r\n]+', ' ')
        Write-HelperLog "OK ($Reason) chars=$($Text.Length) fg=$(Get-ForegroundProcessName) preview=$pv"
    } catch {
        Write-HelperLog "Fail ($Reason): $($_.Exception.Message)"
    }
}

function Invoke-Capture([string]$Reason, [bool]$Term) {
    if ($script:busy) { Write-HelperLog "Skip ($Reason): busy"; return }
    $script:busy = $true
    try {
        $text = Get-SelectionText -Term $Term
        Write-HelperLog "Capture ($Reason) len=$($text.Length) fg=$(Get-ForegroundProcessName) term=$Term"
        if ([string]::IsNullOrWhiteSpace($text)) {
            Write-HelperLog "No selection ($Reason). Highlight text, then Alt+Q again."
            return
        }
        Invoke-Translate -Text $text -Reason $Reason
    } catch {
        Write-HelperLog "Capture error: $($_.Exception.Message)"
    } finally {
        $script:busy = $false
    }
}

function Invoke-AltQAction([string]$Source) {
    Write-HelperLog "Alt+Q action ($Source)"
    Release-Modifiers
    Start-Sleep -Milliseconds 25
    $proc = Get-ForegroundProcessName
    Invoke-Capture -Reason 'altq' -Term (Test-IsTerminalHost $proc)
}

function Update-ShiftPoll {
    try {
        $proc = Get-ForegroundProcessName
        $inTerm = Test-IsTerminalHost $proc
        $shift = [PotHelperForm]::IsDown(0x10)
        $lbtn = [PotHelperForm]::IsDown(0x01)
        $alt = [PotHelperForm]::IsDown(0x12)
        $q = [PotHelperForm]::IsDown(0x51)

        if (-not $script:hotkeyRegistered) {
            if ($alt -and $q -and -not $script:prevAltQDown) {
                Invoke-AltQAction -Source 'poll-fallback'
            }
            $script:prevAltQDown = ($alt -and $q)
        }

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
                    Invoke-Capture -Reason 'shift-select' -Term $true
                }
            }
            $script:shiftSelectActive = $false
        }
        if (-not $inTerm) { $script:shiftSelectActive = $false }
        $script:prevLButtonDown = $lbtn
    } catch {
        Write-HelperLog "Poll error: $($_.Exception.Message)"
    }
}

# ---- single instance ----
$mutex = [Threading.Mutex]::new($false, 'Local\PotTerminalHelper')
$owned = $false
try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) {
    Write-HelperLog 'Already running; exit.'
    exit 0
}

$form = New-Object PotHelperForm

$form.add_AltQPressed({
        Invoke-AltQAction -Source 'RegisterHotKey'
    })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 50
$timer.Add_Tick({ Update-ShiftPoll })

$hb = New-Object System.Windows.Forms.Timer
$hb.Interval = 600000
$hb.Add_Tick({ Write-HelperLog "Heartbeat potReady=$(Test-PotServer) fg=$(Get-ForegroundProcessName)" })

$form.Add_Shown({
        $form.Hide()
        $timer.Start()
        $hb.Start()
        $script:hotkeyRegistered = [bool]$form.HotKeyOk
        $ready = Ensure-PotServer
        Write-HelperLog "Helper READY headless=1 hotkeyAltQ=$($form.HotKeyOk) term-shift=ON potReady=$ready pid=$PID"
    })

$form.Add_FormClosed({
        try { $timer.Stop(); $timer.Dispose() } catch {}
        try { $hb.Stop(); $hb.Dispose() } catch {}
        try { $mutex.ReleaseMutex(); $mutex.Dispose() } catch {}
        Write-HelperLog 'Helper stopped.'
    })

Write-HelperLog "Booting headless helper from $helperDir"
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)
