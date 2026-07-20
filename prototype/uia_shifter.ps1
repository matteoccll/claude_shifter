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
 [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
 public static List<IntPtr> WinsFor(uint pid){ var r=new List<IntPtr>(); EnumWindows((h,l)=>{ uint p; GetWindowThreadProcessId(h,out p); if(p==pid && GetWindowTextLength(h)>0){ r.Add(h);} return true;},IntPtr.Zero); return r; }
}
"@
Add-Type -TypeDefinition $sig -ReferencedAssemblies System.Windows.Forms

# bring existing instance to front
Start-Process "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"; Start-Sleep -Seconds 3
$p=Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" | Where-Object { $_.CommandLine -match 'WindowsApps' -and $_.CommandLine -notmatch '--type' } | Select-Object -First 1
$pid0=[uint32]$p.ProcessId
$wins=[W]::WinsFor($pid0)
Write-Output "pid=$pid0 titled-windows=$($wins.Count)"
if($wins.Count -eq 0){ Write-Output "no window"; exit 1 }
$hwnd=$wins[0]
[W]::ShowWindow($hwnd,9)|Out-Null; [W]::SetForegroundWindow($hwnd)|Out-Null; Start-Sleep -Seconds 1
$A=[System.Windows.Automation.AutomationElement]
$walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
$root=$A::FromHandle($hwnd)

function All(){ $l=New-Object System.Collections.Generic.List[object]; $s=New-Object System.Collections.Stack; $s.Push($root); $n=0
  while($s.Count -gt 0 -and $n -lt 12000){ $c=$s.Pop(); $n++; $l.Add($c); try{ $k=$walker.GetFirstChild($c) }catch{$k=$null}; while($k -ne $null){ $s.Push($k); try{$k=$walker.GetNextSibling($k)}catch{$k=$null} } }; return $l }
function CT($e){ try{($e.Current.ControlType.ProgrammaticName -replace 'ControlType.','')}catch{''} }
function NM($e){ try{$e.Current.Name}catch{''} }
function MB(){ All|Where-Object{(CT $_)-eq 'Button' -and (NM $_)-match '^(Sonnet|Opus|Haiku|Fable)\b'}|Select-Object -First 1 }
function EB(){ All|Where-Object{(CT $_)-eq 'Button' -and (NM $_)-match '^Effort'}|Select-Object -First 1 }
function Expand($e){ if(-not $e){return $false}; try{$e.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand();return $true}catch{return $false} }
function Pick($re){ $it=All|Where-Object{(CT $_)-match 'RadioButton|MenuItem' -and (NM $_)-match $re}|Select-Object -First 1; if(-not $it){return "NF:$re"}; try{$it.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select();return "sel:'$($it.Current.Name)'"}catch{try{$it.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke();return "inv:'$($it.Current.Name)'"}catch{return "FAIL:$($_.Exception.Message)"}} }

# WAKE a11y (persistent: this process stays attached the whole time)
$named=0; for($i=0;$i -lt 8;$i++){ $named=(All|Where-Object{NM $_}).Count; Write-Output ("wake try {0}: named={1}" -f $i,$named); if($named -gt 40){break}; Start-Sleep -Seconds 2 }
if($named -le 40){ Write-Output "a11y did not wake"; exit 1 }

Write-Output "`n=== CURRENT: model='$(NM (MB))'  effort='$(NM (EB))' ==="

Write-Output "`n=== SESSION SIDEBAR (named buttons, deduped) ==="
(All|Where-Object{(CT $_)-eq 'Button' -and (NM $_)}|ForEach-Object{NM $_}|Sort-Object -Unique)|ForEach-Object{Write-Output "  $_"}

Write-Output "`n=== EFFORT ROUND-TRIP ==="
$eb0=NM (EB); Write-Output "effort before='$eb0'"
if(Expand (EB)){ Start-Sleep -Seconds 1
  Write-Output "effort menu:"; (All|Where-Object{(CT $_)-match 'RadioButton|MenuItem'}|ForEach-Object{"  {0} '{1}'" -f (CT $_),(NM $_)}|Sort-Object -Unique)|ForEach-Object{Write-Output $_}
  # pick a different level then revert
  $target = if($eb0 -match 'High'){'Low|Medium'} else {'High'}
  Write-Output ("  ->change: "+(Pick $target)); Start-Sleep -Seconds 2
  $eb1=NM (EB); Write-Output "effort mid='$eb1'"
  if(Expand (EB)){ Start-Sleep -Seconds 1; Write-Output ("  ->revert: "+(Pick ([regex]::Escape(($eb0 -replace '^Effort:\s*',''))))); Start-Sleep -Seconds 2 }
  $eb2=NM (EB); Write-Output "effort after='$eb2'  REVERTED=$($eb2 -eq $eb0)"
}

Write-Output "`n=== MODEL ROUND-TRIP ==="
$mb0=NM (MB); Write-Output "model before='$mb0'"
$targetModel = if($mb0 -match 'Opus'){'^Sonnet'} else {'^Opus'}
if(Expand (MB)){ Start-Sleep -Seconds 1; Write-Output ("  ->change: "+(Pick $targetModel)); Start-Sleep -Seconds 2 }
$mb1=NM (MB); Write-Output "model mid='$mb1'"
$revert = '^' + [regex]::Escape(($mb0 -split ' ')[0])
if(Expand (MB)){ Start-Sleep -Seconds 1; Write-Output ("  ->revert: "+(Pick $revert)); Start-Sleep -Seconds 2 }
$mb2=NM (MB); Write-Output "model after='$mb2'  REVERTED=$($mb2 -eq $mb0)"

Write-Output "`n=== VERDICT ==="
Write-Output ("model switch worked = " + ($mb1 -ne $mb0))
Write-Output ("effort switch worked = proven if mid differed above")