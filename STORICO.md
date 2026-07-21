# STORICO

> ⚠️ **A FINE SESSIONE È OBBLIGATORIO** chiedere all'utente se procedere con
> l'aggiornamento di questo file e di [PROJECT.md](PROJECT.md). Non aggiornare
> senza conferma, ma **non chiudere la sessione senza aver chiesto.**

Registro cronologico delle sessioni. **Solo date e azioni eseguite**: bug, fix,
decisioni. Niente piani, niente intenzioni — quelli stanno in
[PROJECT.md](PROJECT.md).

## Regole di scrittura

- Voce nuova **in cima**, formato data `AAAA-MM-GG`.
- Ogni riga è **una cosa che è successa**, al passato.
- Tag ammessi: `DECISIONE` · `FIX` · `BUG` · `SETUP` · `SCOPERTA` · `SCARTATO`
- Le decisioni riportano il **motivo**, non solo l'esito.
- Non riscrivere le voci passate. Se una decisione viene ribaltata, si aggiunge
  una voce nuova che la ribalta.

---

## 2026-07-21 (sessione 14 — backend: la lentezza, due fix misurati dal vivo)

- `FIX` — **La scansione UIA pagava una chiamata cross-process per elemento.**
  `Walk` camminava l'albero a mano (`GetFirstChild`/`GetNextSibling`, `Name`/
  `ControlType` uno alla volta): su ~1000 elementi, migliaia di round-trip,
  ~1 s a scansione, e `capabilities` ne fa una dozzina. Sostituito con
  `CacheRequest` + `GetUpdatedCache`: un solo round-trip tira giù il
  sottoalbero, la DFS legge tutto in locale da `.CachedChildren`/`.Cached.*`.
  Stesso ordine di documento, modalità `Full` (handle restano azionabili).
  Effetto: `capabilities` da **6–15 s variabili a ~4,6 s stabile**.
- `FIX` — **Apertura submenu "Altri modelli": hover prima di
  `ExpandCollapse`.** Su questa app `ExpandCollapse` non apre **mai** il
  submenu (torna successo senza effetto, `4 -> 4`, 900 ms buttati); solo
  l'hover porta a casa i 3 modelli nascosti. Invertito l'ordine: hover primo,
  `ExpandCollapse` fallback (tenuto per host senza mouse). Effetto:
  `capabilities` **~4,6 → ~3,6 s**.
- `SETUP` — Misurato dal vivo (Opus 4.8/Alto): `setModel` **~1,6 s** (era
  2,5–7,6 s), cambio marcia completo **~5,1 s** (era 9–20 s). `test.js` M1
  PASSATO col codice nuovo. **Mai selezionato Fable; marce rimesse a posto.**
  Cache validata anche su albero UIA reale: 59 nodi in 80 ms.
- `SCOPERTA` — **Resta un'impennata sporadica a ~10 s** su `capabilities` dopo
  un cambio modello (10,6 s vs 4,7 s): non è la scansione, è il menu che tarda
  a comparire. Le attese fisse (`Start-Sleep`) restano tarate dal vivo, non
  toccate.

## 2026-07-21 (sessione 13 — backend su main + ricollaudo M1)

- `DECISIONE` — **Backend spinto direttamente su `main`, saltando la PR.**
  L'utente ha chiesto — con permesso esplicito — push diretto dei 21 commit di
  `simone_fullstack_branch` per sbloccare subito il frontend. Conseguenza:
  arriva su `main` (condiviso con `matteoccll`) **senza sua revisione** —
  scelta esplicita, non svista. Fast-forward, no `--force`; `origin/main` =
  `3a30f75`.
- `SETUP` — Ricollaudo M1 dal vivo (Opus 4.8/Alto/cursore 2): `enumerate` (1
  sessione), `setModel` Opus↔Sonnet, `setEffort` 2↔1, stato ripristinato.
  **Esito: PASSATO.** Mai Fable.
- `SETUP` — `selectSession` non esercitato: sidebar con 1 sola conversazione,
  giro andata/ritorno saltato (serve una seconda sessione).

## 2026-07-21 (sessione 12 — backend: chiusi i due difetti aperti + collaudo dal vivo)

- `FIX` — **`selectSession` non sporca più l'NDJSON e conferma il
  bersaglio.** Il dispatch chiamava `Op-SelectSession` senza catturarne il
  risultato → la hashtable finiva su stdout come tabella (leak), risposta al
  client `null` (contro il principio §7 di PROJECT). Chiuso catturando in
  `$sel`. Verificato sul broker grezzo: 0 righe non-JSON, risposta
  `{title:"..."}`.
- `FIX` — **`test.js` non dichiara più "PASSATO" saltando l'effort.** Lo skip
  guardava solo `startLevel === null`, confondendo "no splitter" (Haiku, skip
  ok) con "scala non letta" (guasto) — stessa trappola già chiusa in `map.js`
  con `hasControl`. Ora 3 casi distinti: letta → collauda `setEffort`;
  assente → skip onesto "PASSATO SENZA EFFORT"; presente-ma-non-letta → FAIL.
