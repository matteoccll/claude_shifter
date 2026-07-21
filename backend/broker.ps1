#Requires -Version 5.1
# UIA Broker -- NDJSON over stdin/stdout
# Spawn: powershell -NonInteractive -ExecutionPolicy Bypass -File broker.ps1
#
# NOTE: this file is deliberately pure ASCII. PowerShell 5.1 reads .ps1 as ANSI
# unless there is a BOM, so literal non-ASCII characters get mangled (and curly
# quotes are treated as string delimiters, which breaks parsing). Non-ASCII
# characters that matter are written as escapes, e.g. the middle dot
# that separates a session number from its title.
#
# Protocol: one JSON object per line on both sides
#   Request:  {"id":<int>,"cmd":<str>[,...args]}
#   Response: {"id":<int>,"ok":true,"data":{...}} | {"id":<int>,"ok":false,"error":"..."}
#   Event:    {"event":"attached","pid":<int>}    | {"event":"error","message":"..."}

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

# -- Win32 --------------------------------------------------------------------
Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public class W {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lp);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    // Deliberately no keybd_event / SendInput: synthetic keystrokes land in the
    // Claude window as real input, and Escape there cancels the running turn.
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    // Per-monitor DPI awareness, so UIA screen coordinates and cursor
    // coordinates agree. Without this a click lands in the wrong place on a
    // scaled display.
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();

    public class CW { public IntPtr Hwnd; public uint Pid; public long Area; }

    // Every visible Claude window, not just the first one found. Taking the
    // first was a real bug: this app owns several windows, and a re-attach
    // grabbed a small one with no model button in it, after which every command
    // failed with "elements not found". Area lets the caller try the main
    // window before the small fry.
    public static CW[] FindClaudeWindows() {
        var list = new System.Collections.Generic.List<CW>();
        EnumWindows((hwnd, lp) => {
            if (!IsWindowVisible(hwnd)) return true;
            if (GetWindowTextLength(hwnd) == 0) return true;
            uint pid; GetWindowThreadProcessId(hwnd, out pid);
            try {
                var p = Process.GetProcessById((int)pid);
                if (!p.ProcessName.Equals("Claude", StringComparison.OrdinalIgnoreCase)) return true;
                RECT r; GetWindowRect(hwnd, out r);
                long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
                list.Add(new CW { Hwnd = hwnd, Pid = pid, Area = area });
            } catch {}
            return true;
        }, IntPtr.Zero);
        return list.ToArray();
    }
}
"@

# Non-ASCII literals needed at runtime, built by code point.
$MIDDOT = [string][char]0x00B7

# -- IPC helpers --------------------------------------------------------------
function Log { param($msg) [Console]::Error.WriteLine("[broker] $msg") }

function Send {
    param($obj)
    [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress -Depth 10))
    [Console]::Out.Flush()
}
function Reply-Ok {
    param($id, $data)
    if ($null -ne $data) { Send @{ id = $id; ok = $true; data = $data } }
    else                 { Send @{ id = $id; ok = $true } }
}
function Reply-Err {
    param($id, $msg)
    Send @{ id = $id; ok = $false; error = [string]$msg }
}

# Read a required argument, telling "absent" apart from "present and empty".
#
# PowerShell answers for a property that is not there with $null, and then
# quietly coerces it: [string]$null is '' and [int]$null is 0. Both are valid
# looking values, so a command that arrived without its argument used to act on
# the coerced one -- setModel engaged the first model in the menu, setEffort
# dropped to the bottom of the ladder, and both reported success. A field that
# JavaScript left undefined never even reaches the JSON, so this is one dropped
# line in the GUI away, not a hypothetical.
function ReqArg {
    param($req, [string]$name)
    if (-not $req.PSObject.Properties[$name]) { throw "$($req.cmd): missing '$name'" }
    $v = $req.$name
    if ($null -eq $v) { throw "$($req.cmd): '$name' is null" }
    return $v
}

# -- UIA state ----------------------------------------------------------------
$script:root   = $null
$script:hwnd   = [IntPtr]::Zero
$script:pid0   = [uint32]0
$script:walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$A             = [System.Windows.Automation.AutomationElement]

# One CacheRequest, reused for every walk. The whole point of the tree cache is
# to stop paying a cross-process round-trip per element: GetUpdatedCache pulls
# the entire subtree AND the two properties we filter on (Name, ControlType) in
# a single marshalled call, after which .Cached.* and .CachedChildren are read
# from a local snapshot for free. See Walk for why this replaced the old
# GetFirstChild/GetNextSibling walk.
#
# AutomationElementMode.Full keeps the returned handles live-capable: the same
# element is later actuated (Expand, Select, SetValue) and re-read live for
# verification, so the cache must not downgrade it to a properties-only husk.
# TreeFilter is the control view, matching the ControlViewWalker used before, so
# the set of elements a walk sees is unchanged -- only how fast it sees them.
$script:cacheReq = New-Object System.Windows.Automation.CacheRequest
$script:cacheReq.Add([System.Windows.Automation.AutomationElement]::NameProperty)
$script:cacheReq.Add([System.Windows.Automation.AutomationElement]::ControlTypeProperty)
$script:cacheReq.TreeScope            = [System.Windows.Automation.TreeScope]::Subtree
$script:cacheReq.AutomationElementMode = [System.Windows.Automation.AutomationElementMode]::Full
$script:cacheReq.TreeFilter           = [System.Windows.Automation.Automation]::ControlViewCondition

# -- Tree walk ----------------------------------------------------------------
# Returns elements in document order: the sidebar comes before the main pane,
# which is what lets us prefer a sidebar entry over a same-named element
# elsewhere in the window.
#
# This walk used to navigate the tree by hand -- GetFirstChild / GetNextSibling
# per node, then a live Name and ControlType read per node -- and every one of
# those was a cross-process call, so a full walk of this ~1000-element app cost
# roughly a second. A finder calls Walk, and an operation calls several finders;
# `capabilities` alone walks the tree a dozen-plus times, which is where its
# seconds went.
#
# Now GetUpdatedCache pulls the whole subtree, with Name and ControlType, in a
# single marshalled call (see $script:cacheReq), and the DFS below reads it all
# from the local snapshot: .CachedChildren for structure, .Cached.* for the two
# properties, zero further round-trips. Same elements, same document order (the
# stack pushes children last-first so the first child is popped first, exactly
# as the old hand walk did) -- just built in one call instead of thousands.
#
# The result is still cached per command and explicitly invalidated whenever we
# do something that can change the tree, because even one round-trip is worth
# not repeating between finders.
$script:walkCache = $null

function InvalidateWalk { $script:walkCache = $null }

function Ct   { param($e) try { $e.Current.ControlType.ProgrammaticName -replace '^ControlType\.','' } catch { '' } }
function Nm   { param($e) try { if ($null -eq $e.Current.Name) { '' } else { $e.Current.Name } } catch { '' } }

# Read the cached Name/ControlType off an element pulled by GetUpdatedCache.
# These never touch the wire; the properties were fetched with the subtree.
function CtCached { param($e) try { $e.Cached.ControlType.ProgrammaticName -replace '^ControlType\.','' } catch { '' } }
function NmCached { param($e) try { $v = $e.Cached.Name; if ($null -eq $v) { '' } else { $v } } catch { '' } }

