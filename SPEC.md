# MODEL AND FURIOUS — Build Spec

> **Authority.** Derived from experiments verified on the target machine on
> 2026-07-20 (see [STORICO.md](STORICO.md) for the dated log, [PROJECT.md](PROJECT.md)
> for direction/why). Where this spec and older notes disagree, **this spec wins.**
>
> ⚠️ **This is v2.** An earlier v1 targeted the Claude Code **CLI in a terminal**
> via console injection. That was the wrong target. The real target is the
> **Claude Desktop application** (the white GUI you launch from the Claude logo).
> All console-injection material is void; the actuator is **UI Automation**.

---

## 0. One-paragraph summary

A **standalone Windows desktop application** — a "gear shifter" — that changes the
**model** and **effort** of a conversation inside the **Claude Desktop app**, picked
from a dropdown of that app's conversations. It drives the Claude Desktop app's own
GUI controls through **Windows UI Automation (UIA)**: it reads the current
model/effort, lists the conversations, and flips the model picker / effort slider.
The user drives **only our stick**; they never open the model menu themselves. It is
the claudeine pattern: a separate desktop app that talks to Claude yet is independent
of Claude's interface.

---

## 1. Target (precise)

- **App:** Claude Desktop, MSIX package `Claude_1.22209.3.0_x64__pzs8sxrjxfjjc`,
  executable `…\WindowsApps\Claude_…\app\Claude.exe` — an **Electron/Chromium** app.
  Launch string: `shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude`.
- It is itself a Claude Code controller: it spawns
  `…\Roaming\Claude\claude-code\<ver>\claude.exe --output-format stream-json` children
  (cowork / Claude-Code-Desktop). We do **not** talk to those children; we drive the GUI.
- **Not** the CLI-in-terminal, **not** the web app, **not** the IDE.

---

## 2. Verified foundation (tested — do not re-litigate)

Reference implementation: [`prototype/uia_shifter.ps1`](prototype/uia_shifter.ps1)
(persistent UIA client: wake, enumerate, read, switch model, self-revert) and
[`prototype/uia_effort_slider.ps1`](prototype/uia_effort_slider.ps1) (effort slider).

| Fact | Evidence |
|---|---|
| The app's DOM is exposed to UIA **only while a UIA client is attached** — Chromium's a11y tree sleeps otherwise. A persistent client keeps it awake. | 15 nodes cold → 130+ named nodes once a client attached and retried. |
| Current **model** and **effort** are readable UIA Buttons. | `Button 'Sonnet 5'`, `Button 'Effort: High'`. |
| **Telemetry** is readable. | `Button 'Usage: context 6%, plan 32%'`. |
| The **conversation list** is readable (dropdown source). | Sidebar Buttons: `#1 · Merged swiss 01 - foundation`, `#2 · Portfolio project summaries`, many `arm IB …`, `Prova`, `crab 2`, plus `New session`, `Search`, `Terminal`, `Code`. |
| **Model switch works.** Model button supports `ExpandCollapse`; expanding shows RadioButtons; selecting one changes the model. | `Sonnet 5` → Select `Opus 4.8` → button read `Opus 4.8` → reverted to `Sonnet 5`. |
| Model options. | RadioButtons `Haiku 4.5`, `Sonnet 5 · Default`, `Opus 4.8`, `Fable 5`. |
| **Effort switch works.** Effort button opens a popup with a **Slider** (`Faster ↔ Smarter`), `RangeValuePattern`, range **0–5**. | `SetValue(1)` → `Effort: Medium`; restore `SetValue(2)` → `Effort: High`. |
| The window can be **minimized/hidden to tray** (handle `0`); must be found by PID and restored. | `hwnd=0` between runs; `EnumWindows`+`ShowWindow` recovers it. |

**Focus (ASSESSED 2026-07-20):** **reads are focus-free, writes are not.** Reading
model/effort/sessions/usage works while another window holds the foreground and
Claude stays background. But **actuating steals focus**: opening the model/effort
popup raises the Claude window to the foreground (confirmed — `foreground=CLAUDE`
the moment the menu expands). The switch still completes; the window just comes to
front. So monitoring is ambient/non-disruptive, but **every shift pops the Claude
app forward** — inherent to driving the Electron popup. Mitigation (unproven):
re-raise the user's previous window right after the shift (brief flicker).

