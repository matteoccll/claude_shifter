# MODEL AND FURIOUS

Cambio di marce simulato per Claude Code: l'utente innesta una marcia e in realtà
cambia il modello che serve la sessione.

Direzione, obiettivo e vincoli: **[PROJECT.md](PROJECT.md)** — leggilo prima di
proporre architetture, contiene le strade già scartate con il motivo.
Registro di cosa è successo: **[STORICO.md](STORICO.md)**.

## Regola obbligatoria — aggiornamento di fine sessione

**Prima di chiudere la sessione devi CHIEDERE all'utente:**

> "Aggiorno PROJECT.md e STORICO.md con quanto fatto oggi?"

Vincoli sulla regola:

- **Chiedere è obbligatorio. Aggiornare no.** Non modificare i due file senza
  conferma esplicita dell'utente, ma non concludere una sessione di lavoro senza
  aver posto la domanda.
- Vale quando la sessione ha prodotto qualcosa di registrabile: una decisione, un
  fix, un bug trovato, una strada scartata, una modifica al repo. Per una domanda
  puramente informativa non serve.
- Se l'utente conferma, aggiorna **entrambi** i file coerentemente: `STORICO.md`
  con la voce datata, `PROJECT.md` solo se la direzione o lo stato sono cambiati.

## Come si scrive su STORICO.md

Solo **date e azioni eseguite**, al passato. Niente piani o intenzioni: quelli
stanno in `PROJECT.md`.

- Voce nuova **in cima**, formato data `AAAA-MM-GG`.
- Tag: `DECISIONE` · `FIX` · `BUG` · `SETUP` · `SCOPERTA` · `SCARTATO`
- Le decisioni riportano il **motivo**, non solo l'esito.
- Non riscrivere le voci passate. Una decisione ribaltata si registra con una
  voce nuova che la ribalta.

## Convenzioni di lavoro

- I fatti su cosa Claude Code permette (campi statusline, comandi, limiti degli
  hook) sono **verificati sui doc ufficiali**, non ricordati a memoria. Se ne
  serve uno nuovo, verificalo e registralo come `SCOPERTA`.
- Le strade elencate come `SCARTATO` in `STORICO.md` non vanno riproposte senza
  un motivo nuovo che invalidi quello per cui erano state scartate.