# Walk returns rows, not bare elements: control type and name travel with each
# element so filters read them without another cross-process hit.
#   .El = the AutomationElement (live-capable), .Ct = control type, .Nm = name
function Walk {
    if ($null -ne $script:walkCache) { return $script:walkCache }
    if (-not $script:root) { return @() }

    $rows = New-Object System.Collections.Generic.List[object]

    # One round-trip: the whole control-view subtree plus Name and ControlType.
    $cachedRoot = $null
    try { $cachedRoot = $script:root.GetUpdatedCache($script:cacheReq) } catch { return $rows }
    if (-not $cachedRoot) { return $rows }

    $stack = New-Object System.Collections.Stack
    $stack.Push($cachedRoot)
    $n = 0
    while ($stack.Count -gt 0 -and $n -lt 12000) {
        $el = $stack.Pop(); $n++
        $rows.Add([pscustomobject]@{ El = $el; Ct = (CtCached $el); Nm = (NmCached $el) })
        $kids = $null
        try { $kids = $el.CachedChildren } catch {}
        if ($kids) {
            for ($i = $kids.Count - 1; $i -ge 0; $i--) { $stack.Push($kids[$i]) }
        }
    }

    $script:walkCache = $rows
    return $rows
}
function IsOn { param($e) try { [bool]$e.Current.IsEnabled } catch { $false } }
function IsSel {
    param($e)
    try { [bool]$e.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected }
    catch { $false }
}

# -- Attach -------------------------------------------------------------------
function Attach {
    # $Launch only applies at startup. A re-attach never launches the app: if the
    # user closed Claude Desktop, reopening it uninvited is worse than an honest
    # error, and the GUI can say "l'app e' chiusa" instead.
    param([bool]$Launch = $true)

    $wins = @([W]::FindClaudeWindows() | Sort-Object -Property Area -Descending)

    if ($wins.Count -eq 0) {
        if (-not $Launch) { Log "Claude Desktop not running"; return $false }
        Log "Claude Desktop not found - launching"
        Start-Process "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"
        Start-Sleep -Seconds 4
        $wins = @([W]::FindClaudeWindows() | Sort-Object -Property Area -Descending)
        if ($wins.Count -eq 0) { return $false }
    }

    Log "candidate Claude windows: $($wins.Count)"

    # The acceptance test is the model button, not an element count. A count
    # threshold accepted a secondary window with 49 named elements and no lever
    # in it, and every command after that failed with "elements not found". The
    # button is what every operation actually needs, so that is what we look for.
    $fallback = $null
    foreach ($w in $wins) {
        Log "trying hwnd=$($w.Hwnd) pid=$($w.Pid) area=$($w.Area)"
        $script:hwnd = $w.Hwnd
        $script:pid0 = $w.Pid

        # Restore only if minimised -- a minimised window has no tree to read.
        # Never raise: reads are focus-free, and stealing focus from whatever the
        # user is doing is rude.
        if ([W]::IsIconic($w.Hwnd)) { [W]::ShowWindow($w.Hwnd, 9) | Out-Null }   # SW_RESTORE
        Start-Sleep -Milliseconds 600

        $script:root = $A::FromHandle($w.Hwnd)

        # Chromium keeps its a11y tree asleep until a UIA client walks it, so a
        # cold window needs a few passes before it has anything in it.
        for ($i = 0; $i -lt 5; $i++) {
            InvalidateWalk
            $named = @(Walk | Where-Object { $_.Nm.Length -gt 0 }).Count
            $lever = $null -ne (ModelBtn)
            Log "  wake[$i] named=$named lever=$lever"
            if ($lever) { Log "attached to hwnd=$($w.Hwnd) pid=$($w.Pid)"; return $true }
            if ($named -gt 40 -and -not $fallback) { $fallback = $w }
            Start-Sleep -Milliseconds 1500
        }
    }

    # No window had a lever. Not necessarily broken: the app can legitimately be
    # sitting on a screen with no model button. Bind to the richest window we saw
    # so reads that do not need the lever still work, and say so.
    if ($fallback) {
        Log "WARNING: no window exposed a model button - falling back to hwnd=$($fallback.Hwnd)"
        $script:hwnd = $fallback.Hwnd
        $script:pid0 = $fallback.Pid
        $script:root = $A::FromHandle($fallback.Hwnd)
        InvalidateWalk
        return $true
    }
    return $false
}

# -- Re-attach ----------------------------------------------------------------
# The broker used to attach once and stay bound to that window handle for life.
# Close and reopen Claude Desktop and every command from then on failed with an
# obscure UIA error, and the only cure was restarting the broker by hand. So
# check liveness before each command and rebind when the window is gone.
#
# Three checks, cheapest first, because this runs on every single command:
#   1. the handle still names a window,
#   2. the process we attached to is still alive and still Claude,
#   3. the UIA root still answers a LIVE property read.
# The third is what catches a window that Windows still lists but whose
# accessibility tree died with the renderer. One cross-process read, ~1 ms --
# a full tree walk here would cost a second per command.
#
# It must be GetCurrentPropertyValue, not $root.Current.Name. Measured with
# alivecheck.ps1: after the target process is killed, .Current.Name keeps
# answering happily from a cached value, so a check written that way reports a
# healthy tree over a corpse. GetCurrentPropertyValue goes and asks, and throws
# when there is nobody left to answer.
#
# Deliberately NOT checked: whether FindClaudeHwnd still returns *our* handle.
# It returns the first Claude window it meets, so with two windows open that
# comparison would flip constantly and re-attach on every command.
function IsAlive {
    if ($script:hwnd -eq [IntPtr]::Zero -or $null -eq $script:root) { return $false }
    if (-not [W]::IsWindow($script:hwnd)) { return $false }
    try {
        $p = Get-Process -Id ([int]$script:pid0) -ErrorAction Stop
        if ($p.ProcessName -ne 'Claude') { return $false }
    } catch { return $false }
    try { $null = $script:root.GetCurrentPropertyValue($A::NameProperty) } catch { return $false }
    return $true
}

# Returns $false when the app is genuinely gone; the caller answers with an
# error instead of pretending. Emits an event either way so a GUI can show the
# state without polling.
function EnsureAttached {
    if (IsAlive) { return $true }

    $was = [int]$script:pid0
    Log "attachment lost (was pid=$was) - reattaching"
    InvalidateWalk
    $script:root = $null
    $script:hwnd = [IntPtr]::Zero

    if (Attach $false) {
        Send @{ event = 'reattached'; pid = [int]$script:pid0; previousPid = $was }
        Log "Reattached to Claude pid=$($script:pid0)"
        return $true
    }

    Send @{ event = 'detached'; message = 'Claude Desktop is not running' }
    return $false
}

# -- Localisation -------------------------------------------------------------
# The app UI follows the OS language (this machine renders it in Italian), so
# label matching cannot assume English. Model names and the Usage string are
# language-neutral; the effort button and the per-session "more options" button
# are not.
#
# English first, then the languages we can name. Only the English and Italian
# spellings are verified on a real app -- the rest are best effort and unproven,
# which is exactly why every label match here has a structural fallback that
# works on shape rather than wording. Extend the alternations freely; a wrong
# guess costs nothing because the fallback still finds the control.
# Non-ASCII letters are written as \uXXXX escapes to keep this file ASCII.
$RX_EFFORT_BTN = '^(?:Effort|Impegno|Aufwand|Esfuerzo|Esfor\u00E7o|Inspanning|Wysi\u0142ek|Insats|Indsats|Panos)\s*:'
$RX_MORE_OPTS  = '^(?:More options for|Altre opzioni per|Weitere Optionen f\u00FCr|M\u00E1s opciones para|Plus d[\u0027\u2019]options pour|Mais op\u00E7\u00F5es para|Meer opties voor|Fler alternativ f\u00F6r|Flere indstillinger for)\s+(.+)$'
$RX_MODEL      = '^(?:Sonnet|Opus|Haiku|Fable)\b'
$RX_USAGE      = '^Usage:'

# -- Element finders ----------------------------------------------------------
function HasPattern {
    param($e, $pattern)
    try { $null = $e.GetCurrentPattern($pattern); return $true } catch { return $false }
}

function Row2El { param($r) if ($r) { $r.El } else { $null } }

