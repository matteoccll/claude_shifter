# MODEL AND FURIOUS — Direzione e obiettivo

> ⚠️ **A FINE SESSIONE È OBBLIGATORIO** chiedere all'utente se procedere con
> l'aggiornamento di questo file e di [STORICO.md](STORICO.md). Non aggiornare
> senza conferma, ma **non chiudere la sessione senza aver chiesto.**

---

## 1. Cos'è

Un **cambio di marce fisico-simulato** per Claude Code: l'utente innesta una
marcia e in realtà sta cambiando il modello che serve la sessione.

Non è una skin. La tesi del progetto è che la metafora meccanica non sia
decorativa ma **descrittiva**: la scelta modello+effort ha davvero la struttura
di un cambio (rapporti discreti, combinazioni non ingranabili, costo del
cambio a caldo), e trattarla come tale produce un'interfaccia migliore di un
menu a tendina.

## 2. Obiettivo

Una **GUI esterna** che pilota una sessione Claude Code viva, con:

- una **leva principale** → il modello
- una **leva secondaria (splitter)** → l'effort
- un **cruscotto** che legge la telemetria reale della sessione

Il criterio di successo non è estetico: si deve poter cambiare marcia
**guardando la strada**, cioè senza uscire dal flusso di lavoro per aprire un
menu, e **sapendo su quale sessione si sta agendo** prima di agire.

## 3. La meccanica reale (verificata, non ipotizzata)

Le due leve **esistono già** in Claude Code come comandi separati. Il design a
"main box + splitter" dedotto in [model selection.md](model%20selection.md) era
corretto:

| Leva | Comando | Posizioni |
|---|---|---|
| Marcia (modello) | `/model <alias>` | `haiku`, `sonnet`, `opus`, `fable`, `default`, `opusplan`, `best`, o model ID completo |
| Splitter (effort) | `/effort <livello>` | `low`, `medium`, `high`, `xhigh`, `max`, + `ultracode` |

**Non tutte le combinazioni sono ingranabili.** Questa è la scoperta che
sostituisce l'ipotesi della griglia 4×5:

- L'effort è **globale**, non memorizzato per-marcia.
- Ma viene **resettato automaticamente per famiglia di modello**: alla prima
  esecuzione di Fable 5 e Opus 4.8 l'effort torna a `high`, su Opus 4.7 a
  `xhigh`, **ignorando la scelta precedente dell'utente**.
- Se si imposta un livello che il modello non regge, **scala** al più alto
  supportato (es. `xhigh` → `high` su Opus 4.6).

Tradotto in meccanica: è uno splitter i cui rapporti **cambiano di significato
a seconda della marcia**, e che in certe marce viene **forzato in posizione**.
La GUI deve mostrare questo, non nasconderlo — è la parte interessante.

## 4. Architettura decisa

**GUI esterna + injection da tastiera nel terminale.**

Scelta consapevole, presa il 2026-07-20, contro due alternative più comode.
Motivo: è l'unica che produce una **marcia che resta inserita**.

### Perché non le altre

| Alternativa | Perché scartata |
|---|---|
| Skill con frontmatter `model:`/`effort:` | Funziona, ma l'override **dura un solo turno**. Non è una marcia inserita: è un **kickdown**. Utile forse come feature secondaria, non come leva. |
| Hook | **Impossibile.** Nessun hook può cambiare modello o effort. `SessionStart` riceve il modello in input ma non esiste un campo di output per modificarlo. |
| `model` in settings.json | Letto **solo all'avvio** della sessione. Inerte a caldo. |
| Harness proprio su Agent SDK | Controllo totale, ma significa riscrivere Claude Code invece di guidarlo. Fuori scala. |

### Il vincolo che ne consegue

`/model` e `/effort` **digitati nel TTY** sono l'unico shift persistente. Quindi
la GUI deve simulare digitazione. Questo è ciò che fanno anche ShiftCC e
ModelShifter (`tmux send-keys`).

**Problema aperto, il più grosso del progetto:** la macchina di sviluppo è
**Windows 11, dove tmux non esiste.** Le strade sono WSL + tmux, oppure
SendInput/AutoHotkey su Windows Terminal. La seconda è fragile: non offre una
conferma affidabile che il tasto sia atterrato nel pane giusto — che è
esattamente il fallimento che [window selection.md](window%20selection.md)
identifica come inaccettabile. **Da risolvere prima di scrivere codice di
attuazione.**

## 5. Il cruscotto (la parte già sbloccata)

Lo statusline di Claude Code esegue uno script arbitrario e gli passa JSON su
stdin. Tutti i campi del cruscotto sono **reali e confermati**:

| Strumento | Campo |
|---|---|
| Marcia inserita | `model.display_name`, `model.id` |
| `FUEL` (E↔F) | `context_window.remaining_percentage` |
| `TOK/MIN` (tach) | delta di `context_window.total_input_tokens` fra invocazioni |
| `TOTAL ×1000 TOK` | `context_window.total_input_tokens` / `total_output_tokens` |
| Costo sessione | `cost.total_cost_usd` |
| Identità sessione | `session_id`, `transcript_path`, `workspace.current_dir` |
| Soglia rossa | `exceeds_200k_tokens` |

Supporta **output multi-riga e colori ANSI**. `refreshInterval: 1` in
settings.json lo rifà girare ogni secondo: **il tach si muove davvero**, non è
un'animazione finta.

Questo è indipendente dal problema dell'attuazione e si può costruire subito.

## 6. Il vincolo che nessuno dei due concorrenti mostra

Un cambio marcia a metà conversazione **costa**: la cache dei prompt è legata al
modello che ha servito la richiesta, quindi al turno successivo l'intero
contesto viene **riletto a prezzo pieno**.

La GUI deve stimarlo e mostrarlo **prima** dello shift, non dopo. È il
differenziatore reale rispetto a ShiftCC e ModelShifter, che non lo espongono.

## 7. Principio non negoziabile

Ereditato da [window selection.md](window%20selection.md) e confermato:

> **Il bersaglio deve essere sempre visibile prima dello shift, mai dedotto
> silenziosamente dopo.**

Con più sessioni aperte, cambiare marcia a quella sbagliata non dà errore: dà
una conversazione silenziosamente rovinata più una rilettura di contesto a
prezzo pieno. Nessuna scorciatoia di targeting vale questo rischio.

## 8. Non-obiettivi

- Nessun broadcast a tutte le sessioni.
- Nessuna inferenza "intelligente" del bersaglio oltre al focus esplicito.
- Nessuna marcia automatica (niente auto-downshift su task semplici) finché la
  leva manuale non è solida.
- Non è un clone di ShiftCC/ModelShifter: se non aggiunge il costo-cache e il
  targeting esplicito, non ha motivo di esistere.

## 9. Stato attuale

| Area | Stato |
|---|---|
| Analisi concorrenti | ✅ Fatta |
| Meccanica model/effort | ✅ Verificata sui doc |
| Campi cruscotto | ✅ Verificati |
| Attuatore su Windows | 🔴 **Aperto — blocca tutto** |
| Codice | ⬜ Nessuno |

---

> ⚠️ **PROMEMORIA FINALE — TASSATIVO**
> Prima di chiudere la sessione, chiedere all'utente:
> **"Aggiorno PROJECT.md e STORICO.md con quanto fatto oggi?"**
> Attendere conferma esplicita. Non aggiornare d'iniziativa, non saltare la domanda.
