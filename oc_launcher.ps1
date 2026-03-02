param([string]$ScriptDir)

$ScriptDir = $ScriptDir.TrimEnd('\', '/')
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# -- Set window font to Consolas 16pt via Win32 API
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class ConsoleHelper {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CONSOLE_FONT_INFOEX {
        public uint cbSize;
        public uint nFont;
        public COORD dwFontSize;
        public int FontFamily;
        public int FontWeight;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string FaceName;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct COORD { public short X; public short Y; }
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern bool SetCurrentConsoleFontEx(IntPtr h, bool b, ref CONSOLE_FONT_INFOEX c);
    public static void SetFont(string name, short size) {
        var h = GetStdHandle(-11);
        var c = new CONSOLE_FONT_INFOEX();
        c.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(c);
        c.FaceName = name; c.dwFontSize = new COORD { X = 0, Y = size }; c.FontWeight = 400;
        SetCurrentConsoleFontEx(h, false, ref c);
    }
}
'@ -ErrorAction SilentlyContinue
try { [ConsoleHelper]::SetFont("Consolas", 16) } catch {}

# -- Window setup
$W = 70  # inner box width (changes per page)
$MaxCols = 512
$MaxRows = 512

function Set-WindowSize([int]$cols, [int]$rows) {
    # Cap at 512x512
    $cols = [math]::Min($cols, $MaxCols)
    $rows = [math]::Min($rows, $MaxRows)
    # Must be at least 20x10
    $cols = [math]::Max($cols, 20)
    $rows = [math]::Max($rows, 10)
    try {
        # Always set buffer >= window to avoid errors
        $curBufW = [Console]::BufferWidth
        $curBufH = [Console]::BufferHeight
        if ($cols -gt $curBufW)  { [Console]::BufferWidth  = $cols }
        if ($rows -gt $curBufH)  { [Console]::BufferHeight = $rows }
        [Console]::WindowWidth  = $cols
        [Console]::WindowHeight = $rows
        if ($cols -lt $curBufW)  { [Console]::BufferWidth  = $cols }
    } catch {}
}

try {
    [Console]::BufferHeight = 9999
    $host.UI.RawUI.WindowTitle = "OpenConnection v1.0.0"
    Set-WindowSize ($W + 6) 40
} catch {}

# -- Box chars
$bTL=[char]0x256D; $bTR=[char]0x256E; $bBL=[char]0x2570; $bBR=[char]0x256F
$bV=[char]0x2502; $bH=[char]0x2500; $bML=[char]0x251C; $bMR=[char]0x2524

# -- Paths
$ConfigFile  = [IO.Path]::Combine($ScriptDir, "config.ini")
$LogDir      = [IO.Path]::Combine($ScriptDir, "logs")
$ChromePath  = [IO.Path]::Combine($ScriptDir, "Chromium", "chrome-win", "chrome.exe")
$UserDataDir = [IO.Path]::Combine($ScriptDir, "Chromium", "chrome-win", "User_Data")
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

# -- Config
$Cfg = @{ URL = "https://www.google.com"; W = "800"; H = "600" }
function Load-Config {
    if (Test-Path $ConfigFile) {
        Get-Content $ConfigFile | ForEach-Object {
            if ($_ -match "^(\w+)=(.*)") { $Cfg[$Matches[1]] = $Matches[2] }
        }
    }
}
function Save-Config {
    [IO.File]::WriteAllLines($ConfigFile, @("URL=$($Cfg.URL)", "W=$($Cfg.W)", "H=$($Cfg.H)"))
}
Load-Config

# -- Colors
$Bdr="Cyan"; $Ttl="Cyan"; $Lbl="DarkCyan"; $Val="White"
$Key="Yellow"; $Dim="DarkGray"; $Err="Red"; $Log="Gray"; $Acc="Cyan"
$Sel="Black"; $SelBg="Cyan"

# ====================================================================
# Drawing helpers
# ====================================================================
function Rep([char]$c, [int]$n) { if ($n -lt 1) { return "" }; return [string]::new($c, $n) }

function Box-Top([string]$lbl = "") {
    if ($lbl) {
        $p = [int][math]::Floor(($W - $lbl.Length - 2) / 2)
        $r = [int]($W - $lbl.Length - 2 - $p)
        Write-Host ("  " + $bTL + (Rep $bH $p) + " ") -NoNewline -ForegroundColor $Bdr
        Write-Host $lbl -NoNewline -ForegroundColor $Ttl
        Write-Host (" " + (Rep $bH $r) + $bTR) -ForegroundColor $Bdr
    } else {
        Write-Host ("  " + $bTL + (Rep $bH $W) + $bTR) -ForegroundColor $Bdr
    }
}
function Box-Bot { Write-Host ("  " + $bBL + (Rep $bH $W) + $bBR) -ForegroundColor $Bdr }
function Box-Div { Write-Host ("  " + $bML + (Rep $bH $W) + $bMR) -ForegroundColor $Bdr }

function Box-Row([string]$text = "", [string]$fg = $Val) {
    $inner = (" " + $text).PadRight($W)
    if ($inner.Length -gt $W) { $inner = $inner.Substring(0, $W) }
    Write-Host ("  " + $bV) -NoNewline -ForegroundColor $Bdr
    Write-Host $inner -NoNewline -ForegroundColor $fg
    Write-Host $bV -ForegroundColor $Bdr
}
function Box-Blank { Box-Row }

function Box-Field([string]$label, [string]$value) {
    $l = $label.PadRight(9)
    Write-Host ("  " + $bV + " ") -NoNewline -ForegroundColor $Bdr
    Write-Host $l -NoNewline -ForegroundColor $Lbl
    $vpad = $value.PadRight($W - $l.Length - 2)
    if ($vpad.Length -gt ($W - $l.Length - 2)) { $vpad = $vpad.Substring(0, $W - $l.Length - 2) }
    Write-Host $vpad -NoNewline -ForegroundColor $Val
    Write-Host $bV -ForegroundColor $Bdr
}

# Draw a menu item - highlighted if selected
function Box-MenuItem([string]$label, [bool]$selected) {
    $arrow = if ($selected) { " > " } else { "   " }
    $text  = ($arrow + $label).PadRight($W)
    if ($text.Length -gt $W) { $text = $text.Substring(0, $W) }
    Write-Host ("  " + $bV) -NoNewline -ForegroundColor $Bdr
    if ($selected) {
        Write-Host $text -NoNewline -BackgroundColor $SelBg -ForegroundColor $Sel
    } else {
        Write-Host $text -NoNewline -ForegroundColor $Val
    }
    Write-Host $bV -ForegroundColor $Bdr
}

function Draw-Header([string]$page = "") {
    Write-Host ""
    Box-Top " OpenConnection v1.0.0 "
    Box-Row "  Text-Based Browser Launcher" $Dim
    if ($page) { Box-Div; Box-Row "  $page" $Ttl }
    Box-Div
}

# Text input box
function Show-Input([string]$hint = "") {
    Write-Host ""
    Write-Host ("  " + $bTL + (Rep $bH $W) + $bTR) -ForegroundColor $Bdr
    Write-Host ("  " + $bV + " ") -NoNewline -ForegroundColor $Bdr
    Write-Host "> " -NoNewline -ForegroundColor $Acc
    Write-Host ("" + $hint) -NoNewline -ForegroundColor $Dim
    # Move cursor back to after "> "
    if ($hint) {
        $pos = [Console]::CursorLeft - $hint.Length
        [Console]::CursorLeft = $pos
    }
    $result = Read-Host
    Write-Host ("  " + $bBL + (Rep $bH $W) + $bBR) -ForegroundColor $Bdr
    return $result
}

# ====================================================================
# Arrow-key menu - returns index of selected item (0-based)
# items: array of strings
# ====================================================================
function Show-Menu([string[]]$items, [int]$default = 0) {
    $idx   = $default
    $count = $items.Length

    $startRow = [Console]::CursorTop

    # Draw all items + footer once
    [Console]::CursorVisible = $false
    for ($i = 0; $i -lt $count; $i++) { Box-MenuItem $items[$i] ($i -eq $idx) }
    Box-Blank
    Box-Bot
    Write-Host ""
    Box-Row "  Arrow keys to move   Enter to select   Esc to go back" $Dim
    Write-Host ""
    [Console]::CursorVisible = $false

    while ($true) {
        $k = [Console]::ReadKey($true)
        $newIdx = $idx
        switch ($k.Key) {
            "UpArrow"   { $newIdx = ($idx - 1 + $count) % $count }
            "DownArrow" { $newIdx = ($idx + 1) % $count }
            "Enter"     { [Console]::CursorVisible = $true; return $idx }
            "Escape"    { [Console]::CursorVisible = $true; return -1 }
        }
        if ($newIdx -ne $idx) {
            $idx = $newIdx
            # Hide cursor, jump back, redraw only the item rows (not footer)
            [Console]::CursorVisible = $false
            [Console]::CursorTop = $startRow
            for ($i = 0; $i -lt $count; $i++) { Box-MenuItem $items[$i] ($i -eq $idx) }
        }
    }
}

# ====================================================================
# MAIN MENU
# ====================================================================
function Draw-ProgressBar([int]$pct, [string]$label) {
    $barW   = $W - 4
    $filled = [int][math]::Floor($barW * $pct / 100)
    $empty  = $barW - $filled
    $bar    = (Rep ([char]0x2588) $filled) + (Rep ([char]0x2591) $empty)
    $pctStr = ("$pct%").PadLeft(4)
    # Redraw the two progress rows in place
    Write-Host ("  " + $bV + " ") -NoNewline -ForegroundColor $Bdr
    Write-Host $bar -NoNewline -ForegroundColor "Cyan"
    Write-Host (" " + $bV) -ForegroundColor $Bdr
    Write-Host ("  " + $bV + " ") -NoNewline -ForegroundColor $Bdr
    $lbl = (" " + $pctStr + "  " + $label).PadRight($W - 1)
    if ($lbl.Length -gt ($W - 1)) { $lbl = $lbl.Substring(0, $W - 1) }
    Write-Host $lbl -NoNewline -ForegroundColor $Dim
    Write-Host $bV -ForegroundColor $Bdr
}

function Show-ResetData {
    Clear-Host
    Draw-Header "RESET DATA"
    Box-Blank
    Box-Row "  This will permanently delete:" $Val
    Box-Blank
    Box-Row "    - All session logs in /logs" $Dim
    Box-Row "    - Chromium User_Data (cache, history, cookies)" $Dim
    Box-Row "    - Chromium debug.log files" $Dim
    Box-Row "    - config.ini (resets URL and window size)" $Dim
    Box-Blank
    Box-Div
    Box-Row "  Are you sure?" $Key
    Box-Blank
    $choice = Show-Menu @("  Cancel - keep my data", "  Yes - delete everything")
    if ($choice -ne 1) { return }

    # ---- Deleting screen ----
    Clear-Host
    Draw-Header "RESET DATA"
    Box-Blank
    Box-Row "  Deleting data..." $Val
    Box-Blank
    Box-Top " Progress "
    Box-Blank  # placeholder for bar
    Box-Blank  # placeholder for label
    Box-Bot

    # Helper: jump up N lines, redraw progress, jump back down
    function Update-Progress([int]$pct, [string]$label) {
        [Console]::CursorVisible = $false
        $cur = [Console]::CursorTop
        # bar is 3 lines up from current (Bot + label + bar)
        [Console]::CursorTop = $cur - 3
        Draw-ProgressBar $pct $label
        [Console]::CursorTop = $cur
        [Console]::CursorVisible = $false
    }

    Update-Progress 0 "Starting..."

    # Step 1 - count files for accurate progress
    $logFiles  = if (Test-Path $LogDir)      { @(Get-ChildItem $LogDir -Recurse -File -EA SilentlyContinue) } else { @() }
    $dataFiles = if (Test-Path $UserDataDir) { @(Get-ChildItem $UserDataDir -Recurse -File -EA SilentlyContinue) } else { @() }
    $total = $logFiles.Count + $dataFiles.Count + 1  # +1 for config
    if ($total -lt 1) { $total = 1 }
    $done = 0

    Update-Progress 5 "Counting files..."

    # Step 2 - delete log files individually for smooth progress
    foreach ($f in $logFiles) {
        Remove-Item -LiteralPath $f.FullName -Force -EA SilentlyContinue
        $done++
        $pct = [int][math]::Min(5 + [math]::Floor($done / $total * 50), 55)
        Update-Progress $pct "Deleting logs... ($done / $($logFiles.Count))"
    }
    if (Test-Path $LogDir) {
        Get-ChildItem $LogDir -Directory -Recurse | Sort-Object FullName -Descending |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -EA SilentlyContinue }
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    Update-Progress 55 "Deleting User_Data..."

    # Step 3 - delete user data files
    foreach ($f in $dataFiles) {
        Remove-Item -LiteralPath $f.FullName -Force -EA SilentlyContinue
        $done++
        $pct = [int][math]::Min(55 + [math]::Floor(($done - $logFiles.Count) / $total * 35), 90)
        Update-Progress $pct "Deleting User_Data... ($($done - $logFiles.Count) / $($dataFiles.Count))"
    }
    if (Test-Path $UserDataDir) {
        Get-ChildItem $UserDataDir -Directory -Recurse | Sort-Object FullName -Descending |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -EA SilentlyContinue }
        Remove-Item -LiteralPath $UserDataDir -Force -EA SilentlyContinue
    }

    Update-Progress 90 "Deleting debug logs..."

    # Step 4 - delete debug.log files
    $debugLogs = @(
        [IO.Path]::Combine($ScriptDir, "Chromium", "chrome-win", "debug.log"),
        [IO.Path]::Combine($ScriptDir, "Chromium", "chrome-win", "chrome_debug.log")
    )
    foreach ($dl in $debugLogs) {
        if (Test-Path $dl) { Remove-Item -LiteralPath $dl -Force -EA SilentlyContinue }
    }
    Start-Sleep -Milliseconds 150

    Update-Progress 95 "Resetting config..."

    # Step 5 - reset config
    $Cfg.URL = "https://www.google.com"; $Cfg.W = "800"; $Cfg.H = "600"
    Save-Config
    Start-Sleep -Milliseconds 200

    Update-Progress 100 "Done!"
    [Console]::CursorVisible = $true
    Start-Sleep -Milliseconds 400

    Clear-Host
    Draw-Header "RESET DATA"
    Box-Blank
    Box-Row "  All data has been cleared." "Green"
    Box-Row "  Config reset to defaults." "Green"
    Box-Blank
    Box-Bot
    Write-Host ""
    Box-Row "  Press any key to return to the menu..." $Dim
    Write-Host ""
    [Console]::ReadKey($true) | Out-Null
}

function Show-MainMenu {
    while ($true) {
        # header(5) + blank + 4 items + blank + bot + hint + 2 padding = 17
        Set-WindowSize ($W + 6) 20
        Clear-Host
        Draw-Header "MAIN MENU"
        Box-Blank
        $choice = Show-Menu @(
            "  Configure and Launch",
            "  View Session Logs",
            "  Reset Data",
            "  Exit"
        )
        switch ($choice) {
            0 { Show-ConfigPage }
            1 { Show-LogListPage }
            2 { Show-ResetData }
            3 { Clear-Host; exit }
        }
    }
}

# ====================================================================
# CONFIG PAGE
# ====================================================================
function Show-ConfigPage {
    while ($true) {
        # header(5) + blank + 3 fields + blank + div + blank + 5 items + blank + bot + hint + 2 padding = 26
        Set-WindowSize ($W + 6) 28
        Clear-Host
        Draw-Header "CONFIGURATION"
        Box-Blank
        Box-Field "URL     " $Cfg.URL
        Box-Field "Width   " $Cfg.W
        Box-Field "Height  " $Cfg.H
        Box-Blank
        Box-Div
        Box-Blank
        $choice = Show-Menu @(
            "  Change URL",
            "  Change Width",
            "  Change Height",
            "  Apply and Launch",
            "  Back to Main Menu"
        )
        switch ($choice) {
            0 {
                Clear-Host; Draw-Header "CHANGE URL"
                Box-Blank; Box-Field "Current " $Cfg.URL; Box-Blank; Box-Bot
                $v = Show-Input; if ($v) { $Cfg.URL = $v }
            }
            1 {
                Clear-Host; Draw-Header "CHANGE WIDTH"
                Box-Blank; Box-Field "Current " $Cfg.W; Box-Blank; Box-Bot
                $v = Show-Input; if ($v) { $Cfg.W = $v }
            }
            2 {
                Clear-Host; Draw-Header "CHANGE HEIGHT"
                Box-Blank; Box-Field "Current " $Cfg.H; Box-Blank; Box-Bot
                $v = Show-Input; if ($v) { $Cfg.H = $v }
            }
            3 { Save-Config; Show-LiveLog; return }
            4 { return }
           -1 { return }
        }
    }
}

# ====================================================================
# LIVE LOG
# ====================================================================
function Show-LiveLog {
    $ts      = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogFile = [IO.Path]::Combine($LogDir, "session_$ts.txt")
    $lines   = [Collections.Generic.List[string]]::new()

    # Live log needs tall window for streaming logs
    Set-WindowSize ($W + 6) 60
    Clear-Host
    Draw-Header "LIVE LOG"
    Box-Blank
    Box-Field "URL     " $Cfg.URL
    Box-Field "Size    " "$($Cfg.W) x $($Cfg.H)"
    Box-Field "Log     " (Split-Path $LogFile -Leaf)
    Box-Blank
    Box-Div
    Box-Row "   Press  [S] to stop Chromium   [B] to go back" $Dim
    Box-Div
    Box-Blank
    Box-Bot
    Write-Host ""
    Box-Top " Logs "
    Box-Blank

    $CL1 = [IO.Path]::Combine($ScriptDir, "Chromium", "chrome-win", "debug.log")
    $CL2 = [IO.Path]::Combine($UserDataDir, "chrome_debug.log")
    $CL  = $CL1

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName        = $ChromePath
    $psi.Arguments       = "--app=`"$($Cfg.URL)`" --window-size=$($Cfg.W),$($Cfg.H) --enable-logging --log-level=0 --user-data-dir=`"$UserDataDir`""
    $psi.UseShellExecute = $true

    try { $proc = [Diagnostics.Process]::Start($psi) }
    catch {
        Box-Row "  ERROR: $($_.Exception.Message)" $Err
        Box-Blank; Box-Bot; Read-Host "  Press Enter"; return
    }

    $waited = 0
    while ($waited -lt 40) {
        if (Test-Path $CL1) { $CL = $CL1; break }
        if (Test-Path $CL2) { $CL = $CL2; break }
        Start-Sleep -Milliseconds 100; $waited++
    }

    $reader = $null
    if (Test-Path $CL) {
        Box-Row "  Reading: $(Split-Path $CL -Leaf)" $Dim
        $reader = [IO.StreamReader]::new(
            [IO.FileStream]::new($CL, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite),
            [Text.Encoding]::UTF8)
    } else {
        Box-Row "  (log file not found)" $Dim
    }

    while (-not $proc.HasExited) {
        if ($reader) {
            $line = $reader.ReadLine()
            if ($null -ne $line) { $lines.Add($line); Box-Row "  $line" $Log; continue }
        }
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq "S") {
                Box-Blank; Box-Row "  Stopping Chromium..." $Lbl
                try { $proc.Kill() } catch {}
                Get-Process -Name chrome -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
                break
            }
            if ($k.Key -eq "B") { Box-Blank; Box-Row "  Returning to config..." $Dim; break }
        }
        Start-Sleep -Milliseconds 50
    }

    if ($reader) {
        Start-Sleep -Milliseconds 200
        while ($null -ne ($line = $reader.ReadLine())) { $lines.Add($line); Box-Row "  $line" $Log }
        $reader.Close()
    }
    try { $proc.WaitForExit(2000) | Out-Null } catch {}
    [IO.File]::WriteAllLines($LogFile, $lines)

    Box-Blank; Box-Bot
    # Shrink back down for end screen: top + blank + field + blank + div + blank + 2 items + blank + bot + hint
    Set-WindowSize ($W + 6) 22
    Write-Host ""
    Box-Top " Session Ended "
    Box-Blank
    Box-Field "Saved   " (Split-Path $LogFile -Leaf)
    Box-Blank
    Box-Div
    Box-Blank
    $choice = Show-Menu @("  Back to Config", "  Main Menu")
    if ($choice -eq 1) { Show-MainMenu; return }
}