# The name alone is not enough for the model button: the sidebar precedes it in
# document order, and a conversation whose auto-generated title starts with a
# model name ("Fable 5 idee") would be matched first and break every command.
# The model button is the one that opens a menu, so demand ExpandCollapse --
# session rows do not have it. The pattern probe is a cross-process call, but
# only buttons whose name already matches pay it (normally exactly one).
function ModelBtn {
    Row2El (Walk | Where-Object {
        $_.Ct -eq 'Button' -and $_.Nm -match $RX_MODEL -and
        (HasPattern $_.El ([System.Windows.Automation.ExpandCollapsePattern]::Pattern))
    } | Select-Object -First 1)
}
function UsageBtn  { Row2El (Walk | Where-Object { $_.Ct -eq 'Button' -and $_.Nm -match $RX_USAGE } | Select-Object -First 1) }
function SliderEl  { Row2El (Walk | Where-Object { $_.Ct -eq 'Slider' } | Select-Object -First 1) }

# Effort button: try the label table, then fall back on shape. Structurally it
# is the next expandable Button after the model button in document order, and
# it is neither the model button nor the Usage readout. That holds in any
# language.
function EffortBtn {
    $buttons = @(Walk | Where-Object { $_.Ct -eq 'Button' })

    $byName = $buttons | Where-Object { $_.Nm -match $RX_EFFORT_BTN } | Select-Object -First 1
    if ($byName) { return $byName.El }

    $modelIdx = -1
    for ($i = 0; $i -lt $buttons.Count; $i++) {
        if ($buttons[$i].Nm -match $RX_MODEL) { $modelIdx = $i; break }
    }
    if ($modelIdx -lt 0) { return $null }

    for ($i = $modelIdx + 1; $i -lt $buttons.Count; $i++) {
        $n = $buttons[$i].Nm
        if ($n -match $RX_USAGE -or $n -match $RX_MODEL) { continue }
        if (HasPattern $buttons[$i].El ([System.Windows.Automation.ExpandCollapsePattern]::Pattern)) {
            Log "effort button found structurally: '$n'"
            return $buttons[$i].El
        }
    }
    return $null
}

# Rows (not elements) so callers can read Nm without another cross-process hit.
function ModelOptionRows {
    Walk | Where-Object { $_.Ct -match 'RadioButton|MenuItem' -and $_.Nm -match $RX_MODEL }
}
function ModelOptions { ModelOptionRows | ForEach-Object { $_.El } }

# Sidebar sessions. Each entry is a pair of buttons: the clickable row, named
# "<status> <title>" (or just "<title>" when idle), and a companion button named
# "More options for <title>". The companion is what gives us the clean title;
# we then match the row back by suffix. Document order matters: the sidebar row
# precedes the same-titled header in the main pane, so First wins.
function SessionEntries {
    $buttons = @(Walk | Where-Object { $_.Ct -eq 'Button' })
    $titles  = New-Object System.Collections.Generic.List[string]

    foreach ($b in $buttons) {
        if ($b.Nm -match $RX_MORE_OPTS) {
            $t = $Matches[1].Trim()
            if ($t -and -not $titles.Contains($t)) { $titles.Add($t) }
        }
    }

    $out = @()
    foreach ($t in $titles) {
        $row = $buttons | Where-Object {
            $_.Nm -notmatch $RX_MORE_OPTS -and ($_.Nm -eq $t -or $_.Nm.EndsWith(" $t"))
        } | Select-Object -First 1
        if (-not $row) { continue }
        $status = if ($row.Nm -eq $t) { '' } else { $row.Nm.Substring(0, $row.Nm.Length - $t.Length).Trim() }
        $out += [pscustomobject]@{ Title = $t; Status = $status; Element = $row.El }
    }
    return $out
}

# -- Popup helpers ------------------------------------------------------------
function Expand {
    param($e)
    try {
        $e.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
        InvalidateWalk
        return $true
    } catch { return $false }
}

# Close any open model/effort popup.
#
# This used to press Escape with keybd_event. That was actively harmful: the
# keystroke goes to the Claude window as a real key, and Escape in Claude
# Desktop cancels the running turn. Driving the app from a task running *inside*
# that same app meant every popup-close aborted the very command doing the
# closing. Collapse the control directly instead: targeted, silent, and it
# neither steals focus nor sends input anywhere.
function ClosePopups {
    foreach ($btn in @((ModelBtn), (EffortBtn))) {
        if (-not $btn) { continue }
        try {
            $p = $btn.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
            if ($p.Current.ExpandCollapseState -ne [System.Windows.Automation.ExpandCollapseState]::Collapsed) {
                $p.Collapse()
                Start-Sleep -Milliseconds 300
            }
        } catch {}
    }
    InvalidateWalk
}

# Drop the leading "<word>:" the effort button carries in whatever language the
# app is running ("Effort: High", "Impegno: Alto"), leaving just the level.
function StripEffort { param($s) ($s -replace '^[^:]{1,24}:\s*','').Trim() }

# Wait for a tree change to materialise, returning the instant it does instead of
# sleeping a fixed quantum and hoping.
#
# UIA popups render a beat after the call that triggers them (Expand, a hover).
# That beat is short in the common case but stretches right after a model change,
# when the app is still settling -- which is exactly the sporadic ~10s spike on
# capabilities (sess. 14: "non e' la scansione, e' il menu che tarda a
# comparire"). A flat Start-Sleep has to be long enough for the worst case, so it
# pays the worst case EVERY time, rounding a 200ms render up to the full 900ms.
#
# PollFor checks once immediately (the action already happened and already
# invalidated the walk), then sleeps a front-loaded schedule -- short waits first
# because the popup is usually quick, longer waits later for the settling case --
# stopping the moment $Check returns something truthy. The schedule's SUM equals
# the old fixed budget, so a genuinely slow popup is no worse off and the spike
# ceiling is unchanged; only the common case, which used to round up to the full
# wait, gets its time back. $Check is re-run against a freshly invalidated walk
# each time and hands its found element/count straight back to the caller.
#
# $Check reads the caller's locals (e.g. $before in OpenSubmenu): PollFor is
# invoked BY that caller, so PowerShell's dynamic scope lookup walks up into it.
function PollFor {
    param([scriptblock]$Check, [int[]]$Schedule)
    InvalidateWalk
    $r = & $Check
    if ($r) { return $r }
    foreach ($ms in $Schedule) {
        Start-Sleep -Milliseconds $ms
        InvalidateWalk
        $r = & $Check
        if ($r) { return $r }
    }
    return $r
}

# -- Pointer ------------------------------------------------------------------
# Some menu entries only respond to a real pointer. UIA gives us a clickable
# point in screen coordinates; the process is marked DPI aware at startup so
# those coordinates are not rescaled underneath us.
$MOUSE_LEFTDOWN = [uint32]0x0002
$MOUSE_LEFTUP   = [uint32]0x0004

function PointOf {
    param($e)
    try { return $e.GetClickablePoint() } catch {}
    try {
        $r = $e.Current.BoundingRectangle
        if ($r.Width -gt 0 -and $r.Height -gt 0) {
            return New-Object System.Windows.Point(($r.X + $r.Width / 2), ($r.Y + $r.Height / 2))
        }
    } catch {}
    throw "element has no clickable point"
}

# The pointer belongs to the user, not to us. Opening the "other models" submenu
# needs a real hover, so a plain capabilities call drags the cursor across the
# screen -- and the GUI is meant to call capabilities after every gear change.
# Left uncorrected that is a mouse yanked away several times a minute.
#
# The position is saved on the first move of a command and put back when the
# command ends (the finally in the dispatch loop), never between one move and the
# next: the submenu stays open only while the pointer rests on it, so restoring
# in between would close the very menu we are reading.
$script:savedCursor  = $null   # where the pointer was before we touched it
$script:lastSetPoint = $null   # where we last put it, to tell our move from the user's

function SaveCursor {
    if ($null -ne $script:savedCursor) { return }
    $pt = New-Object 'W+POINT'
    if ([W]::GetCursorPos([ref]$pt)) { $script:savedCursor = $pt }
}

