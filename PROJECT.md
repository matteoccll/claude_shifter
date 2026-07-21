# MODEL AND FURIOUS — Direzione e obiettivo

> ⚠️ **A FINE SESSIONE È OBBLIGATORIO** chiedere all'utente se procedere con
> l'aggiornamento di questo file e di [STORICO.md](STORICO.md). Non aggiornare
> senza conferma, ma **non chiudere la sessione senza aver chiesto.**

> 📐 Specifica di build: **[SPEC.md](SPEC.md)** (autorevole su "cosa/come").
> Questo file dice *dove si va e perché*.

---

## 1. Cos'è

Cambio di marce fisico-simulato per Claude, come **software desktop autonomo**
(pattern claudeine: app nativa che parla con Claude ma è indipendente dalla sua
interfaccia). L'utente innesta una marcia sulla leva e cambia modello/effort
di una conversazione **dentro l'app Claude Desktop** (quella bianca dal logo),
scelta da un menu a tendina. **L'utente agisce solo sulla nostra leva**, mai
sul menu modello dell'app.

## 2. Obiettivo

GUI desktop autonoma che pilota Claude Desktop:

- un **widget d'angolo** (finestra nostra, sempre in vista, appoggiata sopra
  Claude) che **segue la conversazione attiva** — la chat si sceglie dalla
  **barra nativa di Claude**, non da una nostra tendina (vedi §4, decisione
  2026-07-21);
- **leva principale** → modello, **splitter** → effort;
- **cruscotto** con telemetria reale (context %, plan %).

Successo = cambiare marcia **guardando la strada**, sapendo su quale
conversazione si agisce prima di agire — il widget mostra sempre l'etichetta
della chat su cui sta per agire.

## 3. La meccanica reale (verificata dal vivo il 2026-07-20)

Bersaglio: **app Claude Desktop** (MSIX, Electron), pilotata via **Windows UI
Automation (UIA)**, non da terminale.

| Elemento | UIA | Azione |
|---|---|---|
| Modello corrente | `Button 'Opus 4.8'` | leggi etichetta |
| Menu modello | 4 `RadioButton` + sottomenu `Altri modelli` (altri 3) | hover sottomenu, poi `Select` |
| Effort corrente | `Button 'Impegno: Alto'` (**UI localizzata**) | leggi etichetta |
| Effort | popup con `Slider`, corsa variabile per modello | `RangeValue.SetValue` |
| Sessioni (tendina) | `Button '<stato> <titolo>'` + `Altre opzioni per <titolo>` | `Invoke` sulla riga |
| Telemetria | `Button 'Usage: context 6%, plan 32%'` **o** `context 127.5k` (token assoluti) — formato oscilla, resta in inglese | parse di entrambi i formati |

**Vincolo chiave:** modello ed effort valgono sulla **conversazione attiva** —
per cambiarla bisogna prima selezionarla in sidebar (la porta in primo piano),
poi agire.

**Vincolo (sessione 5) — niente input sintetico.** Il broker non invia mai
tasti alla finestra Claude: `Esc` annulla il turno in corso, e pilotare l'app
da un processo che gira dentro la stessa app si autodistrugge. Popup chiusi
con `ExpandCollapsePattern.Collapse()`.

### 3.1 La mappa del cambio (letta dal vivo)

| Modello | Marce splitter |
|---|---|
| Fable 5 · Opus 4.8 · Opus 4.7 · Sonnet 5 | 6 — Basso, Medio, Alto, Extra, Max, Ultracode |
| Opus 4.6 · Sonnet 4.6 | 4 — Basso, Medio, Alto, **Max** (salta Extra) |
| Haiku 4.5 | nessuna — no effort |

La corsa del cursore **si accorcia davvero** sui modelli ridotti (0-3 invece
di 0-5): le marce extra spariscono, non restano disabilitate. La GUI ricava
quindi la lunghezza della griglia dall'app invece di conoscerla in anticipo
(§4.1).

## 4. Architettura decisa — e la correzione di rotta

**Software desktop autonomo + attuazione UIA su Claude Desktop.** Provato sul
campo il 2026-07-20.

- **Enumerazione** (tendina): righe sidebar, identificate dal pulsante
  compagno `Altre opzioni per <titolo>`.
- **Lettura**: etichette dei `Button` UIA.
- **Attuazione**: modello = espandi → `Select` sul `RadioButton`; effort =
  espandi → `RangeValue.SetValue` sullo Slider. Verifica sempre rileggendo
  l'etichetta.

### 4.1 Principio: il backend rileva, non dichiara

