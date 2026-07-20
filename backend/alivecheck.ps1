#Requires -Version 5.1
# Collaudo delle tre verifiche di IsAlive (broker.ps1) contro un'app che si puo'
# chiudere davvero.
#
# PERCHE' ESISTE
# Il ramo "app davvero chiusa" non e' provabile su Claude Desktop: il broker si
# aggancia al processo Claude, che e' la stessa app dentro cui gira chi lo
# pilota. Chiuderla chiude anche il collaudo. Provato sul campo il 2026-07-20:
# chiudere la finestra non basta nemmeno, perche' Electron tiene vivo il
# processo -- quindi la strada e' impraticabile per costruzione, non per caso.
#
# COSA PROVA DAVVERO
# Le tre verifiche di IsAlive non hanno nulla di specifico su Claude: chiedono a
# Windows se una finestra esiste, se un processo e' vivo, se un albero UIA
# risponde. Qui si fanno le stesse identiche domande sul Blocco note, che si puo'
# chiudere sul serio. Se passano da tutte-vere a tutte-false quando l'app muore,
# il rilevamento funziona.
#
# COSA NON PROVA
# Che le due meta' funzionino INSIEME sull'app vera. Il rilevamento e' provato
# qui, il riaggancio e' provato da reattach.js: la giuntura fra i due resta
# ragionata. E' il massimo ottenibile senza chiudere l'app che ci ospita.
#
# NON TOCCA CLAUDE. Apre e chiude una finestra vuota, creata apposta.
#
# La cavia serve a una cosa sola: essere un processo che possiede la propria
# finestra e che si puo' uccidere. Due candidati scartati sul campo il
# 2026-07-20:
#   - Blocco note: su Windows 11 e' un'app dello Store, `Start-Process notepad`
#     lancia un guscio che termina subito e la finestra vera nasce da un altro
#     processo. Il collaudo restava senza handle.
#   - cmd.exe: non possiede piu' la propria finestra, la tiene il Terminale
#     (MainWindowHandle = 0 anche a processo vivo).
# Una finestra WinForms vuota, creata da un secondo processo PowerShell, non ha
# nessuna delle due sorprese: il processo che avvii e' quello che possiede la
# finestra, ed e' esattamente il rapporto che qui va verificato.
#
#   powershell -ExecutionPolicy Bypass -File backend\alivecheck.ps1

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WT {
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
}
"@

$A = [System.Windows.Automation.AutomationElement]

function Say { param($m) Write-Host $m }

# Le tre verifiche, nello stesso ordine di IsAlive in broker.ps1.
#
# Il controllo `$null -eq $root` non e' pignoleria: con Set-StrictMode Off,
# leggere una proprieta' di $null NON solleva eccezione, restituisce $null. Senza
# questa riga il collaudo direbbe "albero vivo" anche senza albero. Il broker ha
# la stessa guardia in cima a IsAlive, ed e' questo il motivo.
function Checks {
    param($hwnd, $procId, $root, $procName)
    $win = $false
    if ($hwnd -and $hwnd -ne [IntPtr]::Zero) { $win = [WT]::IsWindow($hwnd) }

    $proc = $false
    try { $p = Get-Process -Id ([int]$procId) -ErrorAction Stop; $proc = ($p.ProcessName -eq $procName) }
    catch { $proc = $false }

    # GetCurrentPropertyValue, non $root.Current.Name: e' questo collaudo ad aver
    # scoperto che `.Current.Name` continua a rispondere da una copia in memoria
    # anche dopo che il processo e' morto -- diceva "albero vivo" su un cadavere.
    # GetCurrentPropertyValue va a chiedere davvero, e solleva eccezione quando
    # non c'e' piu' nessuno che risponde.
    $tree = $false
    if ($null -ne $root) {
        try { $null = $root.GetCurrentPropertyValue($A::NameProperty); $tree = $true } catch { $tree = $false }
    }

    [pscustomobject]@{ Finestra = $win; Processo = $proc; AlberoUIA = $tree }
}

function Show { param($label, $c)
    Say ("  {0,-24} finestra={1,-5} processo={2,-5} alberoUIA={3,-5}" -f $label, $c.Finestra, $c.Processo, $c.AlberoUIA)
}

Say ''
Say 'Collaudo del rilevamento "app morta" - cavia: finestra vuota'
Say '==========================================================='

Say ''
Say '1. apro la cavia'
# -WindowStyle Hidden nasconde la console del processo, non la finestra WinForms:
# quella che si vede a schermo per qualche secondo e' la cavia.
$cavia = 'Add-Type -AssemblyName System.Windows.Forms; ' +
         '$f = New-Object System.Windows.Forms.Form; ' +
         '$f.Text = "COLLAUDO-ALIVECHECK"; $f.Width = 320; $f.Height = 160; ' +
         '[void]$f.ShowDialog()'
$np = Start-Process powershell -ArgumentList '-NoProfile','-WindowStyle','Hidden','-Command',$cavia -PassThru
for ($i = 0; $i -lt 30 -and (-not $np.MainWindowHandle -or $np.MainWindowHandle -eq [IntPtr]::Zero); $i++) {
    Start-Sleep -Milliseconds 300
    $np.Refresh()
}
$hwnd     = $np.MainWindowHandle
$procId   = $np.Id
$procName = $np.ProcessName
if (-not $hwnd -or $hwnd -eq [IntPtr]::Zero) { Say '   FALLITO: la cavia non ha aperto una finestra'; exit 1 }
Say "   processo=$procName pid=$procId  finestra=$hwnd"

$root = $A::FromHandle($hwnd)

Say ''
Say '2. con l app VIVA - attese tutte True'
$before = Checks $hwnd $procId $root $procName
Show 'app viva' $before

Say ''
Say '3. chiudo la cavia'
try { $null = $np.CloseMainWindow() } catch {}
if (-not $np.WaitForExit(5000)) { Say '   non si chiude da sola, la termino'; try { $np.Kill() } catch {}; $null = $np.WaitForExit(5000) }
Start-Sleep -Milliseconds 800
Say '   chiusa'

Say ''
Say '4. con l app MORTA - attese tutte False'
$after = Checks $hwnd $procId $root $procName
Show 'app morta' $after

Say ''
Say '--- esito ---'
$okVivo  = $before.Finestra -and $before.Processo -and $before.AlberoUIA
$okMorto = -not ($after.Finestra -or $after.Processo -or $after.AlberoUIA)

if ($okVivo -and $okMorto) {
    Say 'PASSATO: le tre verifiche riconoscono sia l app viva sia l app morta.'
    Say 'Il rilevamento che usa il broker funziona su un caso di morte reale.'
    exit 0
}
if (-not $okVivo)  { Say 'FALLITO: con l app viva qualche verifica dice gia di no (falso allarme:' }
if (-not $okVivo)  { Say '         il broker si riaggancerebbe in continuazione senza motivo).' }
if (-not $okMorto) { Say 'FALLITO: con l app morta qualche verifica dice ancora di si (il broker' }
if (-not $okMorto) { Say '         resterebbe attaccato a una finestra che non esiste piu).' }
exit 1