function MoveCursor {
    param([int]$x, [int]$y)
    SaveCursor
    [W]::SetCursorPos($x, $y) | Out-Null
    $script:lastSetPoint = @{ X = $x; Y = $y }
}

# NOTE: the variable below is deliberately not called $home. PowerShell reserves
# $HOME (and matches variable names case-insensitively), so `$home = ...` fails
# as a non-terminating write error, leaves the name holding the profile path, and
# every read after it goes on with a string where a point should be -- which sent
# the pointer to 0,0 on every single command. Same family as $pid, avoided
# elsewhere in this file by calling the field $script:pid0.
function RestoreCursor {
    $origin = $script:savedCursor
    $last   = $script:lastSetPoint
    $script:savedCursor  = $null
    $script:lastSetPoint = $null
    if ($null -eq $origin) { return }

    # Put it back only if the pointer is still where we left it. If the user
    # grabbed the mouse while we were driving menus, theirs wins: yanking a
    # pointer somebody is actively using is worse than leaving ours behind.
    $now = New-Object 'W+POINT'
    if (-not [W]::GetCursorPos([ref]$now)) { return }
    if ($null -ne $last -and
        ([Math]::Abs($now.X - $last.X) -gt 4 -or [Math]::Abs($now.Y - $last.Y) -gt 4)) {
        Log "cursor left where it is: the user moved it"
        return
    }
    [W]::SetCursorPos([int]$origin.X, [int]$origin.Y) | Out-Null
    Log "cursor restored to $($origin.X),$($origin.Y)"
}

function HoverElement {
    param($e)
    $p = PointOf $e
    MoveCursor ([int]$p.X) ([int]$p.Y)
    Start-Sleep -Milliseconds 250
    # nudge, because some UI only reacts to actual movement
    MoveCursor ([int]$p.X + 2) ([int]$p.Y)
    Start-Sleep -Milliseconds 250
}

