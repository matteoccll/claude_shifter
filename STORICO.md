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

## 2026-07-20 (sessione 4 — spec GUI e divisione backend/frontend)

- `DECISIONE` — **Controllo modello: manopola rotante a 4 posizioni** (Haiku / Sonnet / Opus / Fable). Scartati pulsanti separati e levette. Motivo: scelta discreta tra 4 opzioni, il gesto "girare" è intuitivo e si abbina visivamente allo stick per l'effort senza sovrapporsi.
- `DECISIONE` — **Unico stick con doppio gesto: clic sinistro = sposta in H (effort), clic destro = ruota pomello (modello).** Il pomello in cima allo stick gestisce entrambi gli assi con distinzione netta via tasto mouse, evitando conflitti tra gesto lineare e gesto rotazionale. In Electron il menu contestuale del tasto destro viene disabilitato e il gesto diventa dedicato.
- `DECISIONE` — **Feedback discoverability: targhetta incisa sul pannello** con etichette "sin → cambia marcia / des → ruota modello". Stile engraved (testo piccolo, maiuscoletto, colore smorzato) — parte del design della plancia, non un tooltip aggiunto dopo.
- `DECISIONE` — **Sviluppo parallelo: backend e frontend assegnati a due collaboratori distinti.** Backend (UIA Broker) sviluppato da Simone; frontend (GUI Electron) sviluppato dall'altro collaboratore. I due lati verranno integrati in una fase successiva.

---

## 2026-07-20 (sessione 3 — correzione bersaglio: app Claude Desktop, non terminale)

- `DECISIONE` — **RIBALTATA la sessione 2.** Il bersaglio NON è Claude Code nel
  terminale: è l'**app Claude Desktop** (MSIX Electron, quella bianca che si apre
  dal logo). Tutto l'attuatore a console injection della sessione 2 era corretto
  ma sul bersaglio sbagliato → archiviato. Motivo: richiesta esplicita e ripetuta
  dell'utente.
- `SCOPERTA` — L'app Claude Desktop è un pacchetto **MSIX**
  (`Claude_1.22209.3.0_x64__pzs8sxrjxfjjc`, in `Program Files\WindowsApps\…`),
  Electron/Chromium. Lancio: `shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude`.
  Spawna `claude-code\<ver>\claude.exe --output-format stream-json`: è essa stessa
  un controller di Claude Code (cowork/CCD).
- `SCOPERTA` — **Attuatore corretto: Windows UI Automation (UIA) sull'app.**
  Provato dal vivo end-to-end:
  - l'albero a11y di Chromium è esposto solo con un **client UIA persistente**
    attaccato (15 nodi a freddo → 130+ nomi con client attaccato);
  - modello ed effort correnti sono `Button` leggibili (`'Sonnet 5'`,
    `'Effort: High'`); telemetria in `Button 'Usage: context 6%, plan 32%'`;
  - la **tendina sessioni** sono i `Button` `#N · <titolo>` della sidebar;
  - **switch modello**: espandi il button → `Select` sul `RadioButton`
    (`Haiku 4.5`/`Sonnet 5·Default`/`Opus 4.8`/`Fable 5`) → etichetta cambia.
    Provato Sonnet→Opus→Sonnet (self-revert).
  - **switch effort**: popup con **Slider** 0–5 (`Faster↔Smarter`),
    `RangeValue.SetValue` → etichetta cambia. Provato High→Medium→High.