Il broker **non contiene liste di modelli/effort**: le legge dall'app a ogni
richiesta e le passa alla GUI. Motivo: una lista scritta a mano diventa falsa
al primo aggiornamento di Claude, e il fallimento sarebbe silenzioso.
Conseguenza: **la leva non ha griglia fissa** — si ridisegna in base al
modello, gestendo Haiku dove lo splitter sparisce.

Stesso principio sugli agganci: tabella etichette per 10 lingue (inglese
primario) + riconoscimento per forma come rete di sicurezza (le traduzioni
non-italiane non sono verificabili su questa macchina).

### Perché non le altre / cosa è stato ribaltato

| Alternativa | Esito |
|---|---|
| **Attuatore da terminale (console injection)** | **RIBALTATO** — funzionante ma sul bersaglio sbagliato (Claude Code CLI). Materiale archiviato. |
| API/canale supportato | Non documentato per cambio a caldo. Si pilota la GUI. |
| Estensione web / injection nel renderer | Scartato: fragile / bersaglio sbagliato. Vale anche per "icona dentro la finestra di Claude": il widget è una **finestra nostra separata appoggiata sopra**, non un elemento iniettato in Claude. |
| Una leva per sessione | Scartato: caos. Una leva sola. |
| **Tendina per scegliere la chat** (dentro la nostra finestra) | **SCARTATO 2026-07-21** a favore del **widget d'angolo che segue la chat attiva**. Motivo: per l'utente medio l'attore principale è la chat, che naviga già dalla barra nativa di Claude — la tendina era un doppione. La leva resta una sola; agisce sulla conversazione attiva. |

## 5. Il cruscotto

`Usage: context X%, plan Y%` via UIA dà FUEL (context %) e uso piano.
Eventuale telemetria extra dai transcript locali (stile claudeine). Zero rete.

## 6. Il costo del cambio a caldo

Cambiare modello a metà conversazione costa (rilettura contesto a prezzo
pieno). Da verificare se l'app mostra un avviso nativo allo switch e se
anticiparlo nella GUI.

## 7. Principio non negoziabile

> **Il bersaglio è sempre visibile prima dello shift, mai dedotto dopo.
> Nessuno shift è "riuscito" senza conferma riletta dall'etichetta.**

Nota onesta: selezionare la sessione la porta in primo piano — l'UX va
costruita su questa verità, non nascosta.

## 8. Non-obiettivi / fuori scope v1

- Nessun broadcast, nessuna marcia automatica.
- Nessun targeting implicito oltre alla selezione esplicita in tendina.
- Non console injection nel terminale (bersaglio sbagliato, ribaltato).
- macOS/Linux, web, IDE: fuori scope.

## 9. Stato attuale

| Area | Stato |
|---|---|
| Bersaglio corretto (Claude Desktop MSIX) | ✅ |
| Enumerazione conversazioni (UIA sidebar) | ✅ Provata |
| Lettura modello/effort/telemetria | ✅ Provata — Usage in due formati (%, token), entrambi letti (sess. 7) |
| Switch modello | ✅ Provato su 7 modelli, ripristino verificato — ⚠️ submenu "Altri modelli" a volte non si apre, causa ignota, ora si ritenta da solo (sess. 15, §10) |
| Switch effort | ✅ Provato su tutte le posizioni, ripristino verificato |
| **Ladder effort completo** | ✅ Mappato dal vivo (§3.1), in `backend/gearbox.json`. Rimisurato sess. 8: identico |
| Attuazione senza rubare il focus | 🟡 Letture focus-free ✅; switch alzano l'app ⚠️ |
| **UIA Broker (M1)** | ✅ [`backend/`](backend/) — demone NDJSON, 10 comandi + diagnostici |
| **Backend su `main`** | ✅ Sess. 13 — 21 commit riversati con push diretto (PR saltata, scelta esplicita utente). M1 riconfermato (Opus 4.8: PASSATO) |
| Comando `capabilities` | ✅ **~1,9–2,2 s** dopo i fix sess. 16 (era ~3,6 s sess. 14, 6–15 s prima). Cronometro per sezione su stderr |
| Impennata sporadica a ~10 s | ✅ Tetto sceso a **~4 s** (sess. 16): `OpenEffortPopup` fail-fast, provato dal vivo sul caso patologico del submenu (`4 -> 0`) — `capabilities` in 3,89 s. Causa originaria del picco resta ignota, non serve più spiegarla |
| **Collaudo M1 (`test.js`)** | ✅ Sess. 12 — distingue scala letta/assente/non letta (`hasControl`); verde senza effort si chiama "PASSATO SENZA EFFORT" |
| **`selectSession` conferma il bersaglio** | ✅ Sess. 12 — risponde `{title}`, non sporca più stdout |
| **Guasti distinti dagli stati normali** | ✅ Sess. 11 — lettura mancata finisce in `errors`, `hasControl` distingue i due casi |
| **Nessuna richiesta resta appesa** | ✅ Sess. 11 — scadenza per richiesta, rifiuto immediato se broker morto |
| Riaggancio automatico | ✅ Rilevamento su morte reale (`alivecheck.ps1`), riaggancio 3/3 (`reattach.js`) |
| Finestra giusta fra le più di Claude | ✅ Si aggancia solo dove il pulsante modello esiste |
| **Comandi malformati non fanno danni** | ✅ Sess. 10 — argomento mancante rifiutato, non interpretato |
| L'attuazione non ruba il puntatore | ✅ Rimesso dov'era (scarto 0 px) |
| Spec di build | ✅ [SPEC.md](SPEC.md) (⚠️ §2/§4.1 superati da sess. 5, vedi §3 qui) |
| Prototipo UIA | ✅ [`prototype/`](prototype/) |
| GUI (frontend) | ⬜ In carico all'altro collaboratore — via libera dalla leva + cruscotto sulla conversazione attiva (sess. 11). **Forma decisa (2026-07-21): widget d'angolo che segue la chat attiva, niente tendina** (§4) |