function ClickElement {
    param($e)
    $p = PointOf $e
    MoveCursor ([int]$p.X) ([int]$p.Y)
    Start-Sleep -Milliseconds 200
    [W]::mouse_event($MOUSE_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [W]::mouse_event($MOUSE_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 250
}
# Menu entries carry decoration the button label does not: a " <middot> Default"
# suffix on the settings default, and a trailing keyboard-shortcut digit
# ("Opus 4.8 2"). Strip both so a menu entry can be compared with the button.
#
# The shortcut digit is only stripped when a version number precedes it,
# otherwise "Sonnet 5" would lose its own 5.
function BareModel {
    param($s)
    # Take the model name from the front and drop whatever the menu appends:
    # a shortcut digit ("Opus 4.8 2"), a "requires usage credits" note, or the
    # " <middot> Default" marker. Anchoring at the start is safer than trying to
    # enumerate every possible suffix.
    if ($s -match '^\s*((?:Sonnet|Opus|Haiku|Fable)\s+[\d]+(?:\.[\d]+)?)') { return $Matches[1] }
    ($s -replace "\s*$([regex]::Escape($MIDDOT)).*$", '').Trim()
}

# -- Operations ---------------------------------------------------------------

# Diagnostic: every named element, as one newline-joined string. Returned as
# text rather than an array because ConvertTo-Json in PS 5.1 collapses
# single-element arrays into scalars.
function Op-Dump {
    $items = @(Walk |
        Where-Object { $_.Nm.Length -gt 0 } |
        ForEach-Object { "{0}`t{1}" -f $_.Ct, $_.Nm } |
        Sort-Object -Unique)
    @{ count = $items.Count; text = ($items -join "`n") }
}

# Diagnostic: indented tree with control type, name and AutomationId, so we can
# find structural (language-independent) anchors instead of matching labels.
function TreeLines {
    param($el, [int]$d, $acc)
    if ($acc.Count -ge 12000) { return }
    $aid = ''
    try { $aid = $el.Current.AutomationId } catch {}
    $acc.Add(("{0}{1}`t{2}`t{3}" -f ('  ' * $d), (Ct $el), (Nm $el), $aid))
    try {
        $ch = $script:walker.GetFirstChild($el)
        while ($null -ne $ch) {
            TreeLines $ch ($d + 1) $acc
            try   { $ch = $script:walker.GetNextSibling($ch) }
            catch { $ch = $null }
        }
    } catch {}
}

function Op-DumpTree {
    $lines = New-Object System.Collections.Generic.List[string]
    TreeLines $script:root 0 $lines
    @{ count = $lines.Count; text = ($lines -join "`n") }
}

# Open the effort popup and hand back its Slider.
#
# The popup renders a beat after Expand() returns, and elements grabbed too
# early go stale (their properties read back empty), so retry until the Slider
# actually materialises rather than trusting a fixed sleep.
#
# The open is attempted more than once. Seen live 2026-07-21 on Opus 4.8: one
# call in a long sequence came back empty while the model demonstrably had its
# 0-5 slider, and ten calls either side of it succeeded. A popup that refuses to
# open once is the same intermittent family as the "Altri modelli" submenu.
#
# Fail-fast-then-retry, not wait-then-retry. Measured live 2026-07-21 across 17
# capabilities calls (6 of them the instant after a model change): the slider,
# when it renders at all, renders in well under a second -- "effort popup ready
# (try 0)" every time, ~800ms. So a popup that is going to open opens fast; a
# long wait only ever sits on a STUCK one, and waiting does not unstick it -- the
# close+reopen at the top of the next try does. The old shape (2 tries x ~4s)
# therefore spent up to 8s doing nothing before the recovery that actually works,
# which is the bulk of the sporadic ~10s capabilities spike (the rest being
# listModels). Now: 3 tries with a ~1.3s budget each, so a stuck popup reaches
# its recovering reopen at ~1.3s instead of ~4s, worst case ~4s instead of ~8s,
# and one more recovery attempt than before. The common case is untouched --
# PollFor returns on the first truthy check, so a fast slider still comes back in
# ~800ms; only the budget that used to be burned on a stuck popup is shorter.
#
# An absent effort button is NOT retried: that is Haiku, a real state, not a
# failure to read.
function OpenEffortPopup {
    for ($try = 0; $try -lt 3; $try++) {
        ClosePopups
        $eb = EffortBtn
        if (-not $eb) { return $null }
        if (-not (Expand $eb)) { Log "effort popup: expand refused (try $try)"; continue }

        # The staleness guard stays: a slider grabbed too early reads its
        # properties back empty, so "found" is not enough -- it must answer a live
        # ControlType read too.
        $sl = PollFor {
            $s = SliderEl
            if ($s) { try { $null = $s.Current.ControlType; $s } catch { $false } } else { $false }
        } @(120, 180, 260, 360, 420)
        if ($sl) { Log "effort popup ready (try $try)"; return $sl }
        Log "effort popup: no slider after expand (try $try)"
    }
    return $null
}

function Op-EffortPopupTree {
    $sl = OpenEffortPopup
    if (-not $sl) { ClosePopups; throw "Effort popup did not produce a slider" }

    $info = ''
    try {
        $r = $sl.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
        $info = "min=$($r.Current.Minimum) max=$($r.Current.Maximum) value=$($r.Current.Value) step=$($r.Current.SmallChange)"
    } catch { $info = "no RangeValuePattern: $($_.Exception.Message)" }

    # climb to the popup container so we dump the menu, not the whole app
    $top = $sl
    for ($i = 0; $i -lt 6; $i++) {
        try { $p = $script:walker.GetParent($top) } catch { break }
        if (-not $p) { break }
        $top = $p
        if ((Ct $top) -eq 'Window') { break }
    }

    $lines = New-Object System.Collections.Generic.List[string]
    TreeLines $top 0 $lines
    ClosePopups
    @{ slider = $info; count = $lines.Count; text = ($lines -join "`n") }
}

# Diagnostic: open the model or effort popup and dump what appears, then close
# it. Tells us whether the effort level names are all readable at once (cheap)
# or only by moving the slider and reading the button back (a real change).
function Op-DumpOpen {
    param([string]$target)
    ClosePopups
    $btn = if ($target -eq 'model') { ModelBtn } else { EffortBtn }
    if (-not $btn) { throw "No $target button found" }

    $before = @{}
    foreach ($r in @(Walk)) { $before["$($r.Ct)|$($r.Nm)"] = $true }

    if (-not (Expand $btn)) { throw "Cannot expand $target popup" }
    Start-Sleep -Milliseconds 1000

    $appeared = New-Object System.Collections.Generic.List[string]
    foreach ($row in @(Walk)) {
        $key = "$($row.Ct)|$($row.Nm)"
        if (-not $before.ContainsKey($key)) {
            $extra = ''
            if ($row.Ct -eq 'Slider') {
                try {
                    $rv = $row.El.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
                    $extra = "  [min=$($rv.Current.Minimum) max=$($rv.Current.Maximum) value=$($rv.Current.Value)]"
                } catch {}
            }
            $appeared.Add(("{0}`t{1}`tenabled={2}{3}" -f $row.Ct, $row.Nm, (IsOn $row.El), $extra))
        }
    }

    ClosePopups
    @{ count = $appeared.Count; text = ($appeared -join "`n") }
}

function Op-Enumerate {
    $items = @(SessionEntries | ForEach-Object { "{0}`t{1}" -f $_.Title, $_.Status })
    @{ count = $items.Count; text = ($items -join "`n") }
}

function Op-ReadGear {
    $mb = ModelBtn
    if (-not $mb) { return $null }
    # Haiku exposes no effort control at all -- an absent button is a valid
    # state, not an error.
    $eb = EffortBtn
    $effort = if ($eb) { StripEffort (Nm $eb) } else { $null }
    @{ model = (Nm $mb); effort = $effort; hasEffort = ($null -ne $eb) }
}

# The Usage readout has more than one display format. Seen live on 2026-07-20,
# same machine, hours apart:
#   "Usage: context 14%, plan 32%"      (percentage)
#   "Usage: context 127.5k, plan 41%"   (absolute tokens)
# Parse whichever is there and always return the raw text: the dashboard must
# not go blind because the readout flipped into its other format. Returns $null
# only when the button itself is missing.
function Op-ReadUsage {
    $ub = UsageBtn
    if (-not $ub) { return $null }
    $text = Nm $ub

    $ctxPct = $null; $ctxTok = $null; $planPct = $null
    if     ($text -match 'context\s+([\d\.,]+)\s*%')    { $ctxPct = [int][double]($Matches[1] -replace ',','.') }
    elseif ($text -match 'context\s+([\d\.,]+)\s*[kK]') { $ctxTok = [int]([double]($Matches[1] -replace ',','.') * 1000) }
    elseif ($text -match 'context\s+(\d+)\b')           { $ctxTok = [int]$Matches[1] }
    if     ($text -match 'plan\s+([\d\.,]+)\s*%')       { $planPct = [int][double]($Matches[1] -replace ',','.') }

    @{ contextPct = $ctxPct; contextTokens = $ctxTok; planPct = $planPct; raw = $text }
}

function Op-SelectSession {
    param([string]$name)
    $entry = SessionEntries | Where-Object { $_.Title -eq $name } | Select-Object -First 1
    if (-not $entry) {
        $seen = ((SessionEntries | ForEach-Object { $_.Title }) -join ', ')
        throw "Session not found: '$name' (sidebar has: $seen)"
    }
    $entry.Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Milliseconds 900
    InvalidateWalk
    @{ title = $entry.Title }
}

# Match a model option by full name. Family-only matching is unsafe: "Sonnet"
# matches both "Sonnet 5" and "Sonnet 4.6".
function FindModelOption {
    param([string]$alias)
    $want = BareModel $alias
    # An empty target turns the prefix match below into "*", which matches every
    # entry and hands back the first one in the menu. That is how a setModel with
    # a missing name silently engaged Fable 5 -- and the verification afterwards
    # passed, because the button really did read Fable 5. No name, no match.
    if ([string]::IsNullOrWhiteSpace($want)) { return $null }
    $opts = @(ModelOptionRows)
    $exact = $opts | Where-Object { (BareModel $_.Nm) -eq $want } | Select-Object -First 1
    if ($exact) { return $exact.El }
    Row2El ($opts | Where-Object { (BareModel $_.Nm) -like "$want*" } | Select-Object -First 1)
}

# Open the model menu and wait for it to render.
function OpenModelPopup {
    ClosePopups
    $mb = ModelBtn
    if (-not $mb) { return $false }
    if (-not (Expand $mb)) { return $false }
    # Front-loaded poll, same ~3.2s budget as the old 8x400 loop.
    $ok = PollFor {
        if (@(ModelOptionRows).Count -gt 0) { $true } else { $false }
    } @(80, 120, 180, 260, 360, 500, 700, 1000)
    return [bool]$ok
}

# Three models (Opus 4.7, Opus 4.6, Sonnet 4.6) live behind an "Altri modelli"
# submenu, so a single pass over the menu misses them. Open any expandable entry
# that is not itself a model, then let the caller re-enumerate.
#
# Identifying the submenu by shape rather than by its label keeps this working
# in any language.
# SAFETY: a menu holds more than submenus. This model menu also carries a
# "fast mode" toggle, and blindly invoking non-model entries to see what
# happens flipped that setting on a live app. Only entries that advertise
# ExpandCollapse are submenus; nothing else is ever actuated here.
function IsSubmenuRow {
    param($row)
    try {
        $null = $row.El.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
        return $true
    } catch { return $false }
}

# Judge success by whether more model options actually appeared, not by whether
# the call returned without error: ExpandCollapse reports success on this
# MenuItem while doing nothing, because the submenu is pointer driven.
#
# Order matters for speed. This submenu is pointer driven on the live app, so
# ExpandCollapse has NEVER opened it here -- it returns success while adding
# nothing, and every attempt costs a fixed 900ms wait that yields "4 -> 4". It
# is the physical hover that brings the three hidden models home, every time.
# So hover goes first and ExpandCollapse drops to a fallback: on this machine
# that saves ~900ms per capabilities (which always expands the submenu to list
# all seven models), and it costs nothing where hover works. ExpandCollapse is
# kept as a fallback rather than removed: on a headless or mouseless host where
# hover cannot land, it may be the only handle -- the ordering is a speed
# choice, not a claim that ExpandCollapse is useless everywhere.
function OpenSubmenu {
    param($row)
    $before = @(ModelOptionRows).Count

    $tries = @(
        @{ name = 'hover';  act = { HoverElement $row.El } },
        @{ name = 'ExpandCollapse'; act = {
            $row.El.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand() } },
        @{ name = 'click';  act = { ClickElement $row.El } }
    )

    foreach ($t in $tries) {
        try { & $t.act } catch { Log "  submenu $($t.name) threw: $($_.Exception.Message)"; continue }
        # Poll instead of a flat 900ms. This runs on EVERY capabilities call (the
        # command always expands the submenu to list all seven models), and the
        # submenu usually lands well under 900ms, so the flat wait was the single
        # biggest recurring waste in capabilities. Same 900ms budget for the case
        # where it does lag; the exotic "4 -> 0" (popup vanishes, sess. 8) still
        # times out to a $false the same way, because the count never exceeds
        # $before.
        $after = PollFor {
            $c = @(ModelOptionRows).Count
            if ($c -gt $before) { $c } else { $false }
        } @(120, 180, 250, 350)
        if ($after) {
            Log "  submenu opened by $($t.name): $before -> $after options"
            return $true
        }
        $now = @(ModelOptionRows).Count
        Log "  submenu $($t.name) did not add options ($before -> $now)"
    }
    return $false
}

# Candidates are MenuItem ONLY, never ListItem. Verified live 2026-07-20: the
# menu renders as Menu/MenuItem/RadioButton, while the conversation transcript
# renders its markdown bullets as ListItem -- and those precede the menu in
# document order, so a ListItem-tolerant finder picks up chat text as if it
# were a menu entry.
# Returns @{ opened; failed }, not a bare count: a submenu marker that was
# found but never actually expanded (sess. 8: "4 -> 0", the whole popup
# sometimes disappears instead of the submenu opening, cause unknown, not
# reproducible on demand) is a different situation from no marker existing at
# all. Callers need to tell "nothing to open" from "something failed to open"
# so they know whether retrying from a fresh popup is worth doing.
function ExpandModelSubmenus {
    $opened = 0
    $failed = 0
    $seen   = New-Object System.Collections.Generic.List[string]
    for ($pass = 0; $pass -lt 4; $pass++) {
        $cand = @(Walk | Where-Object {
            $_.Ct -eq 'MenuItem' -and $_.Nm -and $_.Nm -notmatch $RX_MODEL
        } | Where-Object { -not $seen.Contains($_.Nm) -and (IsSubmenuRow $_) })

        if ($cand.Count -eq 0) { break }
        $r = $cand[0]
        $seen.Add($r.Nm)
        Log "trying submenu '$($r.Nm)'"
        if (OpenSubmenu $r) { $opened++ } else { $failed++ }
    }
    return @{ opened = $opened; failed = $failed }
}

# A submenu that fails to expand does not make ModelOptionRows empty -- the
# top-level 4 are still there -- so the old single-pass version returned a
# plausible-looking but short list (4 instead of 7) with no error anywhere,
# the same trap already closed for effort ("gears: 0, errors empty"). Retry
# once from a fresh popup when a submenu marker was seen but did not expand;
# report what actually came back either way rather than pretending success.
function Op-ListModels {
    $expand = $null
    for ($try = 0; $try -lt 2; $try++) {
        if (-not (OpenModelPopup)) { ClosePopups; throw "Model menu did not open" }
        $expand = ExpandModelSubmenus
        if ($expand.failed -eq 0) { break }
        Log "listModels: submenu failed to expand on try $try, retrying from a fresh popup"
    }

    $result = @(ModelOptionRows | ForEach-Object {
        @{ name = $_.Nm; label = (BareModel $_.Nm); enabled = (IsOn $_.El); selected = (IsSel $_.El) }
    })
    ClosePopups
    if ($result.Count -eq 0) { throw "Model menu opened but no options found" }
    return $result
}

# Diagnostic: open the model menu, open its submenu, and list every menu-ish
# element in the whole window. Listing from the window root rather than from
# the menu subtree matters: a submenu can render as a sibling popup, which a
# subtree dump would miss entirely.
# The model menu also carries a "fast mode" switch. We never touch it during
# normal operation; this exists only to read its state and to put it back if
# something flipped it.
function Op-FastMode {
    param($set)   # $null = just read, otherwise $true/$false
    if (-not (OpenModelPopup)) { ClosePopups; throw "Model menu did not open" }

    $menu = Walk | Where-Object { $_.Ct -eq 'Menu' -and $_.Nm } | Select-Object -First 1
    $title = if ($menu) { $menu.Nm } else { '' }

    # MenuItem only -- a ListItem here is chat content, not a menu entry (see
    # the note on ExpandModelSubmenus: this finder once returned the text of a
    # conversation message as "the toggle").
    $toggle = Walk | Where-Object {
        $_.Ct -eq 'MenuItem' -and $_.Nm -and $_.Nm -notmatch $RX_MODEL -and -not (IsSubmenuRow $_)
    } | Select-Object -First 1

    $state = $null
    if ($toggle) {
        try { $state = [string]$toggle.El.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState } catch {}
    }

    $r = @{
        menuTitle  = $title
        toggleName = if ($toggle) { $toggle.Nm } else { $null }
        toggleState = $state
        changed    = $false
    }

    # Refuse to actuate blind. Asking for on/off when the entry is missing
    # (models without fast mode do not show it) or its state is unreadable
    # would mean toggling on a guess: with unknown state, "turn it on" can
    # just as easily turn it off while claiming success. Reading stays fine.
    if ($null -ne $set -and -not $toggle) {
        ClosePopups
        throw "fast mode: no toggle in this model's menu (read-only still works)"
    }
    if ($null -ne $set -and $null -eq $state) {
        ClosePopups
        throw "fast mode: toggle state unreadable, refusing to actuate blind"
    }

    if ($null -ne $set -and $toggle) {
        $isOn = ($state -eq 'On')
        if ($isOn -ne [bool]$set) {
            Log "fast mode: $state -> requested $set, actuating"
            try { $toggle.El.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle() }
            catch { ClickElement $toggle.El }
            Start-Sleep -Milliseconds 800
            InvalidateWalk
            $r.changed = $true
            $m2 = Walk | Where-Object { $_.Ct -eq 'Menu' -and $_.Nm } | Select-Object -First 1
            $t2 = Walk | Where-Object {
                $_.Ct -eq 'MenuItem' -and $_.Nm -and $_.Nm -notmatch $RX_MODEL -and -not (IsSubmenuRow $_)
            } | Select-Object -First 1
            $r.menuTitleAfter = if ($m2) { $m2.Nm } else { '' }
            if ($t2) {
                try { $r.toggleStateAfter = [string]$t2.El.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState } catch {}
            }
        } else {
            Log "fast mode already $state, nothing to do"
        }
    }

    ClosePopups
    return $r
}

function Op-ModelPopupTree {
    if (-not (OpenModelPopup)) { ClosePopups; throw "Model menu did not open" }
    $n = ExpandModelSubmenus

    $rows = @(Walk | Where-Object {
        $_.Ct -match 'RadioButton|MenuItem|ListItem|Menu' -and $_.Nm
    } | ForEach-Object {
        "{0}`t{1}`tenabled={2}" -f $_.Ct, $_.Nm, (IsOn $_.El)
    })

    ClosePopups
    @{ submenusOpened = $n.opened; submenusFailed = $n.failed; count = $rows.Count; text = ($rows -join "`n") }
}

# Read the effort range without touching it. Cheap and non-destructive: this is
# what the GUI needs to know how many detents to draw.
#
# `hasControl` separates the two reasons an effort answer comes back empty, so a
# caller never has to match on the prose of `reason`. A model without the control
# (Haiku) is a finding: the ladder really has no rungs, and the lever must be
# drawn without its splitter. A model whose control is present but would not open
# is a failure to read. A caller that cannot tell them apart either treats Haiku
# as permanently broken or records "no effort" for a model that has one.
function Op-EffortRange {
    $sl = OpenEffortPopup
    if (-not $sl) {
        ClosePopups
        if (-not (EffortBtn)) { return @{ available = $false; hasControl = $false; reason = 'model has no effort control' } }
        return @{ available = $false; hasControl = $true; reason = 'effort popup did not open' }
    }
    try {
        $rv = $sl.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
        $r  = @{
            available = $true
            min       = [int]$rv.Current.Minimum
            max       = [int]$rv.Current.Maximum
            current   = [int]$rv.Current.Value
            label     = (StripEffort (Nm (EffortBtn)))
        }
        ClosePopups
        return $r
    } catch {
        ClosePopups
        throw
    }
}

# Sweep the effort slider through every position, recording the button label at
# each. This is the only way to learn the level names: the popup shows just the
# slider and its two end captions, never the six names. Restores the original
# position before returning.
function Op-ProbeEffort {
    $sl = OpenEffortPopup
    if (-not $sl) {
        ClosePopups
        # See Op-EffortRange for why `hasControl` travels alongside `reason`.
        if (-not (EffortBtn)) { return @{ available = $false; hasControl = $false; reason = 'model has no effort control' } }
        return @{ available = $false; hasControl = $true; reason = 'effort popup did not open' }
    }

    $rv       = $sl.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
    $min      = [int]$rv.Current.Minimum
    $max      = [int]$rv.Current.Maximum
    $original = [int]$rv.Current.Value
    Log "effort slider: min=$min max=$max current=$original"

    $positions = @()
    for ($v = $min; $v -le $max; $v++) {
        $p = SetSliderTo $v
        $positions += $p
    }

    $rest = SetSliderTo $original
    ClosePopups

    # The restore check must compare with what the sweep itself read at the
    # original position: "some label came back" is not a verification (same
    # trap as the IsAlive check fixed in session 6).
    $wanted = ($positions | Where-Object { $_.value -eq $original } | Select-Object -First 1).label

    @{
        available = $true; min = $min; max = $max
        original  = $original
        restored  = $rest.label
        expected  = $wanted
        restoredOk = (-not $rest.error -and $null -ne $wanted -and $rest.label -eq $wanted)
        positions = $positions
    }
}

# Move the slider to one position and read the resulting label. Reopens the
# popup if it dismissed itself between steps, which it sometimes does.
function SetSliderTo {
    param([int]$v)
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        $slNow = SliderEl
        if (-not $slNow) {
            Log "  slider gone before pos $v - reopening"
            $slNow = OpenEffortPopup
            if (-not $slNow) { continue }
        }
        try {
            $slNow.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).SetValue([double]$v)
            Start-Sleep -Milliseconds 700
            InvalidateWalk
            $label = StripEffort (Nm (EffortBtn))
            Log "  pos $v -> '$label'"
            return @{ value = $v; label = $label }
        } catch {
            Log "  pos $v attempt $attempt failed: $($_.Exception.Message)"
        }
    }
    return @{ value = $v; label = $null; error = 'could not set slider' }
}

