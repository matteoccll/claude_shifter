# Session Shifter — Technical Spec

A menubar "gear shift" that changes the model of a *specific* live Claude Code session, without guessing.

## 1. Problem

A single physical/UI control (the shifter) must act on one of N concurrent Claude Code sessions (tmux panes). Implicit targeting — "whichever pane last had focus" — is a footgun: shift while your eyes are on the wrong window and you silently retarget the wrong conversation, plus you eat a full-price re-read of that session's context on the next turn (prompt cache is keyed to the model that served the request).

Design principle: **the target must always be visible before the shift, never inferred silently after.**

## 2. Session registry

A background daemon enumerates tmux panes matching a Claude Code process signature and maintains one record per session:

```
Session {
  pane_id          # tmux %N identifier, stable while pane lives
  cwd               # working directory (used as display label)
  current_model
  last_prompt_snippet   # first ~40 chars of last user message, for identification
  last_active_at
  approx_context_tokens # for cache-cost warning
}
```

Registry refreshes on a tmux hook (`pane-focus-in`, `window-pane-changed`) rather than polling — so it's always current without wasting cycles.

## 3. Targeting modes

Two explicit modes, no hidden third behavior:

- **Pinned** (default once used): the shifter is bound to one `pane_id`. It stays bound even if you switch windows elsewhere. The menubar icon shows a persistent label (`cwd` basename) so you always know what you're about to hit.
- **Follow-focus** (opt-in): binds to whatever tmux pane currently has focus, live. Riskier by design — only useful if you genuinely shift immediately after switching panes and never tab away first.

Switching between the 5 open sessions to re-pin is one click in the widget's dropdown — never automatic, never based on recency alone.

## 4. Widget UI

- Gear positions 1–5 (or however many models) map to model names, configured once.
- A single-line status readout above the lever: `→ target: ~/proj/api-server (opus, 340 tests output found`) so the bound session is unambiguous at a glance.
- A small list icon opens all 5 known sessions with their last-prompt snippet, letting you re-pin without leaving the widget.

## 5. Actuator

On shift:
1. Resolve `pane_id` from current target (pinned or focused).
2. `tmux send-keys -t <pane_id> "/model <model-name>" Enter`
3. Poll pane output (via `tmux capture-pane`) for Claude Code's own confirmation line.
4. On mismatch/timeout, surface a widget error instead of assuming success — never claim a shift happened without confirming it landed in that pane.

## 6. Cache-cost warning

Before sending the shift, use `approx_context_tokens` to show an inline estimate: *"~18k tokens will re-read at full price on next turn."* This is the one piece of information ModelShifter/Model Shift's landing pages didn't surface, and it's the actual cost of a mid-conversation shift — worth seeing before you commit, not after the bill.

## 7. Non-goals

- No broadcast-to-all-sessions mode — too easy to misfire five conversations at once.
- No fully automatic target inference beyond "current tmux focus" — anything cleverer (e.g. guessing by recent keystroke activity) trades a small convenience for a much worse failure mode: silent wrong-session shifts.

## 8. Open question

Whether to persist pin state across app restarts (tmux `pane_id`s survive a tmux server restart but not necessarily map back to the same logical session) — simplest fix is keying persistence off `cwd` + session start time rather than raw `pane_id`.