**Effort ladder (ASSESSED, partial):** effort is a **0–5 slider (6 positions)**
driven by `RangeValuePattern.SetValue`; confirmed `1=Medium`, `2=High`. The full
six labels weren't enumerated because the popup opens unreliably via
`ExpandCollapse` (auto-dismisses / sticks) and the mouse-click fallback hit a **DPI
coordinate mismatch**. Both are harness artifacts. Build must (a) open the popup by
a **reliable method** and (b) use **DPI-aware coordinates** if it ever clicks;
reading all six labels is then trivial.

---

## 3. Key behavioral model

- The Claude Desktop app is **single-view**: model/effort apply to the
  **currently-open conversation**. There is no way to set a background
  conversation's model without navigating to it.
- Therefore **"shift session X" = (1) invoke session X's sidebar button to make it
  active, (2) read/flip its model + effort.** Our dropdown mirrors the app's
  conversation list; selecting an item navigates the app to it.
- This is different from (and weaker than) the old console idea: shifting a session
  will **bring that conversation to the foreground in the app**. Spec the UX around
  that truth, don't hide it.

---

## 4. Architecture

```
 ┌───────────────── GUI (Electron renderer — OUR app) ──────────────────┐
 │  Conversation dropdown   Main lever = MODEL   Splitter = EFFORT       │
 │  Cruscotto: context % · plan %          Shift confirmation           │
 └───────────────▲──────────────────────────────────────────▲──────────┘
                 │ IPC                                        │ IPC
 ┌───────────────┴──────────── OUR app main (Node) ──────────┴──────────┐
 │  Shifter Core (gears + effort-slider mapping)                        │
 └───────────────▲───────────────────────────────────────────────────────┘
                 │ request/response
 ┌───────────────┴──────────── UIA Broker (persistent) ─────────────────┐
 │  Attaches to Claude Desktop window, KEEPS a11y awake, and:           │
 │   enumerate()  read()  selectSession(name)  setModel(x)  setEffort(n)│
 └────────────────────────────────────────────────────────────────────────┘
```

### 4.1 UIA Broker (the actuator — load-bearing)

Uses UI Automation (`System.Windows.Automation` / equivalent). Responsibilities:

- **Attach & keep-awake:** locate the Claude Desktop main process (CIM: `Claude.exe`,
  cmdline has `WindowsApps`, not `--type`), find its top-level titled window by PID
  (`EnumWindows`), `ShowWindow(SW_RESTORE)`, `FromHandle`. Keep the client attached
  for the app's lifetime and re-walk periodically so Chromium a11y never sleeps.
- **Element lookup by STABLE traits, never dynamic AutomationId** (`base-ui-_r_1ls_`
  changes). Use `ControlType` + `Name` patterns:
  - model button: `Button` whose Name matches `^(Sonnet|Opus|Haiku|Fable)`
  - effort button: `Button` whose Name matches `^Effort`
  - effort slider: the `Slider` in the popup, `RangeValuePattern`
  - model options: `RadioButton`s named like the models
  - sessions: `Button`s whose Name matches `^#\d+ · ` (conversation entries)
  - telemetry: `Button` Name `^Usage:`
- **API:**
  - `enumerateSessions() -> [{name, active}]` — sidebar conversation buttons.
  - `readGear() -> {model, effort}` — the two button labels (active conversation).
  - `readUsage() -> {contextPct, planPct}` — parse the Usage button.
  - `selectSession(name)` — invoke that sidebar button; wait until active.
  - `setModel(alias)` — expand model button; `SelectionItemPattern.Select` the
    matching RadioButton; **verify** the model button label changed; else error.
  - `setEffort(level)` — expand effort button; `RangeValuePattern.SetValue(n)` on the
    slider (n = level→index map); **verify** the effort button label; else error.