# Everything the GUI needs to draw the lever, in one round trip: which models
# the app offers right now, which one is engaged, and how many detents the
# engaged model's ladder has.
#
# Why one command instead of letting the GUI call readGear + listModels +
# effortRange itself: each of those opens and closes a popup, so three calls
# cost three popup cycles and can interleave with the user's own clicking. And a
# frontend that has to ask three questions is tempted to cache the answers and
# hardcode a grid -- which is exactly what section 4.1 of PROJECT.md forbids.
#
# It reports the ladder of the CURRENT model only, never a table of all of them.
# The GUI is meant to call this again after every setModel and redraw. A full
# table would mean switching model seven times to build it, and it would be a
# declaration -- the thing the broker must not do.
#
# Partial failure is reported per section rather than failing the whole command:
# a GUI that got the model list but not the effort range can still draw
# something honest, whereas an error leaves it with nothing to draw at all.
function Op-Capabilities {
    $errors = New-Object System.Collections.Generic.List[string]

    # Per-section timing on stderr. The ~10s spike after a model change had no
    # named cause (sess. 14) because nothing recorded WHERE the time went. This
    # does not slow anything down -- one Stopwatch, four Log lines -- and turns
    # the next spike into a log that points straight at the slow section instead
    # of a shrug. Reads as e.g. "capabilities: listModels at 2100ms".
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $gear = $null
    try { $gear = Op-ReadGear } catch { $errors.Add("readGear: $($_.Exception.Message)") }
    Log "capabilities: readGear at $($sw.ElapsedMilliseconds)ms"
    # Without the model button there is no lever at all, and every section below
    # depends on it. This one is fatal.
    if ($null -eq $gear) { throw "capabilities: model button not found (is a conversation open?)" }

    $models = @()
    try { $models = @(Op-ListModels) } catch { $errors.Add("listModels: $($_.Exception.Message)") }
    Log "capabilities: listModels at $($sw.ElapsedMilliseconds)ms"

    if ($gear.hasEffort) {
        # The button is there, so the control exists whether or not the read works:
        # hasControl stays true and this stays a failure, never a "no effort" claim.
        $effort = @{ available = $false; hasControl = $true; reason = 'effortRange failed' }
        try { $effort = Op-EffortRange } catch { $errors.Add("effortRange: $($_.Exception.Message)") }

        # A failed effort read does not throw -- Op-EffortRange answers politely
        # with available=$false -- so without this line the failure travelled the
        # success path and `errors` came back EMPTY while `gears` came back 0.
        # Seen live 2026-07-21 on Opus 4.8, which has six gears: a GUI trusting
        # `gears` would have drawn Haiku's splitterless lever on a model that has
        # a splitter. We only get here when the button exists, so anything short
        # of a reading is a failure, never a "this model has no ladder" claim.
        if (-not $effort.available) {
            $errors.Add("effortRange: $($effort.reason) (il modello HA il cursore: marce non lette, non assenti)")
        }
    } else {
        # Haiku. Not an error: an absent ladder is a real state the GUI must
        # render (the lever loses its splitter).
        $effort = @{ available = $false; hasControl = $false; reason = 'model has no effort control' }
    }
    Log "capabilities: effortRange at $($sw.ElapsedMilliseconds)ms"

    $usage = $null
    try { $usage = Op-ReadUsage } catch { $errors.Add("readUsage: $($_.Exception.Message)") }
    # A missing or unreadable dashboard must show up in `errors`, not slip
    # through as a silent null: the per-section failure report is the whole
    # point of this command, and this section was the one failing in practice.
    if ($null -eq $usage) {
        $errors.Add('readUsage: usage button not found')
    } elseif ($null -eq $usage.contextPct -and $null -eq $usage.contextTokens) {
        $errors.Add("readUsage: unrecognised format: '$($usage.raw)'")
    }

    # Detent count, not slider span: 0..5 is six gears. The GUI draws this many
    # positions and nothing more.
    #
    # WARNING for the caller: gears=0 alone does NOT mean "this model has no
    # ladder". It also comes out 0 when the ladder could not be read. The two are
    # told apart by `effortRange.hasControl` ($false = really absent, $true = not
    # read), and a failed read is always listed in `errors`. Never draw the lever
    # from `gears` without looking at one of those two.
    $gears = 0
    if ($effort.available) { $gears = [int]$effort.max - [int]$effort.min + 1 }

    Log "capabilities: total $($sw.ElapsedMilliseconds)ms"
    @{
        model       = $gear.model
        effort      = $gear.effort
        hasEffort   = [bool]$gear.hasEffort
        gears       = $gears
        effortRange = $effort
        models      = $models
        usage       = $usage
        errors      = @($errors)
    }
}

