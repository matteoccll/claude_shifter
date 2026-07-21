# Frontend — decisioni prese e prossima azione

> Bozza personale sul branch `simone_fullstack_branch` (prova fullstack in
> autonomia, vedi `CLAUDE.local.md`). Non è ancora la GUI concordata col collega:
> è il terreno di prova di Simone. Le decisioni qui sotto valgono per questa bozza.

Riepilogo delle decisioni prese discutendo le 3 foto del cambio (leva a 6 marce,
leva a 4 marce, pomello-giocattolo Haiku). Ogni voce riporta il **motivo**, non
solo l'esito, così fra sei mesi si ricostruisce il perché.

## Decisioni

1. **Leva a immagini scambiate, non griglia fissa con marce bloccate.**
   Quando entra un modello con meno marce si **cambia la foto** (6 → 4 → giocattolo),
   non si tiene la foto a 6 marce bloccando le mancanti con un avviso.
   *Perché:* sull'app vera le marce in più **spariscono**, non restano disabilitate
   (PROJECT §3.1, la corsa del cursore si accorcia davvero); una leva che può andare
   su una marcia inesistente mentirebbe sulla macchina. Inoltre è **meno** codice,
   non di più, e regge il caso limite "ero in Ultracode e passo a un modello a 4
   marce" (con lo scambio-foto la marcia sparita non è un problema, con la foto
   bloccata resti fermo su una posizione ora vietata).

2. **La griglia è guidata da `capabilities`, mai scritta a mano.**
   Il numero di marce e la lista modelli arrivano dal backend a ogni richiesta; la
   GUI ci disegna sopra. *Perché:* PROJECT §4.1 — una lista hardcoded "diventa falsa
   al primo aggiornamento di Claude". Tenere la foto a 6 marce fissa sarebbe di fatto
   la griglia fissa già scartata.

3. **Stato "sto innestando" onesto (~5 s), non "lento apposta" (9–20 s).**
   Il numero 9–20 s è **superato**: sessioni 14–16 hanno sostituito le attese fisse
   con poll a budget invariato. Misure reali: `setModel` ~1,6 s, `capabilities`
   ~2,2 s, cambio completo ~5,1 s, picco peggiore ~4 s (era ~10). Lo stato serve
   ancora — un cambio non è istantaneo — ma è ~un terzo di quanto detto prima.

4. **Selezione modello: ruota che appare, sul pomello solo il modello attivo.**
   Clic destro sul pomello → il pomello ruota → appare una **ruota dei modelli** →
   scegli → sul pomello resta scritto **solo** il modello selezionato. *Scartata*
   l'idea di incidere tutti e 7 i nomi sul pomello: ripeterebbe la griglia fissa
   (decisione 2), 7 nomi su un tondo sono illeggibili, e un pomello con una sola
   scritta chiara rispetta il principio §7 (il bersaglio è visibile, non dedotto).

5. **La ruota si disegna da `listModels` (dinamica) e mostra tutti i modelli in piano.**
   *Perché:* stessa ragione della 2. In più la GUI può fare meglio dell'app che
   pilota, che ne nasconde 3 su 7 dietro il sottomenu "Altri modelli".

6. **Pomello Haiku = skin giocattolo, coincide con `gears: 0`.**
   Haiku non ha splitter (PROJECT §3.1): quando è innestato, la leva **deve** già
   cambiare forma. La skin giocattolo trasforma quel vincolo tecnico in una battuta
   invece di nasconderlo.

7. **Architettura a strati: la foto è l'hardware, il codice disegna sopra.**
   Foto (sfondo statico) = cornice, gate, forma del pomello. Codice = nome del
   modello sul pomello + ruota. **Nessuna foto per-modello.** Editing foto ridotto
   al minimo: serve solo un **pomello pulito** (superficie su cui scrivere) e la
   **variante Haiku** come immagine separata; le scritte delle marce nel gate possono
   restare stampate nella foto perché sono fisse per quel numero di marce.

8. **`setModel` può fallire (bug sottomenu §10): la GUI mostra "riprovo", non dà per fatto lo switch.**
   Un `setModel` fallito **non** prova che il modello non esista; il backend ora
   ritenta da solo (sessione 15), e la GUI deve accettare uno stato "non riuscito,
   riprovo" invece di dedurre che l'app non offre più quel modello.

## Prossima azione

**Costruire il frontend a partire dalle 3 foto seguendo le decisioni qui sopra.**
Primo taglio in questo commit (mock al posto del backend, placeholder al posto
delle foto).

### Cosa c'è in questo primo commit

- Scaffold Electron (`main.js` + renderer HTML/CSS/JS **apribile anche in un
  browser normale**, così si può vedere subito senza avviare Electron).
- Strati come da decisione 7: `img` foto sotto, nome-modello e ruota disegnati sopra.
- Scambio-foto per numero di marce (decisione 1): 6 → 4 → giocattolo Haiku.
- Ladder effort disegnato **da `capabilities`** (decisione 2), non hardcoded.
- Clic destro sul pomello → ruota dei modelli da `listModels` (decisioni 4–5).
- Stato "sto innestando" con tempi realistici + **retry** su `setModel` fallito
  (decisioni 3, 8).
- `mockBroker.js`: simula `capabilities` / `listModels` / `setModel` / `setEffort`
  con le latenze misurate e un tasso di fallimento del submenu, così gira da solo.
- Placeholder SVG in `assets/` con lo **slot esatto** per le 3 foto vere.

### TODO (non in questo commit)

- Sostituire i placeholder con le 3 foto vere (vedi `assets/README.md`).
- Misurare l'**ancora del pomello** (centro x,y in %) su ogni foto vera e metterla
  in `IMAGES` dentro `app.js`.
- Sostituire `mockBroker.js` con il broker UIA vero (i nomi dei comandi sono già
  quelli del backend, così il cambio è quasi solo una rinomina).
- Decidere il layout della ruota (nomi in cerchio vs raggruppati per famiglia
  Opus / Sonnet / Haiku / Fable).

### Nota sul branch

`simone_fullstack_branch` è **6 commit indietro** rispetto a `simone`: qui il
backend è ancora quello lento della sessione 13. Il codice veloce (14–16) sta su
`simone`/`main`. Non incide sui file frontend (sono nuovi), ma quando si collauderà
il frontend contro il backend vero conviene prima allineare il branch.
