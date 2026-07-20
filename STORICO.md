# STORICO

> ⚠️ **A FINE SESSIONE È OBBLIGATORIO** chiedere all'utente se procedere con
> l'aggiornamento di questo file e di [PROJECT.md](PROJECT.md). Non aggiornare
> senza conferma, ma **non chiudere la sessione senza aver chiesto.**

Registro cronologico delle sessioni. **Solo date e azioni eseguite**: bug, fix,
decisioni. Niente piani, niente intenzioni, niente "prossimi passi" — quelli
stanno in [PROJECT.md](PROJECT.md).

## Regole di scrittura

- Voce nuova **in cima**, formato data `AAAA-MM-GG`.
- Ogni riga è **una cosa che è successa**, al passato.
- Tag ammessi: `DECISIONE` · `FIX` · `BUG` · `SETUP` · `SCOPERTA` · `SCARTATO`
- Le decisioni riportano il **motivo**, non solo l'esito. Fra sei mesi il "cosa"
  si ricostruisce dal codice, il "perché" no.
- Non riscrivere le voci passate. Se una decisione viene ribaltata, si aggiunge
  una voce nuova che la ribalta — lo storico resta un registro, non un riassunto.

---

## 2026-07-20

- `SETUP` — Repo collegato a GitHub (`matteoccll/claude_shifter`), clonato in
  `C:\Users\simon\Desktop\MODEL AND FURIOUS`, branch `main` da `fb34a0c`.
  Cartella aperta in VS Code. `gh` CLI **non installato** sulla macchina.
- `SCOPERTA` — Verificato sui doc ufficiali che i due assi del cambio esistono
  già come comandi separati: `/model` (haiku, sonnet, opus, fable, default,
  opusplan, best) e `/effort` (low, medium, high, xhigh, max, ultracode).
  Conferma l'ipotesi "main box + splitter" di `model selection.md`.
- `SCOPERTA` — Risolta la domanda aperta di `model selection.md:56`: l'effort è
  **globale**, non per-marcia, ma viene **resettato per famiglia di modello**
  (Fable 5 e Opus 4.8 → `high`, Opus 4.7 → `xhigh`, ignorando la scelta
  precedente) e **scala** al livello più alto supportato se il modello non
  regge quello richiesto. Quindi non tutte le combinazioni sono ingranabili.
- `SCOPERTA` — Confermati tutti i campi del cruscotto via statusline JSON:
  `model.display_name`, `context_window.remaining_percentage`,
  `total_input_tokens`, `cost.total_cost_usd`, `session_id`, `transcript_path`,
  `exceeds_200k_tokens`. Supporta multi-riga, ANSI e `refreshInterval: 1` →
  il tach può aggiornarsi ogni secondo. Le voci marcate *inferred* in
  `model selection.md` (FUEL = contesto) risultano corrette.
- `SCARTATO` — **Hook come attuatore.** Nessun hook può cambiare modello o
  effort; `SessionStart` riceve il modello in input ma non esiste campo di
  output per modificarlo. Strada chiusa, non riprovare.
- `SCARTATO` — **`model` in settings.json come attuatore.** Letto solo
  all'avvio della sessione, inerte a caldo.
- `SCARTATO` — **Skill con frontmatter `model:`/`effort:` come leva.**
  Funziona ma l'override dura **un solo turno**: è un kickdown, non una marcia
  inserita. Eventualmente recuperabile come feature secondaria.
- `DECISIONE` — Architettura: **GUI esterna + injection da tastiera nel
  terminale.** Motivo: `/model` e `/effort` digitati nel TTY sono l'**unico**
  meccanismo che produce uno shift persistente. Scartato l'harness proprio su
  Agent SDK perché equivale a riscrivere Claude Code invece di guidarlo.
- `BUG` — **Aperto, bloccante.** L'attuatore richiede injection di tastiera, ma
  la macchina è Windows 11 e tmux non esiste. Alternative: WSL + tmux, oppure
  SendInput/AutoHotkey su Windows Terminal. La seconda non dà conferma
  affidabile che il tasto sia atterrato nel pane giusto — cioè esattamente il
  fallimento che `window selection.md` dichiara inaccettabile.
- `DECISIONE` — Creati `PROJECT.md` e `STORICO.md` come documenti guida, con
  obbligo esplicito di richiesta di aggiornamento a fine sessione.

---

> ⚠️ **PROMEMORIA FINALE — TASSATIVO**
> Prima di chiudere la sessione, chiedere all'utente:
> **"Aggiorno PROJECT.md e STORICO.md con quanto fatto oggi?"**
> Attendere conferma esplicita. Non aggiornare d'iniziativa, non saltare la domanda.