function Op-SetModel {
    param([string]$alias)
    # Refuse before opening anything. A caller that lost the name is a caller
    # that does not know which gear it wants, and guessing one is the worst
    # possible answer -- see FindModelOption.
    if ([string]::IsNullOrWhiteSpace($alias)) { throw "setModel: no model name given" }

    # The "Altri modelli" submenu occasionally does not expand and instead
    # takes the whole popup down with it (sess. 8: "4 -> 0", cause unknown,
    # not reproducible on demand). A single-pass setModel could not tell that
    # apart from the model genuinely not existing, and said so -- "Model
    # option not found" for a model that was real. Retry the whole
    # open-popup-then-expand sequence once from scratch before believing that,
    # same shape as OpenEffortPopup's retry for the same family of popup
    # flakiness.
    $target = $null
    $opened = $false
    for ($try = 0; $try -lt 2 -and -not $target; $try++) {
        if (-not (OpenModelPopup)) { ClosePopups; continue }
        $opened = $true

        $target = FindModelOption $alias
        if (-not $target) {
            # not on the top level, so it must be behind the "other models" submenu
            $null = ExpandModelSubmenus
            $target = FindModelOption $alias
        }
        if (-not $target) { Log "setModel: '$alias' not found on try $try, retrying from a fresh popup" }
    }
    if (-not $opened) { ClosePopups; throw "Model menu did not open" }
    if (-not $target) {
        $seen = (@(ModelOptions) | ForEach-Object { BareModel (Nm $_) }) -join ', '
        ClosePopups
        throw "Model option not found: '$alias' (menu offers: $seen)"
    }
    if (-not (IsOn $target)) {
        $n = Nm $target
        ClosePopups
        throw "Model option disabled: $n"
    }

    $chosen = Nm $target
    try   { $target.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }
    catch { $target.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
    Start-Sleep -Seconds 1
    InvalidateWalk

    # Verification is mandatory -- never report a shift we have not read back.
    $result = Nm (ModelBtn)
    if (-not $result) { throw "Model button gone after set" }
    if ((BareModel $result) -ne (BareModel $chosen)) {
        throw "Model verify failed: wanted '$(BareModel $chosen)', button reads '$result'"
    }
    return $result
}

function Op-SetEffort {
    param([int]$level)
    ClosePopups
    $eb = EffortBtn
    if (-not $eb) { throw "This model has no effort control" }
    if (-not (Expand $eb)) { throw "Cannot expand effort popup" }
    Start-Sleep -Milliseconds 900

    $sl = SliderEl
    if (-not $sl) { ClosePopups; throw "Effort slider not found" }
    $rv  = $sl.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
    $min = [int]$rv.Current.Minimum
    $max = [int]$rv.Current.Maximum
    Log "slider range: min=$min max=$max now=$($rv.Current.Value)"

    # The ladder shrinks for lesser models -- refuse out of range rather than
    # silently clamping to something the user did not ask for.
    if ($level -lt $min -or $level -gt $max) {
        ClosePopups
        throw "Effort level $level out of range for this model (allowed $min..$max)"
    }

    $rv.SetValue([double]$level)
    Start-Sleep -Milliseconds 1000
    InvalidateWalk
    $label = StripEffort (Nm (EffortBtn))

    # Verification is mandatory here too: SetValue can fail without throwing,
    # and reporting ok with the old label inside is a shift never verified.
    # Read the slider position back. The popup sometimes dismisses itself right
    # after SetValue, so a failed read is reopened once rather than mistaking a
    # vanished popup for a failed shift.
    $now = $null
    try { $now = [int]$rv.Current.Value } catch {}
    if ($null -eq $now) {
        $sl2 = OpenEffortPopup
        if ($sl2) {
            try { $now = [int]$sl2.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).Current.Value } catch {}
        }
        InvalidateWalk
        $label = StripEffort (Nm (EffortBtn))
    }
    ClosePopups

    if ($now -ne $level) {
        $shown = if ($null -eq $now) { 'unreadable' } else { $now }
        throw "Effort verify failed: asked for $level, slider reads $shown (label '$label')"
    }
    @{ effort = $label; min = $min; max = $max }
}

