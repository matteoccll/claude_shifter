# MODEL AND FURIOUS — Direzione e obiettivo

> ⚠️ **A FINE SESSIONE È OBBLIGATORIO** chiedere all'utente se procedere con
> l'aggiornamento di questo file e di [STORICO.md](STORICO.md). Non aggiornare
> senza conferma, ma **non chiudere la sessione senza aver chiesto.**

> 📐 Specifica di build pronta allo sviluppo: **[SPEC.md](SPEC.md)** (autorevole
> sul "cosa/come"). Questo file dice *dove si va e perché*.

---

## 1. Cos'è

Un **cambio di marce fisico-simulato** per Claude, realizzato come **software
desktop autonomo** (pattern claudeine: un'app nativa che parla con Claude ma è
indipendente dalla sua interfaccia). L'utente innesta una marcia sulla leva e in
realtà cambia il modello/effort di una conversazione **dentro l'app Claude
Desktop** (quella bianca che si apre cliccando il logo), scelta da un menu a
tendina. **L'utente agisce solo sulla nostra leva: non apre mai il menu modello
dell'app a mano.**

## 2. Obiettivo

Una **GUI desktop autonoma** che pilota l'app **Claude Desktop** viva, con:

- **una sola leva-cambio** + un **menu a tendina** per scegliere la conversazione
  su cui agire (una leva, molte conversazioni);
- **leva principale** → il modello, **splitter** → l'effort;
- un **cruscotto** che legge la telemetria reale (context %, plan %).

Criterio di successo: cambiare marcia **guardando la strada** e **sapendo su quale
conversazione si agisce** prima di agire.

## 3. La meccanica reale (verificata dal vivo il 2026-07-20)

Il bersaglio è l'**app Claude Desktop** (MSIX, Electron). Si pilota via **Windows
UI Automation (UIA)**, non da terminale. Verificato sul campo:

| Elemento | Come appare in UIA | Azione |
|---|---|---|
| Modello corrente | `Button 'Sonnet 5'` | leggere l'etichetta |
| Menu modello | `RadioButton` `Haiku 4.5` / `Sonnet 5 · Default` / `Opus 4.8` / `Fable 5` | espandi + `Select` |
| Effort corrente | `Button 'Effort: High'` | leggere l'etichetta |
| Effort | popup con uno **Slider** 0–5 (`Faster ↔ Smarter`) | `RangeValue.SetValue` |
| Sessioni (tendina) | `Button` `#N · <titolo>` nella sidebar | `Invoke` per attivarla |
| Telemetria | `Button 'Usage: context 6%, plan 32%'` | parse |

**Vincolo chiave:** modello ed effort valgono sulla **conversazione attiva**. Per
cambiare marcia a una sessione bisogna **prima selezionarla** nella sidebar (che la
porta in primo piano nell'app), poi agire sulle leve.

## 4. Architettura decisa — e la correzione di rotta

**Software desktop autonomo + attuazione via UI Automation sull'app Claude
Desktop.** Provato sul campo il 2026-07-20.

- **Enumerazione** (tendina): i `Button` `#N · …` della sidebar dell'app.
- **Lettura** marcia/effort/telemetria: etichette dei `Button` UIA.
- **Attuazione**: modello = espandi il button → `Select` sul `RadioButton`; effort =
  espandi → `RangeValue.SetValue` sullo Slider. Verifica sempre rileggendo
  l'etichetta.

### Perché non le altre / cosa è stato ribaltato

| Alternativa | Esito |
|---|---|
| **Attuatore da terminale (console injection)** | **RIBALTATO.** Provato e funzionante, ma sul bersaglio SBAGLIATO (Claude Code CLI nel terminale). Il bersaglio è l'app Claude Desktop. Materiale archiviato. |
| API/canale di controllo supportato | Non documentato per cambiare modello/effort a caldo. Si pilota la GUI. |
| Estensione web / iniezione nel renderer dell'app | Scartato: fragile / bersaglio sbagliato. |
| Una leva per ogni sessione | Scartato: caos. Una leva + tendina. |

## 5. Il cruscotto

Il button `Usage: context X%, plan Y%` dà già context % (FUEL) e uso del piano via
UIA. Eventuale telemetria extra dai transcript locali (stile claudeine). Zero rete.

## 6. Il costo del cambio a caldo

Cambiare modello a metà conversazione costa (rilettura contesto a prezzo pieno). Da
verificare se l'app Claude Desktop mostra un avviso nativo allo switch e se
convenga anticiparlo nella nostra GUI.

## 7. Principio non negoziabile

> **Il bersaglio (la conversazione) è sempre visibile prima dello shift, mai
> dedotto dopo. Nessuno shift è "riuscito" senza conferma riletta dall'etichetta.**

Nota onesta: sull'app Claude Desktop, selezionare la sessione la porta in primo
piano — l'UX va costruita su questa verità, non nasconderla.

## 8. Non-obiettivi / fuori scope v1

- Nessun broadcast, nessuna marcia automatica.
- Nessun targeting implicito oltre alla selezione esplicita in tendina.
- Non è console injection nel terminale (bersaglio sbagliato, ribaltato).
- macOS/Linux, web, IDE: fuori scope.

## 9. Stato attuale

| Area | Stato |
|---|---|
| Bersaglio corretto individuato (app Claude Desktop MSIX) | ✅ |
| Enumerazione conversazioni (UIA sidebar) | ✅ Provata |
| Lettura modello/effort/telemetria (UIA) | ✅ Provata |
| Switch modello (UIA Select) | ✅ Provato (Sonnet↔Opus, self-revert) |
| Switch effort (UIA Slider) | ✅ Provato (High↔Medium, self-revert) |
| Attuazione **senza rubare il focus** | 🟡 Valutato: **letture** focus-free ✅, **switch** portano l'app in primo piano ⚠️ |
| Ladder effort completo (6 livelli) | 🟡 Valutato: slider 0–5 provato; mappa completa bloccata da apertura popup instabile |
| Spec di build | ✅ [SPEC.md](SPEC.md) |
| Prototipo UIA | ✅ [`prototype/`](prototype/) (`uia_shifter.ps1`, `uia_effort_slider.ps1`) |
| Codice app | ⬜ Da costruire |

---

> ⚠️ **PROMEMORIA FINALE — TASSATIVO**
> Prima di chiudere la sessione, chiedere all'utente:
> **"Aggiorno PROJECT.md e STORICO.md con quanto fatto oggi?"**
> Attendere conferma esplicita. Non aggiornare d'iniziativa, non saltare la domanda.
