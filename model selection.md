# Shift Mechanism Spec v2 — What the two apps actually do

Supersedes the previous spec, which combined model and effort onto one lever (H-pattern gate + throw). That was speculation. Neither real app does that. Below is what's actually on their pages, split from what's inferred.

## 1. Model Shift (shiftcc.app) — dodges the problem entirely

Confirmed from the page's own gear map:

```
1st — Haiku
2nd — Sonnet
3rd — Fable
4th — Opus
5th — GPT-5.5   (yes — Codex models share the same gearbox)
R   — Default
```

There is no effort control anywhere on this page. No lever, no dial, no mention of the word. The gearbox has exactly as many positions as it has models — 5 forward gears + reverse, one throw = one full preset.

**How this avoids 20 states:** it doesn't solve the combinatorics, it refuses the premise. Effort isn't a variable this app exposes at the shifter at all — presumably left at each model's API default, set elsewhere if at all. Simplicity purchased by cutting a whole axis, not by cleverly folding it in.

## 2. ModelShifter (modelshifter.app) — two independent physical controls

Confirmed from the page's own copy: *"A gated six-speed bolted to your desktop... Cache-safe clutch, **an effort lever**, and a tach that revs with your real tokens/min."*

So this app does expose effort — but as a **second, separate lever**, not as a second axis on the same throw. The gearstick handles model (1st = Haiku, 5th = Fable, confirmed); the effort lever is a distinct control next to it.

The interactive dashboard mockup on the page shows these labeled elements (quoted as they appear):

| Label | What it plausibly is |
|---|---|
| `TOK/MIN` tach | live token throughput readout |
| `NEUTRAL` | an idle/safe resting state before a gear is engaged |
| `DIRECT DRIVE` | a named position — see below |
| `FUEL` (gauge marked E ↔ F) | *inferred*: context or budget remaining, styled as a fuel gauge |
| `CLUTCH` | *inferred*: a control you engage before shifting, tied to "cache-safe" |
| `LINK` | *inferred*: connection status to the live tmux/Claude Code session |
| `TOTAL ×1000 TOK` | running token counter |

**The one genuinely load-bearing detail:** `DIRECT DRIVE` is not a generic label — it's real terminology from heavy-truck transmissions. Trucks with small main gearboxes (say, 4-5 speeds) reach 10-18 effective ratios via a **range splitter**: a separate thumb-operated lever or switch on the knob with a few named positions, typically Low / Direct / Overdrive, that multiplies every main gear by 2-3x. "Direct" specifically means the splitter is passing 1:1 — neither multiplying nor reducing.

That match is too specific to be coincidental. It strongly suggests ModelShifter's effort lever isn't a 5-step linear slider — it's modeled on a **splitter**, a small set of named multiplier positions layered onto the main gear, which is exactly the real mechanical answer to "more ratios than physical gear positions" that trucking solved decades before software UI designers reinvented it.

## 3. What this actually tells us about the 20-state problem

Neither app builds anything resembling a single 4×5 grid on one lever. They diverge in a more informative way:

- **Model Shift**: eliminates the second axis. One gear, one preset, done.
- **ModelShifter**: keeps two axes, but refuses to let them share one physical motion — model on the main stick, effort on an entirely separate lever, mirroring a truck's main-box-plus-splitter layout rather than a car's H-pattern gate-and-throw.

My original spec's mistake was assuming the two axes had to share one lever because that's the more common car metaphor. The actual product goes with the truck metaphor instead — because trucks, not cars, are the real-world vehicles that actually face "more ratios than one lever can hold."

## 4. Genuinely unknown (not stated anywhere on either page)

- Exact number of detents on ModelShifter's effort lever, or their names beyond `DIRECT DRIVE`.
- Whether the effort lever's position is remembered per-gear or is global across all six gears.
- What `CLUTCH` mechanically requires from the user (hold-while-shifting? press-before-shifting?).
- Whether `FUEL` is context window, token budget, or something else — it's a visual guess from the gauge styling, not a labeled explanation.

Getting exact answers to those would need the actual app running, or a response from its maker — the marketing page doesn't go deeper.