# -- Main ---------------------------------------------------------------------
Log "UIA Broker starting"
try { [W]::SetProcessDPIAware() | Out-Null } catch {}
$attached = Attach

if ($attached) {
    Send @{ event = 'attached'; pid = [int]$script:pid0 }
    Log "Attached to Claude pid=$($script:pid0)"
} else {
    Send @{ event = 'error'; message = 'Claude Desktop not found or a11y did not wake' }
    Log "Attach failed"
}

while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { Log "stdin closed - exiting"; break }
    $line = $line.Trim()
    if ($line -eq '') { continue }

    try   { $req = $line | ConvertFrom-Json }
    catch { Log "Bad JSON: $line"; continue }

    $id  = if ($req.PSObject.Properties['id'])  { [int]$req.id }    else { 0 }
    $cmd = if ($req.PSObject.Properties['cmd']) { [string]$req.cmd } else { '' }

    # never answer a command from a snapshot taken during the previous one
    InvalidateWalk
    Log "-> $cmd (id=$id)"

    # The app may have been closed and reopened since the last command. Rebind
    # before touching anything, rather than failing with a UIA error that says
    # nothing about the real cause.
    if (-not (EnsureAttached)) {
        Reply-Err $id "Claude Desktop is not running - reopen it and retry"
        continue
    }

    try {
        switch ($cmd) {
            'enumerate' {
                Reply-Ok $id (Op-Enumerate)
            }
            'dump' {
                Reply-Ok $id (Op-Dump)
            }
            'dumpTree' {
                Reply-Ok $id (Op-DumpTree)
            }
            'dumpOpen' {
                Reply-Ok $id (Op-DumpOpen $req.target)
            }
            'effortPopupTree' {
                Reply-Ok $id (Op-EffortPopupTree)
            }
            'modelPopupTree' {
                Reply-Ok $id (Op-ModelPopupTree)
            }
            'fastMode' {
                $set = if ($req.PSObject.Properties['set']) { [bool]$req.set } else { $null }
                Reply-Ok $id (Op-FastMode $set)
            }
            'readGear' {
                $g = Op-ReadGear
                if ($null -eq $g) { Reply-Err $id 'readGear: elements not found' }
                else { Reply-Ok $id $g }
            }
            'readUsage' {
                $u = Op-ReadUsage
                if ($null -eq $u) { Reply-Err $id 'readUsage: usage button not found' }
                else { Reply-Ok $id $u }
            }
            'selectSession' {
                # Capture the result. An uncaptured Op-SelectSession leaks its
                # @{ title = ... } hashtable to stdout, where PowerShell renders
                # it as a formatted table -- non-JSON lines dropped in the middle
                # of the NDJSON protocol (seen live). And replying $null broke
                # principle 7: the target must be confirmed, not deduced. Now the
                # client learns which session was actually selected.
                $sel = Op-SelectSession ([string](ReqArg $req 'name'))
                Reply-Ok $id $sel
            }
            'setModel' {
                Reply-Ok $id @{ model = (Op-SetModel ([string](ReqArg $req 'model'))) }
            }
            'setEffort' {
                # Not just "is it there": a level that is not a whole number is
                # as unusable as a missing one, and [int] on junk either throws
                # somewhere less obvious or rounds to a gear nobody asked for.
                $raw = ReqArg $req 'level'
                $lvl = 0
                if (-not [int]::TryParse([string]$raw, [ref]$lvl)) {
                    throw "setEffort: 'level' is not a whole number: '$raw'"
                }
                Reply-Ok $id (Op-SetEffort $lvl)
            }
            'listModels' {
                Reply-Ok $id @{ models = (Op-ListModels) }
            }
            'probeEffort' {
                $r = Op-ProbeEffort
                if ($r.available) {
                    $r.positions = @($r.positions | ForEach-Object { "{0}`t{1}" -f $_.value, $_.label }) -join "`n"
                }
                Reply-Ok $id $r
            }
            'effortRange' {
                Reply-Ok $id (Op-EffortRange)
            }
            'capabilities' {
                Reply-Ok $id (Op-Capabilities)
            }
            # Diagnostic: throw away the binding so the NEXT command has to
            # rebuild it. Exists because the honest test -- closing Claude
            # Desktop -- also closes whatever is driving the broker when the two
            # are the same app. This exercises the expensive half of the
            # recovery (find the window again, wake its a11y tree, re-emit the
            # event); the cheap half, noticing the window died, is the three
            # checks in IsAlive.
            'forceDetach' {
                $script:root = $null
                $script:hwnd = [IntPtr]::Zero
                InvalidateWalk
                Log "forceDetach: binding dropped on purpose"
                Reply-Ok $id @{ detached = $true; wasPid = [int]$script:pid0 }
            }
            default {
                Reply-Err $id "Unknown command: $cmd"
            }
        }
    } catch {
        $msg = $_.Exception.Message
        Log "Error in $cmd : $msg"
        Reply-Err $id $msg
    } finally {
        # Every exit from a command, including the failed ones: an operation that
        # threw halfway through a menu is exactly when the pointer is left
        # stranded somewhere the user did not put it.
        RestoreCursor
    }
}
