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

## 2026-07-20 (sessione 6 — backend: i due pezzi mancanti del broker)

- `SETUP` — Aggiunto il comando **`capabilities`**: una sola risposta con marcia
  innestata, effort corrente, **numero di marce del modello attivo**, elenco dei
  modelli con `enabled`/`selected`, e telemetria del cruscotto. Provato sull'app
  viva: 7 modelli letti, `Opus 4.8 / Alto`, 6 marce (cursore 0-5), contesto 9% /
  piano 32%, in 9,9 s.
- `DECISIONE` — **`capabilities` risponde solo per il modello attivo, non per
  tutti.** Motivo: una tabella completa richiederebbe di cambiare marcia sette
  volte a ogni chiamata, e sarebbe una *dichiarazione* — proprio ciò che il
  principio "il backend rileva, non dichiara" vieta. La GUI richiama il comando
  dopo ogni `setModel` e ridisegna la griglia.
- `DECISIONE` — **Fallimento parziale riportato per sezione invece di far
  fallire tutto il comando.** `capabilities` torna quel che è riuscita a leggere
  più una lista `errors`. Motivo: una GUI che ha i modelli ma non la corsa
  dell'effort può disegnare qualcosa di onesto; un errore secco la lascia senza
  nulla da disegnare.
- `SETUP` — Aggiunto il **riaggancio automatico**: prima di ogni comando il
  broker verifica di essere ancora legato alla finestra giusta (handle valido →
  processo vivo e di nome `Claude` → radice UIA che risponde) e, se l'aggancio è
  caduto, si rilega da solo emettendo l'evento `reattached` (o `detached` se
  l'app non c'è). Prima restava legato a una finestra morta e ogni comando
  falliva finché non lo si riavviava a mano.
- `DECISIONE` — **Il riaggancio non rilancia l'app.** `Attach` prende un
  parametro `$Launch`: vero all'avvio, falso al riaggancio. Motivo: se l'utente
  ha chiuso Claude Desktop apposta, riaprirgliela addosso è peggio di un errore
  chiaro; la GUI accende una spia invece di indovinare.
- `DECISIONE` — **Non si controlla se `FindClaudeHwnd` restituisce ancora *il
  nostro* handle.** Restituisce la prima finestra Claude che incontra: con due
  finestre aperte quel confronto oscillerebbe e il broker si riaggancerebbe a
  ogni comando.
- `SCOPERTA` — **Il collaudo onesto del riaggancio non è eseguibile dall'interno.**
  Il broker si aggancia al processo `Claude`, che è la stessa app dentro cui gira
  chi lo pilota: chiuderla per provare il recupero chiude anche il collaudo.
  Aggiunto il comando diagnostico `forceDetach`, che butta via l'aggancio senza
  toccare l'app, e `reattach.js` che lo usa — 3 recuperi su 3, ~1,4 s l'uno.
  Copre la metà cara del recupero (ritrovare la finestra, risvegliare l'albero di
  accessibilità), **non** il rilevamento della morte del processo.
- `SETUP` — Scritto `detachtest.js` per il ramo non coperto: va lanciato **da un
  terminale esterno** con l'app aperta, poi si chiude e si riapre Claude Desktop
  a mano. Nota: si parte a app *aperta* perché all'avvio il broker, se non la
  trova, la lancia lui. **Non ancora eseguito.**
- `SETUP` — Aggiunto `capabilities.js` (collaudo di sola lettura) e l'inoltro
  degli eventi del broker al client Node (`onEvent`), così la GUI vede
  `attached`/`reattached`/`detached` senza interrogare.
- `SCOPERTA` — **PowerShell 5.1 collassa un array di un elemento in un oggetto
  singolo** nel JSON. `Broker.capabilities()` normalizza `models` ed `errors` con
  `[].concat(...)`: se un giorno l'app offrisse un solo modello, la GUI non deve
  accorgersene.
- `SCARTATO` — **Provare il riaggancio chiudendo Claude Desktop a mano.** Provato
  sul campo: chiudere la finestra non chiude l'app (Electron tiene vivo il
  processo), e chiuderla davvero chiude anche chi sta eseguendo il collaudo,
  perché è la stessa app. La strada è impraticabile per costruzione, non per
  sfortuna. `detachtest.js` resta in repo: funzionerebbe su una macchina dove
  chi collauda non sta dentro l'app, ma qui non è eseguibile.
- `SETUP` — Scritto `alivecheck.ps1`: prova le tre verifiche di `IsAlive` su una
  cavia che si può uccidere davvero (una finestra vuota creata apposta), invece
  che su Claude. Le verifiche non hanno nulla di specifico su Claude, quindi il
  rilevamento si può provare senza chiudere l'app che ci ospita. Esito: passato.