# ====================================================================
# LOG LIST
# ====================================================================
function Show-LogListPage {
    while ($true) {
        Clear-Host
        Draw-Header "SESSION LOGS"
        Box-Blank

        $logs = Get-ChildItem -Path $LogDir -Filter "session_*.txt" -EA SilentlyContinue |
                Sort-Object Name -Descending

        if (-not $logs -or $logs.Count -eq 0) {
            Box-Row "  No log files found yet." $Dim
            Box-Blank; Box-Div; Box-Blank
            $choice = Show-Menu @("  Back to Main Menu")
            return
        }

        $items = @($logs | ForEach-Object { "  " + $_.Name }) + "  Back to Main Menu"
        # header(5) + blank + items + blank + div + blank + bot + hint + 2 padding
        $dynRows = [math]::Min(5 + 2 + $items.Length + 6, $MaxRows)
        Set-WindowSize ($W + 6) $dynRows
        $choice = Show-Menu $items

        if ($choice -eq ($items.Length - 1) -or $choice -eq -1) { return }
        if ($choice -ge 0 -and $choice -lt $logs.Count) {
            Show-LogView $logs[$choice].FullName $logs[$choice].Name
        }
    }
}

# ====================================================================
# LOG VIEWER
# ====================================================================
function Show-LogView([string]$path, [string]$name) {
    Clear-Host
    Draw-Header "LOG VIEWER"
    Box-Blank
    Box-Field "File    " $name
    Box-Blank
    Box-Bot
    Write-Host ""
    Box-Top " Logs "
    Box-Blank
    $logLines = Get-Content $path
    $logLines | ForEach-Object { Box-Row "  $_" $Log }
    # header(5) + blank + field + blank + bot + log top + blank + loglines + blank + bot + nav box + 2 items + blank + bot + hint
    $dynRows = [math]::Min(16 + $logLines.Count + 8, $MaxRows)
    Set-WindowSize ($W + 6) $dynRows
    Box-Blank; Box-Bot
    Write-Host ""
    Box-Top
    Box-Blank
    $choice = Show-Menu @("  Back to Log List", "  Back to Main Menu")
    if ($choice -eq 1) { Show-MainMenu }
}

# -- Entry point
try {
    Show-MainMenu
} catch {
    Write-Host ""
    Write-Host "  CRASH: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  Line $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  Press Enter to close"
}