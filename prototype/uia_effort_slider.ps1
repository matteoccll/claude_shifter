Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
$sig=@"
using System;using System.Text;using System.Runtime.InteropServices;using System.Collections.Generic;
public class W{
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb,IntPtr l);
 public delegate bool EnumProc(IntPtr h,IntPtr l);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
 public static List<IntPtr> WinsFor(uint pid){ var r=new List<IntPtr>(); EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid && GetWindowTextLength(h)>0){ r.Add(h);} return true;},IntPtr.Zero); return r; }
}
"@
Add-Type -TypeDefinition $sig -ReferencedAssemblies System.Windows.Forms
Start-Process "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"; Start-Sleep -Seconds 2
$p=Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" | Where-Object { $_.CommandLine -match 'WindowsApps' -and $_.CommandLine -notmatch '--type' } | Select-Object -First 1
$hwnd=([W]::WinsFor([uint32]$p.ProcessId))[0]
[W]::ShowWindow($hwnd,9)|Out-Null; [W]::SetForegroundWindow($hwnd)|Out-Null; Start-Sleep -Seconds 1
$A=[System.Windows.Automation.AutomationElement]
$walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
$root=$A::FromHandle($hwnd)
function All(){ $l=New-Object System.Collections.Generic.List[object]; $s=New-Object System.Collections.Stack; $s.Push($root); $n=0
  while($s.Count -gt 0 -and $n -lt 12000){ $c=$s.Pop(); $n++; $l.Add($c); try{$k=$walker.GetFirstChild($c)}catch{$k=$null}; while($k -ne $null){ $s.Push($k); try{$k=$walker.GetNextSibling($k)}catch{$k=$null} } }; return $l }
function CT($e){ try{($e.Current.ControlType.ProgrammaticName -replace 'ControlType.','')}catch{''} }
function NM($e){ try{$e.Current.Name}catch{''} }
function EB(){ All|Where-Object{(CT $_)-eq 'Button' -and (NM $_)-match '^Effort'}|Select-Object -First 1 }
function Slider(){ All|Where-Object{(CT $_)-eq 'Slider'}|Select-Object -First 1 }
function Expand($e){ try{$e.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand();return $true}catch{return $false} }
$null=All; Start-Sleep -Seconds 2

Write-Output "effort button start: '$(NM (EB))'"
Expand (EB) | Out-Null; Start-Sleep -Seconds 1
$sl=Slider
if(-not $sl){ Write-Output "no slider found"; exit 1 }
$rv=$sl.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern)
$min=$rv.Current.Minimum; $max=$rv.Current.Maximum; $val=$rv.Current.Value; $sc=$rv.Current.SmallChange
Write-Output "slider: min=$min max=$max value=$val small=$sc"

# step DOWN one notch (toward Faster), read label, then restore
$target = [Math]::Max($min, $val - $(if($sc -gt 0){$sc}else{1}))
Write-Output "setting slider -> $target"
$rv.SetValue($target); Start-Sleep -Seconds 2
Write-Output "effort button after change: '$(NM (EB))'"

# restore
$sl2=Slider; if($sl2){ $sl2.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).SetValue($val); Start-Sleep -Seconds 2 }
Write-Output "effort button after restore: '$(NM (EB))'"
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")

# enumerate the discrete effort labels by sweeping (read-only report of range)
Write-Output "`n(one notch changed the label => effort slider is drivable via RangeValuePattern)"