- `SETUP` — Collaudato tutto il backend, 2 giri (Opus 4.8/Alto/cursore 2):
  `state`, `probe`, `capabilities` (6 marce, 7 modelli, `errors` vuoto,
  10%/41%), `fastmode`, `reattach` 3/3, `test.js` M1 completo (`enumerate` 2
  sessioni, `selectSession` andata/ritorno, `setModel`/`setEffort`
  ripristinati). Ramo Haiku provato ("PASSATO SENZA EFFORT"). Mai Fable.
- `SCOPERTA` — **Sidebar con 2 conversazioni**: primo giro completo di
  `selectSession` dentro `test.js` (sess. 11 ne vedeva 1 sola). Nessuna
  collisione fra "Untitled session"/"(fork)": match per uguaglianza esatta.
- `SETUP` — Non rilanciati apposta: `map.js` (seleziona anche Fable, vietato
  nei collaudi, `gearbox.json` già validata), `detachtest.js` (serve l'app
  chiusa da terminale esterno, non fattibile da dentro).

## 2026-07-21 (sessione 11 — backend: collaudo per il via libera al frontend)

- `SETUP` — Collaudato tutto il backend per rispondere a: si può cominciare il
  frontend? Passati `capabilities`, `probe`, `state`, `dump`, `test.js`,
  `enumerate`, `selectSession`, `setModel`/`setEffort` andata/ritorno, Haiku
  senza splitter, riaggancio, 11 comandi malformati, 2 comandi in parallelo,
  morte del broker, 7 min di inattività. **Nessun comando malformato ha
  cambiato lo stato dell'app**; marce rimesse a posto.
- `BUG` `FIX` — **`capabilities` dichiarava "0 marce" su un modello con 6,
  `errors` vuoto.** La lettura del cursore non si apriva, e `Op-EffortRange`
  in quel caso risponde educatamente `available: false` senza eccezione:
  scattava solo nel `catch`, quindi il guasto viaggiava sulla strada buona. Una
  GUI fidata avrebbe disegnato la leva-senza-splitter (Haiku) su un modello che
  lo splitter ce l'ha. Chiuso: ogni lettura mancata (pulsante presente) finisce
  in `errors`; `OpenEffortPopup` ritenta una volta prima di arrendersi. Haiku
  mai ritentato.
- `SETUP` — Ramo riparato forzato su una copia col popup che non si apre mai:
  copia guasta → `gears 0` + errore esplicito, broker vero → `gears 6` +
  `errors` vuoto, Haiku → `errors` vuoto. Le tre risposte distinguibili a
  macchina.
- `BUG` `FIX` — **Una richiesta a un broker morto non tornava mai** (né
  risposta né errore, passava solo tempo): `withDeadline` ammazzava l'intero
  processo, utile per uno script ma non per una GUI (leva bloccata su "sto
  cambiando" senza uscita). Chiuso con scadenza per singola richiesta (2 min
  base, regolabile), rifiuto immediato su broker già morto, ascoltatore
  sull'errore di scrittura. Verificato: rifiuto in pochi ms, scadenza forzata
  a 1,5 s scatta a 1504 ms.
- `SCOPERTA` — **Il contatore dei consumi ha cambiato formato durante la
  sessione stessa** (`context 112.8k` → `context 15%, plan 92%`), a conferma
  dei due formati già noti dalla sess. 7. Il broker li legge entrambi.
- `SCOPERTA` — Il submenu "Altri modelli" **non si è aperto con
  `ExpandCollapse` nemmeno una volta** in tutte le prove (`4 -> 4` ogni
  volta): solo l'hover fisico lo salva.
- `SCOPERTA` — Tempi misurati: `capabilities` 6–15 s, `setModel` 2,5–7,6 s,
  `selectSession` ~1,3 s, `effortRange` ~0,8 s, `readGear` ~0,2 s. Cambio
  marcia completo: 9–20 s (la griglia va richiesta di nuovo dopo ogni cambio
  modello). La scadenza per richiesta **non annulla** il lavoro del broker,
  smette solo di aspettarlo.
- `SCOPERTA` — 7 minuti di inattività non degradano l'aggancio.
- `BUG` — **`selectSession` non dice su cosa ha agito** (risponde `null`, il
  dispatch butta il titolo) e **sporca stdout** con una tabella PowerShell in
  mezzo all'NDJSON. Innocuo oggi (il client scarta le righe non-JSON) ma
  contro il principio §7. Lasciato aperto.
- `BUG` — **`test.js` scrive "PASSATO" senza aver mai provato `setEffort`**
  (stessa trappola già chiusa in `map.js` con `hasControl`, mai riportata
  qui). Lasciato aperto.
- `SCOPERTA` — `enumerate` trova **1 sola conversazione**: legge la sidebar
  del momento, non l'archivio delle chat.
- `DECISIONE` — **Il frontend parte dalla leva/cruscotto sulla conversazione
  attiva, non dalla tendina.** Motivo: `capabilities` è provata e stabile, il
  targeting per sessione (`enumerate`, `selectSession`) è ancora la parte più
  debole.

## 2026-07-21 (sessione 10 — backend: controllo generale e quattro difetti chiusi)