---

## 10. Da fare

**Nessun difetto backend/sessione resta aperto** — tutto chiuso fino a
sess. 14. Via libera al frontend.

### Cosa può fare il frontend, adesso

Si parte **dalla leva e dal cruscotto sulla conversazione attiva** — che è
anche la forma finale decisa (widget d'angolo, niente tendina, §4):
`capabilities` è provata e stabile, copre le due forme della leva (6 marce /
Haiku senza splitter), ed espone gli eventi
`attached`/`reattached`/`detached`.

Vincoli da progettare, non da aggirare:

- **Lentezza**: `capabilities` ~1,9–2,2 s (sess. 16, era ~3,6 s), `setModel`
  ~1,6 s, cambio marcia completo ~4 s nel caso normale. Tetto dell'impennata
  sceso da ~10 s a ~4 s (sess. 16); scattare comunque può, in ~4 s. Serve uno
  stato "sto innestando" onesto; la scadenza per richiesta non annulla il
  lavoro del broker, smette solo di aspettarlo.
- **Un `setModel` fallito non prova più (di regola) che il modello non
  esista** (bug submenu, sotto): sess. 15 ha aggiunto un ritentativo
  automatico da un popup fresco. La GUI può ancora trovarsi davanti un
  fallimento vero se anche il secondo tentativo inciampa nello stesso bug.
- **`gears: 0` da solo non basta**: guardare anche `effortRange.hasControl`
  o `errors`.

La **tendina è scartata** (decisione 2026-07-21, §4): la chat si sceglie dalla
barra nativa di Claude e il widget segue quella attiva. `selectSession` /
`enumerate` non servono più al flusso base — restano disponibili nel broker
come funzioni opzionali. Quel che invece **resta necessario** è che il widget
sappia *quale* chat è attiva per mostrarne l'etichetta: quindi la verifica
*forte* del bersaglio (e il rischio di match per suffisso in `SessionEntries`,
rimandati in sess. 7) va comunque chiusa, ora sulla lettura della chat attiva
più che sulla selezione da tendina.

Le due metà del riaggancio sono provate **separatamente**, non insieme
(chiudere l'app per davvero chiuderebbe anche chi collauda) — è il massimo
ottenibile su questa macchina; `detachtest.js` chiude il cerchio da fuori
Claude.

**Bug aperto senza causa nota (sess. 8), sintomo attenuato in sess. 15**: il
submenu "Altri modelli" a volte non si apre (`4 -> 0` nel log, menu sparisce
invece di espandersi). Non riproducibile a comando — la causa resta ignota.
`setModel`/`listModels` ora ritentano una volta l'intera sequenza
apri-popup→espandi da zero prima di arrendersi (stesso schema di
`OpenEffortPopup`), il che assorbe la maggior parte dei casi osservati finora,
ma non è una correzione della causa: un secondo inciampo consecutivo resta
possibile e la GUI deve saperlo.

### Idee raccolte — frontend / GUI

- **Cruscotto dei consumi**: context%/token dalla chat, sorgente già letta
  (`readUsage`).
- **Cambio giocattolo per Haiku**: leva stile giocattolo quando innestato
  Haiku 4.5 — ironia sul modello meno potente, si sposa col vincolo reale che
  Haiku non ha splitter (§3.1).

---

> ⚠️ **PROMEMORIA FINALE — TASSATIVO**
> Prima di chiudere la sessione, chiedere all'utente:
> **"Aggiorno PROJECT.md e STORICO.md con quanto fatto oggi?"**
> Attendere conferma esplicita. Non aggiornare d'iniziativa, non saltare la domanda.
