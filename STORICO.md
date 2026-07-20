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

## 2026-07-21 (sessione 10 — backend: controllo generale e quattro difetti chiusi)

- `SETUP` — Controllo generale del backend sull'app viva: parse di `broker.ps1`,
  sintassi dei 13 file JS, poi `capabilities` (5,8 s, 7 modelli col sottomenu
  aperto all'hover), `reattach` 2/2, `test.js` M1 passato con ripristino
  verificato, e una batteria nuova sui rami d'errore (comando ignoto, modello
  inesistente, effort fuori scala, sessione inesistente): tutti errori puliti,
  **nessuno ha cambiato lo stato dell'app**.
- `BUG` `FIX` — **`setModel` senza il nome innestava Fable 5.** Con l'argomento
  mancante il match "a somiglianza" di `FindModelOption` diventava `-like "*"`,
  che accetta tutto e restituisce la prima voce del menu. E la verifica **passava**:
  il broker rileggeva il pulsante, ci trovava davvero "Fable 5" e rispondeva `ok`.
  Un campo `undefined` lato GUI sparisce dal JSON senza far rumore, quindi il caso
  era a una riga di distanza, non ipotetico. Chiuso con tre sbarramenti: il jolly
  non degenera più (nome vuoto → nessun match), `Op-SetModel` rifiuta prima di
  aprire il menu, il dispatch controlla che il campo sia arrivato.
- `BUG` `FIX` — **`setEffort` senza il livello scendeva al minimo in silenzio.**
  `[int]$null` vale `0`, che è dentro la scala, quindi il controllo "fuori range"
  non scattava. Aggiunto `ReqArg`, che distingue **"il campo non c'è"** da **"il
  campo c'è e vale zero"** — differenza che prima non esisteva. Il livello deve
  anche essere un intero: `"alto"` e `2.7` vengono respinti. Verificato apposta
  che `level: 0` continui a passare: zero è la marcia più bassa, non un valore
  mancante.
- `FIX` — **Il puntatore non veniva più restituito.** Aprire il sottomenu "Altri
  modelli" richiede un hover vero, quindi ogni `capabilities` trascinava il mouse
  attraverso lo schermo e ce lo lasciava — e la GUI deve chiamare `capabilities`
  dopo ogni cambio marcia. Ora la posizione viene salvata al primo movimento e
  rimessa alla fine del comando (in un `finally`, così vale anche per i comandi
  falliti a metà menu), mai fra un movimento e l'altro: il sottomenu resta aperto
  solo finché il puntatore ci sta sopra. Se nel frattempo è stato l'utente a
  muovere il mouse, il broker lo lascia stare.
- `SCOPERTA` — **`$home` in PowerShell è riservata, e il confronto fra nomi di
  variabile è insensibile alle maiuscole.** Scritta durante il fix qui sopra, ha
  prodotto un errore non terminante a ogni comando; il nome restava a contenere
  il percorso del profilo, la guardia `$null -eq` lo trovava valorizzato e
  proseguiva, e `[int]$origin.X` su una stringa dava `0` — **puntatore spedito a
  0,0 a ogni comando**, peggio del problema di partenza. Rinominata `$origin`.
  È la stessa famiglia di `$PID`, già evitata nel file chiamando `$script:pid0`
  quel campo; ora il motivo è scritto accanto alla funzione. Passato tutto il
  file al setaccio: nessun'altra collisione (i `$null = ...` sono lo scarto
  idiomatico).
- `SETUP` — Il ripristino del puntatore è stato **misurato**, non dedotto: mouse
  a 640,400, `capabilities.js`, rilettura → 640,400, scarto 0 px. Il difetto di
  `$home` era invisibile agli esiti verdi dei collaudi (i test guardavano la
  marcia, non il mouse) ed è emerso solo dal rumore su stderr nel report.
- `BUG` `FIX` — **`map.js` si fidava della lista modelli.** Leggeva `listModels`
  senza la normalizzazione che `capabilities()` ha già: se l'app offrisse un solo
  modello, PowerShell 5.1 lo consegna come oggetto singolo e `models.forEach`
  esplode. Aggiunto `listModels()` al client, che restituisce sempre un array.
  Ipotetico con 7 modelli, ma è la stessa trappola già documentata nel client.

## 2026-07-21 (sessione 9 — backend: chiusi i due difetti di `map.js`)

- `BUG` `FIX` — **Un modello storto buttava all'aria l'intera mappatura.** In
  `map.js` il `setModel` di ogni giro era protetto da un `try`, il `probeEffort`
  subito dopo no: un suo errore risaliva fino al `finally`, chiudendo la run e
  perdendo anche i modelli già misurati bene. Ora i due passaggi si comportano
  allo stesso modo — errore scritto nel report, modello contato fra i non
  misurati, giro che continua. Un guasto costa un modello, non la serata.