- `SETUP` — Controllo generale: parse di `broker.ps1`, sintassi dei 13 file
  JS, `capabilities` (5,8 s, 7 modelli col submenu ad hover), `reattach` 2/2,
  `test.js` M1 passato con ripristino, batteria sui rami d'errore (comando
  ignoto, modello inesistente, effort fuori scala, sessione inesistente):
  tutti puliti, **nessuno ha cambiato lo stato dell'app**.
- `BUG` `FIX` — **`setModel` senza il nome innestava Fable 5.** Il match "a
  somiglianza" di `FindModelOption` degenerava in `-like "*"` (accetta tutto,
  prende la prima voce del menu), e la verifica **passava** (rileggeva "Fable
  5", rispondeva `ok`). Un campo `undefined` lato GUI sparisce dal JSON senza
  rumore: il caso era a una riga di distanza. Chiuso con 3 sbarramenti: il
  jolly non degenera più (nome vuoto → nessun match), `Op-SetModel` rifiuta
  prima di aprire il menu, il dispatch controlla che il campo sia arrivato.
- `BUG` `FIX` — **`setEffort` senza il livello scendeva al minimo in
  silenzio.** `[int]$null` vale `0`, dentro la scala, quindi il controllo
  "fuori range" non scattava. Aggiunto `ReqArg`, che distingue "campo assente"
  da "campo presente e zero". Il livello deve anche essere un intero (`"alto"`
  e `2.7` respinti). Verificato che `level: 0` continui a passare.
- `FIX` — **Il puntatore non veniva restituito.** Aprire il submenu richiede
  hover vero: ogni `capabilities` trascinava il mouse e lo lasciava lì (la GUI
  chiama `capabilities` dopo ogni cambio marcia). Ora la posizione è salvata
  al primo movimento e rimessa a fine comando in un `finally` (anche sui
  comandi falliti a metà), mai fra un movimento e l'altro.
- `SCOPERTA` — **`$home` in PowerShell è riservata** (confronto nomi
  insensibile alle maiuscole): la variabile del fix precedente collideva,
  produceva un errore non terminante a ogni comando e mandava il puntatore a
  0,0 — peggio del problema di partenza. Rinominata `$origin`. Stessa famiglia
  di `$PID` (già evitata con `$script:pid0`). Setacciato tutto il file:
  nessun'altra collisione.
- `SETUP` — Ripristino del puntatore **misurato**: 640,400 → `capabilities.js`
  → rilettura 640,400, scarto 0 px. Il difetto `$home` era invisibile ai
  collaudi verdi (guardavano la marcia, non il mouse), emerso dal rumore su
  stderr.
- `BUG` `FIX` — **`map.js` si fidava della lista modelli** senza la
  normalizzazione che `capabilities()` ha già (PowerShell 5.1 collassa un
  array di 1 elemento in oggetto singolo: con un solo modello `forEach`
  esplode). Aggiunto `listModels()` al client, sempre array.

## 2026-07-21 (sessione 9 — backend: chiusi i due difetti di `map.js`)

- `BUG` `FIX` — **Un modello storto buttava all'aria l'intera mappatura.** In
  `map.js` il `setModel` di ogni giro era protetto da `try`, il `probeEffort`
  no: un suo errore risaliva al `finally`, perdendo anche i modelli già
  misurati. Ora stesso trattamento: errore scritto nel report, modello contato
  fra i non misurati, giro che continua.
- `BUG` `FIX` — **Lo script usciva 0 anche a mappa incompleta.** Il ramo
  protettivo di sess. 8 rifiutava di sovrascrivere `gearbox.json` ma
  restituiva comunque successo. Ora la mappa monca esce **3** (codici: 0
  completa, 1 fatale, 2 deadline, 3 incompleta), via `process.exitCode` (non
  `exit()`) così il report resta scritto.

## 2026-07-21 (sessione 8 — backend: collaudo completo e la mappa che si cancellava)

- `SETUP` — Collaudato l'intero backend: `state`, `probe`, `capabilities`,
  `fastmode`, `popup`, `effortpopup`, `dump`, `tree` tutti passati; `reattach`
  3/3 (~850 ms l'uno); `test.js` 6/6 con ripristino confermato. `selectSession`
  saltato (1 sola conversazione in sidebar).
- `BUG` — **`map.js` ha cancellato la mappa buona.** Una run in cui i 3
  modelli dietro "Altri modelli" non si sono lasciati raggiungere ha comunque
  riscritto `gearbox.json`, sostituendo le scale di 4 modelli con messaggi
  d'errore (97 righe perse, 6 aggiunte). Scrittura incondizionata. Recuperato
  da git (HEAD).
- `DECISIONE` `FIX` — **`gearbox.json` si scrive solo a mappa completa.** Un
  solo modello non misurato → file buono intatto, risultato zoppo in
  `gearbox-partial.json` (in `.gitignore`, è uno scarto diagnostico). Motivo:
  la mappa è l'unica misura completa esistente, non un log. Scartata
  l'alternativa di fondere vecchio+nuovo (spaccerebbe misure di ieri per
  misure di oggi, contro "il backend rileva, non dichiara", PROJECT §4.1).
- `SCOPERTA` `FIX` — **Due risposte vuote si somigliano**: "modello senza
  effort" (Haiku, misura riuscita) e "effort non apertosi" (fallimento),
  distinguibili solo dal testo inglese di `reason`. Aggiunto il campo
  `hasControl` (leggibile a macchina) in `Op-EffortRange`, `Op-ProbeEffort`,
  `Op-Capabilities`.
- `BUG` — **Il submenu "Altri modelli" a volte non si apre, causa ignota.**
  Log: `4 -> 0` (il menu sparisce dopo `Expand()` invece di espandersi),
  tentativi successivi trovano un elemento senza punto cliccabile. Non
  riproducibile a comando (funzionato 4/4 e poi 7/7 in prove isolate). Resta
  aperto, ma non fa più danni permanenti.
- `SCOPERTA` — **Il degrado era un incidente**, non un cambiamento dell'app:
  la rimappatura completa ha prodotto un `gearbox.json` identico al precedente
  (solo timestamp diverso).
- `SETUP` — Ramo protettivo forzato con un modello inesistente su una copia
  dello script: Haiku misurato e non contato come buco, modello fasullo
  contato, scritto solo il parziale, SHA256 di `gearbox.json` identico
  prima/dopo.
- `DECISIONE` — **Rinviati apposta gli altri due difetti di `map.js`**
  (`probeEffort` non protetto, script che esce sempre 0): due politiche
  opposte per lo stesso tipo di guasto.

## 2026-07-20 (sessione 7 — backend: collaudo dal vivo e sei riparazioni)

- `SETUP` — Collaudato l'intero backend **prima** di toccare il codice:
  `state`, `probe`, `capabilities`, `reattach` (3/3, ~0,8 s l'uno), catena M1
  completa (`enumerate` → `selectSession` andata/ritorno → `setModel`
  andata/ritorno → `setEffort` andata/ritorno) con verifica a ogni passo e
  ripristino confermato.
- `BUG` `FIX` — **Il cruscotto era cieco e non lo diceva.** Il contatore
  oscilla fra due formati (`Usage: context 14%, plan 32%` /
  `context 127.5k, plan 41%`), `readUsage` capiva solo la percentuale, e
  `capabilities` restituiva il cruscotto vuoto **senza registrarlo in
  `errors`**. Ora il parser legge entrambi i formati (e la virgola decimale),
  riporta il testo grezzo, e un cruscotto assente/illeggibile compare in
  `errors`.
- `BUG` `FIX` — **`test.js` era morto**, e con lui il collaudo di
  `selectSession`: parlava il protocollo di due generazioni fa (`{sessions}`
  invece di `{count,text}`) e crollava al passo 1 con un TypeError muto.
  Riscritto sul client condiviso con verifica per passo e auto-ripristino:
  7/7 in 25 s.
- `SCOPERTA` `FIX` — **I cercatori di menu pescavano la chat.** I punti
  elenco markdown si renderizzano come `ListItem` e precedono il menu
  nell'ordine del documento: il broker ha restituito come "interruttore fast
  mode" il testo di un messaggio della chat. I cercatori ora accettano solo
  `MenuItem`/`RadioButton` veri (verificato col dump).
- `BUG` `FIX` — **`fastMode` agiva alla cieca.** Lo stato del toggle non era
  mai leggibile, e il ramo `set` attuava comunque assumendo "spento",
  dichiarando `changed=true` senza verifica. Ora rifiuta esplicitamente se la
  voce manca o lo stato non si legge; la lettura resta permessa.
- `FIX` — **`ModelBtn` non si fida più del solo nome.** La sidebar precede la
  leva nell'ordine del documento: un titolo auto-generato che inizia per
  Sonnet/Opus/Haiku/Fable sarebbe stato scambiato per il pulsante modello
  (visto "Prompt efficace per Fable 5" in sidebar). Ora il candidato deve
  esporre anche `ExpandCollapsePattern` (riga sessione → False, leva → True).
- `FIX` — **`setEffort` ora verifica, `probeEffort` verifica la cosa
  giusta.** `setEffort` rispondeva ok con qualunque etichetta rimasta sul
  pulsante; ora rilegge la posizione del cursore e fallisce se non coincide
  (riapre il popup una volta se si è chiuso da solo). `probeEffort` non
  controllava di aver riletto *quella* etichetta di partenza, solo *una*
  etichetta qualsiasi — terza "verifica che non verificava" del progetto; ora
  confronta con l'etichetta letta dalla spazzata stessa.
- `FIX` — **Minuzie del client.** `start()` rigetta se PowerShell non parte o
  il broker muore prima dell'aggancio; `withDeadline` accetta report nullo e
  scrive su stderr; `state.js` passava la label al posto del report (TypeError
  muto al timeout); rimosso un watchdog mai assegnato; corretti due commenti
  obsoleti.
- `DECISIONE` — **Lasciati fuori apposta, perché prematuri:** la verifica
  forte di `selectSession` (serve un segnale affidabile di "conversazione
  attiva") e il match dei titoli per suffisso in `SessionEntries` (un titolo
  che è suffisso di un altro può agganciare la riga sbagliata). Rischi noti,
  da riprendere con la GUI.
- `SCOPERTA` — **`detachtest.js` risulta lanciato e abbandonato** (report
  delle 23:06, 16 giri ok, troncato senza esito, app mai chiusa durante la
  run).
- `SCOPERTA` — **Limite noto:** se una chiamata UIA si pianta, la deadline
  uccide lo script Node ma il figlio PowerShell resta orfano. Non provocabile
  senza rischiare l'app che ospita il collaudo.

## 2026-07-20 (sessione 6 — backend: i due pezzi mancanti del broker)

- `SETUP` — Aggiunto il comando **`capabilities`**: marcia innestata, effort
  corrente, numero di marce del modello attivo, elenco modelli con
  `enabled`/`selected`, telemetria. Provato dal vivo: 7 modelli, Opus
  4.8/Alto, 6 marce (cursore 0-5), 9%/32%, in 9,9 s.
- `DECISIONE` — **`capabilities` risponde solo per il modello attivo, non per
  tutti.** Una tabella completa richiederebbe 7 cambi marcia a ogni chiamata,
  sarebbe una dichiarazione — vieta "il backend rileva, non dichiara". La GUI
  richiama dopo ogni `setModel`.
- `DECISIONE` — **Fallimento parziale riportato per sezione, non fallimento
  totale.** `capabilities` torna quel che riesce a leggere + lista `errors`.
  Una GUI con modelli ma senza corsa dell'effort può disegnare qualcosa di
  onesto.
- `SETUP` — Aggiunto il **riaggancio automatico**: prima di ogni comando il
  broker verifica handle valido → processo vivo `Claude` → radice UIA che
  risponde; se caduto, si rilega ed emette `reattached` (o `detached` se
  l'app non c'è). Prima restava legato a una finestra morta finché non
  riavviato a mano.
- `DECISIONE` — **Il riaggancio non rilancia l'app** (`$Launch`: vero
  all'avvio, falso al riaggancio). Motivo: se l'utente ha chiuso Claude
  apposta, riaprirgliela addosso è peggio di un errore chiaro.
- `DECISIONE` — **Non si controlla se `FindClaudeHwnd` restituisce ancora *il
  nostro* handle**: con 2 finestre Claude aperte quel confronto oscillerebbe
  a ogni comando.
- `SCOPERTA` — **Il collaudo onesto del riaggancio non è eseguibile
  dall'interno** (il broker si aggancia allo stesso processo che ospita chi lo
  pilota). Aggiunto `forceDetach` (butta l'aggancio senza toccare l'app) e
  `reattach.js`: 3/3, ~1,4 s l'uno. Copre il recupero, non il rilevamento
  della morte del processo.
- `SETUP` — Scritto `detachtest.js` per il ramo non coperto (va lanciato da
  terminale esterno, app chiusa/riaperta a mano). **Non ancora eseguito.**
- `SETUP` — Aggiunto `capabilities.js` (collaudo di sola lettura) e inoltro
  degli eventi del broker al client Node (`onEvent`): la GUI vede
  `attached`/`reattached`/`detached` senza interrogare.
- `SCOPERTA` — **PowerShell 5.1 collassa un array di 1 elemento in oggetto
  singolo** nel JSON. `Broker.capabilities()` normalizza `models`/`errors` con
  `[].concat(...)`.
- `SCARTATO` — **Provare il riaggancio chiudendo Claude Desktop a mano.**
  Chiudere la finestra non chiude l'app (Electron la tiene viva), chiuderla
  davvero chiude anche chi collauda (stessa app). Impraticabile per
  costruzione. `detachtest.js` resta per una macchina dove chi collauda non è
  dentro l'app.
- `SETUP` — Scritto `alivecheck.ps1`: prova le 3 verifiche di `IsAlive` su una
  cavia uccidibile davvero (finestra vuota), non su Claude. Esito: passato.
- `BUG` `FIX` — **La 3ª verifica di `IsAlive` non verificava niente.**
  `$root.Current.Name` risponde da una copia in memoria anche a processo
  morto (mostrava `True` su un cadavere). Sostituita con
  `GetCurrentPropertyValue(NameProperty)`, che solleva eccezione se non c'è
  più nessuno.
- `BUG` `FIX` — **Il riaggancio prendeva la finestra sbagliata.**
  `FindClaudeHwnd` restituiva la prima finestra Claude, il criterio di
  risveglio era un conteggio elementi (`> 40`): una finestra secondaria con 49
  elementi e nessuna leva passava il controllo, ogni comando falliva con
  "elements not found". Sostituito con `FindClaudeWindows`: le elenca tutte,
  prova dalla più grande, accetta solo quella col pulsante modello. Se nessuna
  ce l'ha, ripiega sulla più ricca e lo logga.
- `SCOPERTA` — **Cavie di collaudo scartate su Windows 11**: Blocco note
  (Store app, il processo lanciato termina subito), `cmd.exe` (non possiede
  più la finestra, la tiene il Terminale). Serve una finestra WinForms da un
  secondo processo PowerShell.

## 2026-07-20 (sessione 5 — backend: UIA Broker costruito e mappa del cambio)

- `SETUP` — Costruito il **UIA Broker** in `backend/` come demone persistente
  (`broker.ps1`, NDJSON su stdin/stdout) + client Node (`client.js`) +
  strumenti (`state.js`, `dump.js`, `tree.js`, `effortpopup.js`, `map.js`).
  Comandi: `enumerate`, `readGear`, `readUsage`, `selectSession`, `setModel`,
  `setEffort`, `listModels`, `effortRange`, `probeEffort` + diagnostici.
- `DECISIONE` — **Broker in PowerShell, non .NET/C#.** `dotnet` non
  installato sulla macchina, PowerShell 5.1 espone già
  `System.Windows.Automation` nativamente. Zero installazioni, riusa la
  logica dei prototipi.
- `DECISIONE` — **Rilevamento dinamico invece di tabelle scritte a mano.** Il
  broker legge modelli/effort dall'app a ogni richiesta, non li dichiara. Una
  lista hardcoded diventa falsa al primo aggiornamento di Claude, fallimento
  silenzioso. Richiesta esplicita dell'utente.
- `DECISIONE` — **Doppio aggancio agli elementi: tabella lingue + fallback
  strutturale.** Tabella etichette per 10 lingue (inglese primario), più un
  riconoscimento per forma (il pulsante effort è "quello espandibile dopo il
  pulsante modello", in qualunque lingua). Le traduzioni non-italiane non sono
  verificabili qui.
- `SCOPERTA` — **L'interfaccia segue la lingua di sistema**: qui italiano
  (`Impegno: Alto`, non `Effort: High`). SPEC.md dava per scontato l'inglese.
  `Usage:` resta in inglese.
- `BUG` `FIX` — **Il broker si auto-interrompeva.** Chiudeva i popup con Esc
  via `keybd_event`, ma in Claude Desktop Esc annulla il turno in corso:
  pilotando l'app da un task che gira dentro la stessa app, ogni chiusura
  popup abbatteva il comando in corso ("Background task interrotto",
  scambiato per interruzione utente). Risolto con
  `ExpandCollapsePattern.Collapse()`; rimossa la `keybd_event`. Rimosso anche
  `SetForegroundWindow` in attach (letture focus-free).
- `BUG` `FIX` — **PowerShell 5.1 tratta lo stderr di un comando nativo come
  errore fatale**, abbatteva la run (i log del broker finivano lì). Risolto
  instradando i log in un file di rapporto (`makeReport` in `client.js`).
- `FIX` — **Prestazioni da minuti a 11 s.** Ogni finder scansionava l'intero
  albero (~900 elementi, ogni proprietà cross-process) e un'operazione ne
  faceva decine. Aggiunta cache della scansione con invalidazione dopo ogni
  azione che muta la UI.
- `FIX` — **File `.ps1` forzato ad ASCII puro.** PowerShell 5.1 senza BOM
  legge come ANSI (accentate mangiate, virgolette curve spezzano il
  parsing). Caratteri non-ASCII come escape `\uXXXX`.
- `FIX` — **Verifica del cambio modello** confrontava l'etichetta col nome
  del menu comprensivo di decorazioni, dichiarando fallito un cambio riuscito.
  La normalizzazione ora ancora il nome all'inizio della stringa.
- `SCOPERTA` — **I modelli sono 7, non 4**: Fable 5/Opus 4.8/Sonnet 5/Haiku
  4.5 al primo livello, Opus 4.7/Opus 4.6/Sonnet 4.6 dietro "Altri modelli"
  (non si apre con `ExpandCollapse`, serve hover). Voci con decorazioni da
  ripulire (scorciatoia, "Richiede crediti di utilizzo" per Fable).
- `SCOPERTA` — **Il popup effort non contiene i nomi dei livelli**, solo
  Slider + 2 didascalie agli estremi ("Più veloce"/"Più intelligente").
  L'unico modo per enumerare i livelli è spostare il cursore e rileggere
  l'etichetta del pulsante (operazione che muta lo stato).
- `SCOPERTA` — **Mappa del cambio completa**, letta dal vivo (vedi PROJECT
  §3.1), salvata in `backend/gearbox.json`.
- `SCOPERTA` — **La corsa del cursore si accorcia davvero** sui modelli
  ridotti (0-3): le posizioni extra spariscono, non restano disabilitate.
- `SCOPERTA` — **Le sessioni in sidebar si identificano dal pulsante
  compagno** `Altre opzioni per <titolo>` (titolo pulito); la riga cliccabile
  si ritrova per suffisso (`<stato> <titolo>`). Il formato `#N · nome`
  previsto da SPEC.md non esiste.
- `SETUP` — Round-trip completo verificato: la mappatura ha cambiato modello
  7 volte e spazzato il cursore, poi ha **ripristinato e riletto** lo stato
  iniziale (Opus 4.8/Alto).

---

## 2026-07-20 (sessione 4 — spec GUI e divisione backend/frontend)

- `DECISIONE` — **Controllo modello: manopola rotante a 4 posizioni** (Haiku/
  Sonnet/Opus/Fable). Scartati pulsanti separati e levette: scelta discreta
  fra 4, gesto "girare" intuitivo, si abbina visivamente allo stick
  dell'effort.
- `DECISIONE` — **Unico stick con doppio gesto: clic sinistro = sposta in H
  (effort), clic destro = ruota pomello (modello).** Distinzione netta via
  tasto mouse; menu contestuale destro disabilitato in Electron.
- `DECISIONE` — **Feedback discoverability: targhetta incisa** "sin → cambia
  marcia / des → ruota modello", stile engraved (testo piccolo maiuscoletto,
  colore smorzato), parte del design plancia.
- `DECISIONE` — **Sviluppo parallelo**: backend (Simone) e frontend (altro
  collaboratore), integrazione in fase successiva.
- `SCOPERTA` — **Nota per il collega frontend — gesti del pomello.** Nel
  prototipo `stick_demo.html`, `mousedown`/`mousemove`/`mouseup` non rilevava
  il tasto destro (drag di rotazione inerte). Fix: (1) **Pointer Events con
  `setPointerCapture`** invece dei mouse event (regge anche fuori dal
  pomello); (2) rotazione come **angolo assoluto verso il puntatore**, non
  delta accumulato (si sfasa). Aggiunta la rotella come input alternativo.
  `contextmenu` va soppresso.

---

## 2026-07-20 (sessione 3 — correzione bersaglio: app Claude Desktop, non terminale)

- `DECISIONE` — **RIBALTATA la sessione 2.** Il bersaglio non è Claude Code
  nel terminale, è l'**app Claude Desktop** (MSIX Electron). L'attuatore a
  console injection della sess. 2 era corretto ma sul bersaglio sbagliato →
  archiviato. Motivo: richiesta esplicita e ripetuta dell'utente.
- `SCOPERTA` — App **MSIX**
  (`Claude_1.22209.3.0_x64__pzs8sxrjxfjjc`, `Program Files\WindowsApps\…`),
  Electron/Chromium. Lancio: `shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude`.
  Spawna `claude-code\<ver>\claude.exe --output-format stream-json` (controller
  Claude Code interno, cowork/CCD).
- `SCOPERTA` — **Attuatore corretto: Windows UI Automation (UIA).** Provato
  end-to-end: albero a11y di Chromium esposto solo con client UIA persistente
  attaccato (15 nodi a freddo → 130+ nomi); modello/effort correnti sono
  `Button` leggibili (`'Sonnet 5'`, `'Effort: High'`); telemetria in
  `Button 'Usage: context 6%, plan 32%'`; tendina sessioni = `Button`
  `#N · <titolo>` della sidebar; switch modello (espandi → `Select` sul
  RadioButton, provato Sonnet→Opus→Sonnet); switch effort (popup Slider 0-5
  Faster↔Smarter, `RangeValue.SetValue`, provato High→Medium→High).
- `SCOPERTA` — Modello/effort valgono sulla **conversazione attiva**: serve
  selezionarla in sidebar prima (la porta in primo piano). Vincolo UX da
  specificare.
- `BUG` — **Aperto:** attuazione provata con finestra in foreground. Da
  verificare se funziona senza rubare il focus (il vecchio bersaglio console
  era focus-free, questo forse no).
- `SETUP` — Riscritta SPEC.md su base UIA/app Desktop (v2). `prototype/`
  aggiornato: rimossi gli script console, aggiunti `uia_shifter.ps1` e
  `uia_effort_slider.ps1`. PROJECT.md allineato.
- `SCOPERTA` — **Focus valutato: letture focus-free, switch no.** Con
  foreground altrove, lettura modello/effort/sessioni/usage funziona con
  Claude in background; ma aprire il menu (switch) porta la finestra Claude
  in primo piano. Downgrade reale rispetto al vecchio bersaglio console
  (focus-free anche in scrittura).
- `SCOPERTA` — **Ladder effort: meccanismo provato, mappa non completa.**
  Slider 0-5 via `RangeValue.SetValue` (1=Medium, 2=High confermati). I 6
  label non enumerati: popup instabile via `ExpandCollapse`, fallback a click
  sbagliava le coordinate per mismatch DPI. Artefatti del banco prova, non
  blocchi.

---

## 2026-07-20 (sessione 2 — pivot desktop + attuatore risolto)

- `DECISIONE` — **Pivot: il prodotto è software desktop autonomo**, non
  terminale né web. L'utente pilota solo la GUI (leva + tendina sessioni), mai
  la tastiera del terminale. Riferimento: claudeine.
- `DECISIONE` — **Una sola leva con tendina di selezione sessione**,
  scartata l'ipotesi "una leva per sessione" (caos di finestre).
- `SCARTATO` — **Estensione web/browser.** Il target è il desktop.
- `SCARTATO` — **Icona-stick iniettata in ogni chat.** Elegante ma richiede
  injection nel renderer, fragile su Electron, si rompe a ogni update. Tenuta
  come idea, non come strada.
- `SCOPERTA` — **Nessun canale supportato cambia modello/effort a caldo**
  (verificato sui doc: vs-code, agent-sdk, model-config, settings — né IDE
  websocket, né Agent SDK, né settings.json). Unico meccanismo: comando
  `/model`/`/effort`. L'attuazione deve simularne la digitazione.
- `SCOPERTA` — **`~/.claude/sessions/<pid>.json` è il registro vivo delle
  sessioni interattive** (pid, sessionId, cwd, name, status). Sorgente del
  menu a tendina: isola correttamente le 2 interattive fra ~14 `claude.exe`.
- `SCOPERTA` — **Attuatore risolto e provato: `AttachConsole(pid)` +
  `WriteConsoleInput`.** Consegna tasti a una console per PID, senza rubare
  focus, anche in Windows Terminal (ConPTY), TUI raw-mode, e tab in
  background. Equivalente Windows di `tmux send-keys -t`. Chiude il BUG
  bloccante della sessione 1.
- `SCOPERTA` — **Conferma via `AttachConsole(pid)` +
  `ReadConsoleOutputCharacter`**: si rilegge lo schermo per PID
  (focus-free), verifica dall'header che lo shift sia entrato. Diventa anche
  sorgente del "marcia corrente" per il cruscotto.
- `SCOPERTA` — **Confermato dal vivo:** `/effort low` cambia l'header
  `high → low` istantaneamente; `/model sonnet` porta `Opus 4.8 → Sonnet 5`
  ma passa da una conferma "Switch model?".
- `SCOPERTA` — **Il warning sul costo di cache è nativo.** La conferma di
  `/model` mostra già "This conversation is cached… full history gets
  re-read". Il differenziatore di PROJECT §6 in parte esiste già.
- `SCOPERTA` — **Reset dell'effort per famiglia confermato dal vivo:**
  `settings.json` diceva `effortLevel: medium`, una sessione Sonnet 5 nuova
  mostrava `high`. `/model`/`/effort` si salvano come default in
  `settings.json` (i test l'hanno mutato; ripristinato a `sonnet`/`medium`).
- `SETUP` — Salvato il prototipo provato in `prototype/` (`inject.py`,
  `screen_read.py`). Scritta SPEC.md. Eliminati `model selection.md` e
  `window selection.md` (contenuto assorbito).

---

## 2026-07-20 (sessione 1 — analisi e verifiche iniziali)

- `SETUP` — Repo collegato a GitHub (`matteoccll/claude_shifter`), clonato in
  `C:\Users\simon\Desktop\MODEL AND FURIOUS`, branch `main` da `fb34a0c`.
  Aperto in VS Code. `gh` CLI non installato.
- `SCOPERTA` — Verificato sui doc ufficiali: i due assi esistono già come
  comandi separati, `/model` (haiku, sonnet, opus, fable, default, opusplan,
  best) e `/effort` (low, medium, high, xhigh, max, ultracode). Conferma
  l'ipotesi "main box + splitter".
- `SCOPERTA` — Risolta la domanda aperta di `model selection.md:56`: l'effort
  è **globale**, non per-marcia, ma viene **resettato per famiglia di
  modello** (Fable 5/Opus 4.8 → `high`, Opus 4.7 → `xhigh`, ignorando la
  scelta precedente) e **scala** al livello più alto supportato se il modello
  non regge quello richiesto. Non tutte le combinazioni sono ingranabili.
- `SCOPERTA` — Confermati tutti i campi del cruscotto via statusline JSON:
  `model.display_name`, `context_window.remaining_percentage`,
  `total_input_tokens`, `cost.total_cost_usd`, `session_id`,
  `transcript_path`, `exceeds_200k_tokens`. Supporta multi-riga, ANSI,
  `refreshInterval: 1` (aggiornamento al secondo). Le voci *inferred* di
  `model selection.md` (FUEL = contesto) risultano corrette.
- `SCARTATO` — **Hook come attuatore.** Nessun hook cambia modello/effort;
  `SessionStart` riceve il modello in input ma non ha campo di output per
  modificarlo.
- `SCARTATO` — **`model` in settings.json come attuatore.** Letto solo
  all'avvio, inerte a caldo.
- `SCARTATO` — **Skill con frontmatter `model:`/`effort:` come leva.**
  Funziona ma l'override dura un solo turno (kickdown, non marcia inserita).
  Eventualmente recuperabile come feature secondaria.
- `DECISIONE` — Architettura: **GUI esterna + injection da tastiera nel
  terminale.** Motivo: `/model` e `/effort` digitati nel TTY sono l'unico
  meccanismo che produce uno shift persistente. Scartato l'harness su Agent
  SDK (equivarrebbe a riscrivere Claude Code).
- `BUG` — **Aperto, bloccante.** L'attuatore richiede injection di tastiera,
  macchina Windows 11, tmux non esiste. Alternative: WSL+tmux, o
  SendInput/AutoHotkey su Windows Terminal (non dà conferma affidabile che il
  tasto sia atterrato nel pane giusto — il fallimento che
  `window selection.md` dichiara inaccettabile).
- `DECISIONE` — Creati `PROJECT.md` e `STORICO.md` come documenti guida, con
  obbligo esplicito di richiesta di aggiornamento a fine sessione.

---

> ⚠️ **PROMEMORIA FINALE — TASSATIVO**
> Prima di chiudere la sessione, chiedere all'utente:
> **"Aggiorno PROJECT.md e STORICO.md con quanto fatto oggi?"**
> Attendere conferma esplicita. Non aggiornare d'iniziativa, non saltare la domanda.
