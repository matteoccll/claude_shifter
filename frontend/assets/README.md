# assets/ — le foto della leva

Qui vanno le **3 foto vere** del cambio. Adesso ci sono dei **placeholder SVG**
generati a mano solo perché la app giri e si veda qualcosa: vanno sostituiti.

## I 3 slot

| File placeholder | Sostituire con | Quando appare |
|---|---|---|
| `shifter-6.svg` | foto **leva a 6 marce** (Low…Ultracode) | modelli a 6 marce (Fable 5, Opus 4.8/4.7, Sonnet 5) |
| `shifter-4.svg` | foto **leva a 4 marce** (Low, Medium, High, Max) | modelli a 4 marce (Opus 4.6, Sonnet 4.6) |
| `knob-haiku.svg` | foto **pomello-giocattolo** (clown "HAIKU 4.5") | Haiku 4.5 (nessuno splitter) |

## Come mettere le foto vere

1. Esporta le 3 foto e mettile qui. Puoi:
   - **tenere i nomi** `shifter-6`, `shifter-4`, `knob-haiku` (più comodo), oppure
   - usare altri nomi e aggiornare la mappa `IMAGES` in
     [`../renderer/app.js`](../renderer/app.js).
2. Se sono `.png`/`.jpg` invece che `.svg`, aggiorna l'estensione in `IMAGES`
   (`app.js`), es. `src: '../assets/shifter-6.png'`.
3. **Misura l'ancora del pomello** su ogni foto: il centro del pomello in
   percentuale dello stage (x da sinistra, y dall'alto). Mettila in `IMAGES`, campo
   `knob: { x, y }`. È lì che il codice scrive il nome del modello (decisione 4).

## Nota sul pomello "pulito"

Perché il codice possa scriverci sopra il nome del modello, il pomello nella foto
deve essere **liscio** (senza un nome già stampato). Le scritte delle **marce** nel
gate (Low/Medium/High…) invece possono restare stampate nella foto: sono fisse per
quel numero di marce. Vedi decisione 7 in [`../DECISIONI-FRONTEND.md`](../DECISIONI-FRONTEND.md).