- `BUG` `FIX` — **Lo script usciva 0 anche a mappa dichiarata incompleta.** Il
  ramo protettivo aggiunto in sessione 8 rifiutava di sovrascrivere
  `gearbox.json` ma restituiva comunque successo: un esito verde che non
  significava niente per chi non apriva il report. Ora la mappa monca esce **3**.
  Codici documentati in cima al file: 0 completa, 1 errore fatale, 2 deadline,
  3 incompleta. Usato `process.exitCode` e non `process.exit()`, così il report
  viene scritto e il broker chiuso come prima. Chiude il rinvio deciso in
  sessione 8.

## 2026-07-21 (sessione 8 — backend: collaudo completo e la mappa che si cancellava)

- `SETUP` — Collaudato l'intero backend sull'app viva, partendo dai comandi che
  non toccano nulla: `state`, `probe`, `capabilities`, `fastmode`, `popup`,
  `effortpopup`, `dump`, `tree` tutti passati; `reattach` 3/3 recuperi in ~850 ms
  l'uno; `test.js` 6 verifiche su 6 con ripristino confermato. Il giro di
  `selectSession` è stato saltato: in sidebar c'era una sola conversazione.
- `BUG` — **`map.js` ha cancellato la mappa buona.** Una run in cui i tre modelli
  dietro il sottomenu "Altri modelli" non si sono lasciati raggiungere ha
  comunque riscritto `gearbox.json`, sostituendo le scale di effort di quattro
  modelli con altrettanti messaggi d'errore (97 righe perse, 6 aggiunte). La
  scrittura era incondizionata: nessuna distinzione fra mappa completa e mappa
  monca. Dato recuperato da git, che lo teneva a HEAD.
- `DECISIONE` `FIX` — **`gearbox.json` si scrive solo a mappa completa.** Se anche
  un solo modello abilitato non è stato misurato, il file buono resta intatto e
  il risultato zoppo va in `gearbox-partial.json` (aggiunto al `.gitignore`: è
  uno scarto diagnostico, non una mappa). Motivo: la mappa non è un log, è
  l'unica misura completa che esista, e una serata sfortunata al menu non deve
  poterla cancellare. Scartata l'alternativa di fondere il vecchio col nuovo per
  i modelli falliti: spaccerebbe misure di ieri per misure di stasera, contro
  "il backend rileva, non dichiara" (PROJECT §4.1).
- `SCOPERTA` `FIX` — **Due risposte vuote che si assomigliano.** "Questo modello
  non ha l'effort" (Haiku: misura riuscita) e "l'effort non si è aperto"
  (fallimento di lettura) erano distinguibili solo dal testo inglese del campo
  `reason`. Farci dipendere `map.js` sarebbe stata la trappola che in sessione 7
  aveva ucciso `test.js`. Aggiunto al broker il campo `hasControl`, leggibile a
  macchina, nei tre punti che producono quella risposta (`Op-EffortRange`,
  `Op-ProbeEffort`, `Op-Capabilities`).
- `BUG` — **Il sottomenu "Altri modelli" a volte non si apre, e non si sa
  perché.** Nel log della run fallita: `4 -> 0`, cioè dopo l'`Expand()` il menu
  intero è sparito invece di espandersi, e i tentativi successivi (hover, click)
  trovavano un elemento senza punto cliccabile. Non riproducibile a comando: 3
  giri isolati di `probe` e un repro mirato subito dopo Haiku l'hanno visto
  funzionare 4 volte su 4, e la rimappatura successiva ha fatto 7/7. Causa non
  trovata. Resta aperto — ma ora non fa più danni permanenti.
- `SCOPERTA` — **Il degrado era un incidente, non un cambiamento dell'app.** La
  rimappatura completa ha prodotto un `gearbox.json` identico a quello
  precedente tranne il timestamp: le scale di effort dei 7 modelli non si sono
  mosse.
- `SETUP` — Il ramo protettivo non era osservabile aspettando che il sottomenu si
  impuntasse di nuovo, quindi è stato forzato con un modello inesistente su una
  copia dello script: Haiku misurato e **non** contato come buco, il modello
  fasullo contato, scritto solo il parziale, e l'impronta SHA256 di
  `gearbox.json` identica prima e dopo.
- `DECISIONE` — **Rinviati apposta gli altri due difetti di `map.js`**, su
  richiesta: `probeEffort` non è protetto mentre `setModel` sì (un suo errore
  butta all'aria l'intera run, comprese le misure già fatte), e lo script esce
  sempre 0 — anche a mappa dichiarata incompleta. Due politiche opposte per lo
  stesso tipo di guasto, e un esito verde che non significa niente.

## 2026-07-20 (sessione 7 — backend: collaudo dal vivo e sei riparazioni)