- `BUG` `FIX` — **La terza verifica di `IsAlive` non verificava niente.**
  `$root.Current.Name` continua a rispondere da una copia in memoria anche dopo
  che il processo è morto: `alivecheck.ps1` la mostrava a `True` su un cadavere.
  Sostituita con `GetCurrentPropertyValue(NameProperty)`, che va a chiedere
  davvero e solleva eccezione quando non c'è più nessuno. Le prime due verifiche
  reggevano già, quindi il broker si comportava bene: il difetto era una falsa
  sicurezza, non un malfunzionamento.
- `BUG` `FIX` — **Il riaggancio prendeva la finestra sbagliata.** L'app possiede
  più finestre; `FindClaudeHwnd` restituiva la prima e il criterio di risveglio
  era un conteggio di elementi (`> 40`). Una finestra secondaria con 49 elementi
  e nessuna leva dentro passava il controllo, e da lì ogni comando falliva con
  `readGear: elements not found`. Osservato dal vivo durante il collaudo.
  Sostituito con `FindClaudeWindows`, che le elenca tutte, le prova dalla più
  grande e **accetta solo quella in cui il pulsante del modello esiste** — la
  cosa di cui ogni operazione ha effettivamente bisogno. Se nessuna ce l'ha
  (schermata senza selettore) ripiega sulla più ricca e lo scrive nel log.
- `SCOPERTA` — **Cavie di collaudo scartate su Windows 11.** Il Blocco note è
  un'app dello Store: `Start-Process notepad` lancia un guscio che termina subito
  e la finestra vera nasce da un altro processo. `cmd.exe` non possiede più la
  propria finestra (la tiene il Terminale): `MainWindowHandle` resta 0 a processo
  vivo. Serve una finestra WinForms creata da un secondo processo PowerShell.

## 2026-07-20 (sessione 5 — backend: UIA Broker costruito e mappa del cambio)

- `SETUP` — Costruito il **UIA Broker** in `backend/` come demone persistente
  (`broker.ps1`) che parla NDJSON su stdin/stdout, più client Node
  (`client.js`) e strumenti di collaudo (`state.js`, `dump.js`, `tree.js`,
  `effortpopup.js`, `map.js`). Comandi: `enumerate`, `readGear`, `readUsage`,
  `selectSession`, `setModel`, `setEffort`, `listModels`, `effortRange`,
  `probeEffort` + diagnostici.
- `DECISIONE` — **Broker in PowerShell, non in .NET/C#.** Motivo: `dotnet` non è
  installato sulla macchina, mentre PowerShell 5.1 espone già
  `System.Windows.Automation` nativamente. Zero installazioni, e riusa
  direttamente la logica già provata nei prototipi.
- `DECISIONE` — **Rilevamento dinamico invece di tabelle scritte a mano.** Il
  broker non dichiara quali modelli/effort esistono: li legge dall'app a ogni
  richiesta. Motivo: una lista hardcoded diventa falsa al primo aggiornamento di
  Claude e il fallimento sarebbe silenzioso. Richiesta esplicita dell'utente.
- `DECISIONE` — **Doppio aggancio agli elementi: tabella lingue + fallback
  strutturale.** Le etichette coprono 10 lingue (inglese primario), ma sotto c'è
  un riconoscimento per forma — il pulsante effort è "quello espandibile dopo il
  pulsante modello", in qualunque lingua. Motivo: le traduzioni non-italiane non
  sono verificabili su questa macchina, quindi non possono essere l'unica difesa.
- `SCOPERTA` — **L'interfaccia dell'app segue la lingua del sistema: qui è in
  italiano.** Il pulsante effort è `Impegno: Alto`, non `Effort: High`. La
  SPEC.md dava per scontato l'inglese. `Usage:` invece resta in inglese.
- `BUG` `FIX` — **Il broker si auto-interrompeva.** Per chiudere i popup premeva
  Esc via `keybd_event`. In Claude Desktop Esc annulla il turno in corso: pilotando
  l'app da un task che gira *dentro* la stessa app, ogni chiusura di popup
  abbatteva il comando che la stava eseguendo. Sintomo osservato: "Background task
  interrotto", scambiato per interruzione dell'utente. Risolto chiudendo i popup
  con `ExpandCollapsePattern.Collapse()`; rimossa la P/Invoke di `keybd_event` per
  rendere l'errore irripetibile. Rimosso anche `SetForegroundWindow` in attach:
  le letture sono focus-free.
- `BUG` `FIX` — **PowerShell 5.1 tratta lo stderr di un comando nativo come
  errore fatale** e abbatteva la run. I log del broker finivano lì. Risolto
  instradando i log in un file di rapporto (`makeReport` in `client.js`).
- `FIX` — **Prestazioni: da minuti a 11 secondi.** Ogni finder richiamava una
  scansione completa dell'albero (~900 elementi, ogni proprietà è una chiamata
  cross-process) e una singola operazione ne faceva decine. Introdotta cache
  della scansione con invalidazione esplicita dopo ogni azione che muta la UI, e
  `ControlType`/`Name` letti una volta sola durante la scansione.