- `SCOPERTA` — Modello/effort valgono sulla **conversazione attiva**: per agire su
  una sessione bisogna prima selezionarla nella sidebar (che la porta in primo
  piano nell'app). Vincolo UX da specificare.
- `BUG` — **Aperto:** attuazione provata con finestra in **foreground**. Da
  verificare se funziona **senza rubare il focus** (il vecchio bersaglio console
  era focus-free; questo forse no).
- `SETUP` — Riscritta [SPEC.md](SPEC.md) su base UIA/app Desktop (v2). Prototipo
  `prototype/` aggiornato: rimossi gli script console, aggiunti `uia_shifter.ps1`
  e `uia_effort_slider.ps1`. PROJECT.md allineato.
- `SCOPERTA` — **Focus valutato: letture focus-free, switch no.** Tenendo il
  foreground con un'altra finestra, la lettura di modello/effort/sessioni/usage
  funziona con Claude in background; ma **aprire il menu (switch) porta la finestra
  Claude in primo piano** (`foreground=CLAUDE` all'apertura del popup). Il
  monitoraggio è ambientale/non invasivo, ogni cambio marcia invece alza l'app.
  Inerente al pilotare il popup Electron. Downgrade reale rispetto al vecchio
  bersaglio console (che era focus-free anche in scrittura).
- `SCOPERTA` — **Ladder effort: meccanismo provato, mappa completa no.** Slider
  0–5 via `RangeValue.SetValue` (1=Medium, 2=High confermati). I 6 label non
  enumerati: il popup effort si apre in modo instabile via `ExpandCollapse`
  (si auto-chiude / si incastra) e il fallback a click del mouse ha sbagliato le
  coordinate per **mismatch DPI**. Artefatti del banco di prova, non blocchi:
  la build deve aprire il popup con un metodo affidabile e usare coordinate
  DPI-aware.

---

## 2026-07-20 (sessione 2 — pivot desktop + attuatore risolto)

- `DECISIONE` — **Pivot: il prodotto è software desktop autonomo, non terminale
  né web.** L'utente pilota solo la GUI (una leva sola + menu a tendina delle
  sessioni), mai la tastiera del terminale. Riferimento concettuale: claudeine —
  "un software che comunica con Claude ma è indipendente dalla sua interfaccia".
- `DECISIONE` — **Una sola leva con tendina di selezione sessione**, scartata
  l'ipotesi "una leva per sessione" perché diventa un caos di finestre.
- `SCARTATO` — **Estensione web / browser.** Il target è il desktop.
- `SCARTATO` — **Icona-stick iniettata dentro ogni chat.** Elegante (dissolve il
  targeting) ma richiede injection nel renderer dell'app: fragile su Electron,
  si rompe a ogni update. Tenuta come idea, non come strada.
- `SCOPERTA` — **Nessun canale supportato cambia modello/effort a caldo.**
  Verificato sui doc (vs-code, agent-sdk, model-config, settings): né IDE
  websocket, né Agent SDK, né settings.json. L'unico meccanismo è il comando
  `/model`/`/effort`. Quindi l'attuazione deve simularne la digitazione.
- `SCOPERTA` — **`~/.claude/sessions/<pid>.json` è il registro vivo delle
  sessioni interattive** (pid, sessionId, cwd, name, status busy/idle). È la
  sorgente del menu a tendina: fra ~14 `claude.exe` isola correttamente le 2
  interattive.
- `SCOPERTA` — **Attuatore risolto e provato: `AttachConsole(pid)` +
  `WriteConsoleInput`.** Consegna i tasti a una console **per PID, senza rubare
  il focus**, anche dentro Windows Terminal (ConPTY) e su TUI in raw-mode, e
  perfino in una **tab in background**. È l'equivalente Windows di
  `tmux send-keys -t`. Chiude il BUG bloccante della sessione 1.
- `SCOPERTA` — **Conferma via `AttachConsole(pid)` +
  `ReadConsoleOutputCharacter`:** si rilegge lo schermo della sessione per PID
  (focus-free) e si verifica dall'header che lo shift sia entrato. Diventa anche
  la sorgente del "marcia corrente" per il cruscotto.
- `SCOPERTA` — **Confermato dal vivo su una sessione reale:** `/effort low`
  cambia l'header `high → low` istantaneamente; `/model sonnet` porta l'header
  `Opus 4.8 → Sonnet 5` ma passa da una conferma **"Switch model?"**.
- `SCOPERTA` — **Il warning sul costo di cache è nativo.** La conferma di
  `/model` mostra già "This conversation is cached… full history gets re-read".
  Il differenziatore di PROJECT §6 in parte esiste già: la GUI lo anticipa e
  rilancia, non lo inventa.
- `SCOPERTA` — **Reset dell'effort per famiglia confermato dal vivo:**
  `settings.json` diceva `effortLevel: medium`, una sessione Sonnet 5 nuova
  mostrava `high`. E `/model`/`/effort` **si salvano come default** in
  `settings.json` (i test l'hanno mutato; ripristinato a `sonnet`/`medium`).
- `SETUP` — Salvato il prototipo provato in [`prototype/`](prototype/)
  (`inject.py`, `screen_read.py`). Scritta la spec di build [SPEC.md](SPEC.md).
  Eliminati `model selection.md` e `window selection.md`: contenuto utile
  assorbito da SPEC.md/PROJECT.md.

---

## 2026-07-20 (sessione 1 — analisi e verifiche iniziali)

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
