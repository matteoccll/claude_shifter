# prototype/ — the proven actuator core (UI Automation)

These scripts are the **verified reference implementation** of the shifter's
actuator, tested end-to-end against the live **Claude Desktop app** (MSIX Electron)
on 2026-07-20. Port them into the app's UIA Broker (see [../SPEC.md](../SPEC.md) §4.1).

- **`uia_shifter.ps1`** — the full persistent-client loop: locate + restore the
  Claude Desktop window, keep Chromium's a11y tree awake, enumerate the conversation
  sidebar, read current model/effort/usage, **switch model** (expand the model
  button → `SelectionItemPattern.Select` a RadioButton), and self-revert. This is
  the end-to-end proof of read + enumerate + model-switch.
- **`uia_effort_slider.ps1`** — the **effort** actuator: the effort control is a
  popup **Slider** (0–5, `Faster ↔ Smarter`); drive it via
  `RangeValuePattern.SetValue` and confirm from the `Effort: <level>` button label.

Requires Windows + `System.Windows.Automation` (built into .NET). The Claude Desktop
app must be installed/running.

## Hard-won facts (read before changing the approach)

- **Chromium's a11y tree sleeps** unless a UIA client stays attached — a one-shot
  script sees ~15 nodes; a persistent client sees 130+. Keep the client alive.
- **The window minimizes/hides to tray** (handle can be `0`); find it by PID with
  `EnumWindows` and `ShowWindow(SW_RESTORE)` before driving.
- **Match elements by `ControlType` + `Name`, never by AutomationId** — the ids are
  dynamic (`base-ui-_r_1ls_`) and change between renders.
- **Model/effort apply to the active conversation** — select the session in the
  sidebar first (it foregrounds that conversation).
- **Serialize UIA ops** and Escape stale popups before opening a new one.
- **Open item:** actuation here ran with the window foregrounded; focus-free
  actuation is not yet verified.

> A prototype, not the product. The shipped broker should be a persistent .NET/Node
> UIA client, per SPEC.md §4.1. (The earlier console-injection prototype targeted the
> wrong thing — the CLI — and was removed.)