- `FIX` — **File `.ps1` forzato ad ASCII puro.** PowerShell 5.1 legge gli script
  come ANSI se non c'è il BOM: i caratteri accentati venivano mangiati e le
  virgolette curve risultanti spezzavano il parsing. I caratteri non-ASCII sono
  ora scritti come escape `\uXXXX`.
- `FIX` — **Verifica del cambio modello.** Confrontava l'etichetta del pulsante
  con il nome del menu comprensivo di decorazioni, e dichiarava fallito un cambio
  in realtà riuscito. La normalizzazione ora ancora il nome all'inizio della
  stringa.
- `SCOPERTA` — **I modelli nell'app sono 7, non 4.** Fable 5, Opus 4.8, Sonnet 5,
  Haiku 4.5 al primo livello; Opus 4.7, Opus 4.6, Sonnet 4.6 dietro la voce
  **"Altri modelli"**. Il sottomenu **non si apre con `ExpandCollapse`**: serve
  passarci sopra (hover). Le voci portano decorazioni da ripulire — il numero
  della scorciatoia (`Opus 4.8 2`) e, per Fable 5, `Richiede crediti di utilizzo`.
- `SCOPERTA` — **Il popup dell'effort non contiene i nomi dei livelli.** Dentro
  ci sono solo lo Slider e due didascalie agli estremi (`Più veloce` /
  `Più intelligente`). L'unico modo per enumerare i livelli è spostare il cursore
  e rileggere l'etichetta del pulsante: è un'operazione che modifica davvero lo
  stato, non una lettura.
- `SCOPERTA` — **Mappa del cambio completa, letta dal vivo.** Fable 5 / Opus 4.8 /
  Opus 4.7 / Sonnet 5: 6 marce (`Basso, Medio, Alto, Extra, Max, Ultracode`).
  Opus 4.6 / Sonnet 4.6: 4 marce (`Basso, Medio, Alto, Max` — salta `Extra`, non
  è la scala lunga troncata). Haiku 4.5: nessun controllo effort. Salvata in
  `backend/gearbox.json`.
- `SCOPERTA` — **La corsa del cursore si accorcia davvero** sui modelli ridotti
  (`0-3` invece di `0-5`): le posizioni in più non restano disabilitate,
  spariscono. Quindi il numero di marce è leggibile dall'app senza saperlo prima.
- `SCOPERTA` — **Le sessioni in sidebar si identificano dal pulsante compagno**
  `Altre opzioni per <titolo>`, che fornisce il titolo pulito; la riga cliccabile
  si ritrova per suffisso (è nominata `<stato> <titolo>`). Il formato `#N · nome`
  previsto da SPEC.md non esiste.
- `SETUP` — Round-trip completo verificato: la mappatura ha cambiato modello 7
  volte e spazzato il cursore, poi ha **ripristinato e riletto** lo stato
  iniziale (Opus 4.8 / Alto).

---

## 2026-07-20 (sessione 4 — spec GUI e divisione backend/frontend)

- `DECISIONE` — **Controllo modello: manopola rotante a 4 posizioni** (Haiku / Sonnet / Opus / Fable). Scartati pulsanti separati e levette. Motivo: scelta discreta tra 4 opzioni, il gesto "girare" è intuitivo e si abbina visivamente allo stick per l'effort senza sovrapporsi.
- `DECISIONE` — **Unico stick con doppio gesto: clic sinistro = sposta in H (effort), clic destro = ruota pomello (modello).** Il pomello in cima allo stick gestisce entrambi gli assi con distinzione netta via tasto mouse, evitando conflitti tra gesto lineare e gesto rotazionale. In Electron il menu contestuale del tasto destro viene disabilitato e il gesto diventa dedicato.
- `DECISIONE` — **Feedback discoverability: targhetta incisa sul pannello** con etichette "sin → cambia marcia / des → ruota modello". Stile engraved (testo piccolo, maiuscoletto, colore smorzato) — parte del design della plancia, non un tooltip aggiunto dopo.
- `DECISIONE` — **Sviluppo parallelo: backend e frontend assegnati a due collaboratori distinti.** Backend (UIA Broker) sviluppato da Simone; frontend (GUI Electron) sviluppato dall'altro collaboratore. I due lati verranno integrati in una fase successiva.
- `SCOPERTA` — **Nota per il collega frontend — gesti del pomello.** Nel prototipo `stick_demo.html` la prima implementazione con `mousedown`/`mousemove`/`mouseup` non rilevava il tasto destro: il drag di rotazione risultava inerte. Due correzioni necessarie: (1) usare **Pointer Events con `setPointerCapture`** invece dei mouse event — il tracking regge anche quando il cursore esce dal pomello; (2) calcolare la rotazione come **angolo assoluto verso il puntatore**, non come delta accumulato dal punto di partenza — il delta si sfasa e la rotazione diventa imprevedibile. Aggiunta anche la rotella come input alternativo al tasto destro. Il `contextmenu` va soppresso.

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