- **Verification is mandatory** (Principle §7 in PROJECT.md): never report a shift
  done without reading the label back. Timeout → surface error.
- **Serialize** all UIA operations (one popup open at a time; close stale popups with
  Escape before opening another — popup-state races were observed).

### 4.2 Shifter Core (gearbox)

- **Main lever → model:** gears map to the RadioButtons `Haiku 4.5`, `Sonnet 5`,
  `Opus 4.8`, `Fable 5` (`Sonnet 5 · Default` = the settings default). Configurable.
- **Splitter → effort:** the 0–5 slider. Map splitter detents → slider indices
  (confirmed `1=Medium`, `2=High`; enumerate the rest at build time via
  `uia_effort_slider.ps1`). The splitter is a **6-detent range**, driven by
  `SetValue`, with the button label as the source of truth.
- Keep the dependent-splitter honesty from PROJECT.md §3 where it still applies
  (the app may itself constrain effort per model); reflect the **read-back** label,
  never the intended value.

### 4.3 GUI (our stick)

- **One window.** Dropdown = the app's conversations (from `enumerateSessions`).
  Selecting one calls `selectSession` (navigates the app) and shows its gear.
  Persistent label of the bound conversation (Principle §7).
- **Single stick, two gestures:**
  - left-click + drag → move stick in H-gate → change gear (effort)
  - right-click + drag → rotate the knob in place → change model
  - Right-click context menu is suppressed in Electron.
- **Rotary knob indicator** (4 positions: Haiku / Sonnet / Opus / Fable) reflects
  current model; the right-click drag gesture rotates it.
- **Engraved label** beneath the knob: "left → gear / right → model" —
  passive discoverability, dashboard style.
- **Cruscotto:** context % + plan % from `readUsage`.
- **Shift feedback:** landed / failed from the Broker's verified read-back.
- Be explicit in the UX that shifting a session **foregrounds that conversation** in
  the Claude Desktop app (§3).

### 4.4 Tech stack

- **Electron** for our app (claudeine pattern; reuse its build tooling: `--dir` +
  manual shortcut, `asar:false`, worker threads).
- **UIA Broker:** a .NET helper (C#/PowerShell `System.Windows.Automation`) or a
  Node UIA binding, run as a persistent child so the a11y client stays attached.
  Reference: the two `prototype/uia_*.ps1` scripts.
- Local-only; no network, no tokens consumed by our app.

---

## 5. Constraints & invariants

1. **Never claim an unverified shift** — read the label back or report failure.
2. **Explicit, visible target** — the bound conversation is always shown; selecting a
   session is an explicit act (and it foregrounds that conversation — §3).
3. **Keep the a11y client attached** (or the tree sleeps) and **restore the window**
   before driving.
4. **Serialize UIA ops**; clear stale popups with Escape.
5. Match elements by `ControlType`+`Name`, **not** dynamic AutomationIds.

---

## 6. Build order

- **M1 — UIA Broker (headless):** port `uia_shifter.ps1`; prove
  `enumerate → select session → setModel → setEffort → verify` as a persistent client.
- **M2 — validate focus-free actuation** (§2 open item); decide the window/focus UX.
- **M3 — GUI:** dropdown + two levers over the Broker.
- **M4 — Cruscotto:** context %/plan % from the Usage button.
- **M5 — polish:** effort-ladder mapping, error surfaces, session-foreground UX.

---

## 7. Open items (resolve during build)

- **Focus-on-shift UX (assessed §2):** shifting raises the Claude window. Decide:
  accept it, or re-raise the user's prior window after each shift. Reads stay ambient.
- **Reliable popup open + DPI (assessed §2):** replace flaky `ExpandCollapse` opens
  with a reliable method; make any coordinate use DPI-aware. Then enumerate the full
  effort 0–5 → label map.
- Robustness of Name-based selectors across app updates (localization: the app UI can
  be non-English — e.g. this machine shows Italian content; `Effort:`/model names
  appeared in English but verify).
- Does switching model mid-conversation trigger the app's own cache/re-read notice,
  and should we surface it (PROJECT.md §6)?