- `SETUP` — Collaudato l'intero backend sull'app viva **prima** di toccare il
  codice: `state`, `probe`, `capabilities`, `reattach` (3/3 recuperi, ~0,8 s
  l'uno) e la catena M1 completa — enumerate → selectSession andata/ritorno →
  setModel andata/ritorno → setEffort andata/ritorno — con verifica delle
  etichette a ogni passo e ripristino finale confermato. Il cuore del broker
  reggeva; i difetti erano tutti ai bordi.
- `BUG` `FIX` — **Il cruscotto era cieco e non lo diceva.** Il contatore
  dell'app oscilla fra due formati — `Usage: context 14%, plan 32%` e
  `Usage: context 127.5k, plan 41%` (token assoluti) — visti entrambi nella
  stessa serata. `readUsage` capiva solo la percentuale, e `capabilities`
  restituiva il cruscotto vuoto **senza registrarlo in `errors`**: il
  fallimento silenzioso che quella lista doveva impedire. Ora il parser legge
  entrambi i formati (e la virgola decimale), riporta il testo grezzo, e un
  cruscotto assente o illeggibile compare in `errors`.
- `BUG` `FIX` — **test.js era morto e con lui il collaudo di selectSession.**
  Parlava il protocollo di due generazioni fa (`{sessions}` invece di
  `{count,text}`) e crollava al passo 1 con un TypeError muto; era l'unico
  script a esercitare `selectSession`. Riscritto sul client condiviso con
  verifica per passo e auto-ripristino; passato 7 verifiche su 7 in 25 s.
- `SCOPERTA` `FIX` — **I cercatori di menu pescavano la chat.** I punti elenco
  markdown della conversazione si renderizzano come `ListItem` e precedono il
  menu nell'ordine del documento: il broker ha restituito come "interruttore
  fast mode" il testo di un messaggio della chat. Le voci di menu vere sono
  solo `Menu`/`MenuItem`/`RadioButton` (verificato col dump): i cercatori ora
  accettano solo `MenuItem`. Emersa collaudando il fix precedente, non
  leggendo il codice.
- `BUG` `FIX` — **fastMode agiva alla cieca.** Lo stato del toggle non è mai
  stato leggibile (illeggibile in ogni run) e il ramo `set` attuava comunque
  assumendo "spento", dichiarando poi `changed=true` senza verifica. Ora
  rifiuta esplicitamente se la voce manca (modelli senza fast mode) o se lo
  stato non si legge; la lettura resta permessa. Provate entrambe le guardie
  dal vivo, con ripristino del modello.
- `FIX` — **ModelBtn non si fida più del solo nome.** La sidebar precede la
  leva nell'ordine del documento: una conversazione con titolo auto-generato
  che inizia per Sonnet/Opus/Haiku/Fable sarebbe stata scambiata per il
  pulsante modello. In sidebar c'era "Prompt efficace per Fable 5" — salva
  solo perché il titolo non *inizia* col nome. Ora il candidato deve esporre
  anche `ExpandCollapsePattern`: la leva apre un menu, una riga di sessione no
  (verificato dal vivo: riga → False, leva → True).
- `FIX` — **setEffort ora verifica, e probeEffort verifica la cosa giusta.**
  `setEffort` rispondeva ok con qualunque etichetta fosse rimasta sul
  pulsante; ora rilegge la posizione del cursore e fallisce se non coincide
  (riaprendo il popup una volta se si è chiuso da solo). `restoredOk` di
  `probeEffort` controllava solo di aver letto *una* etichetta al ripristino,
  non che fosse *quella* della posizione di partenza — terza "verifica che non
  verificava" del progetto; ora confronta con l'etichetta letta dalla spazzata
  stessa ed espone `expected`.
- `FIX` — **Minuzie del client.** `start()` rigetta se PowerShell non parte o
  se il broker muore prima dell'aggancio (prima restava appeso); `withDeadline`
  accetta report nullo e scrive su stderr, così anche i diagnostici a console
  (`probe`, `dump`, `tree`, `popup`) hanno una scadenza; `state.js` le passava
  la label al posto del report (TypeError muto al timeout); rimosso un
  watchdog mai assegnato; corretti due commenti che dicevano ancora "closed
  with Escape".
- `DECISIONE` — **Lasciati fuori apposta, perché prematuri:** la verifica
  forte di `selectSession` (serve prima progettare un segnale affidabile di
  "conversazione attiva") e il match dei titoli per suffisso in
  `SessionEntries` (un titolo che è suffisso di un altro può agganciare la
  riga sbagliata). Registrati come rischi noti, da riprendere quando la GUI
  esisterà.
- `SCOPERTA` — **detachtest.js risulta lanciato ma abbandonato.** Esiste un
  report delle 23:06 (16 giri, tutti ok, troncato senza esito): l'app non è
  mai stata chiusa durante la run. Il ramo "app davvero chiusa" resta non
  provato, come già dichiarato in PROJECT §10.
- `SCOPERTA` — **Limite noto:** se una chiamata UIA si pianta davvero, la
  deadline uccide lo script Node ma il figlio PowerShell resta orfano,
  bloccato con il client UIA attaccato. Non provocabile senza rischiare l'app
  che ospita il collaudo.

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
