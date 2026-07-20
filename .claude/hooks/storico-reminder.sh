#!/usr/bin/env bash
# Stop hook — promemoria di aggiornamento di PROJECT.md / STORICO.md.
#
# Non blocca mai la sessione: inietta solo contesto. Si zittisce da solo appena
# STORICO.md contiene una voce datata oggi, e comunque non parla piu' di una
# volta ogni 30 minuti per sessione.
#
# Portabile: bash (Git Bash su Windows, sh su macOS/Linux).

set -u

INPUT="$(cat)"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
STORICO="$PROJECT_DIR/STORICO.md"
TODAY="$(date +%Y-%m-%d)"

# Nessuno STORICO.md da aggiornare -> niente da ricordare.
[ -f "$STORICO" ] || exit 0

# Voce di oggi gia' presente -> silenzio per il resto della giornata.
grep -q "^## ${TODAY}" "$STORICO" && exit 0

# Throttle per sessione: il hook Stop scatta a ogni turno, il promemoria no.
SESSION_ID="$(printf '%s' "$INPUT" \
  | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[ -n "$SESSION_ID" ] || SESSION_ID="unknown"

STAMP_DIR="${TMPDIR:-/tmp}/model-and-furious"
mkdir -p "$STAMP_DIR" 2>/dev/null || true
STAMP="$STAMP_DIR/${SESSION_ID}.stamp"

NOW="$(date +%s)"
if [ -f "$STAMP" ]; then
  LAST="$(cat "$STAMP" 2>/dev/null || echo 0)"
  case "$LAST" in ''|*[!0-9]*) LAST=0 ;; esac
  [ "$((NOW - LAST))" -lt 1800 ] && exit 0
fi
printf '%s' "$NOW" > "$STAMP" 2>/dev/null || true

cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"PROMEMORIA OBBLIGATORIO (hook di progetto MODEL AND FURIOUS): STORICO.md non contiene ancora una voce datata oggi. Se questa sessione ha prodotto qualcosa di registrabile (decisione, fix, bug, strada scartata, modifica al repo), prima di chiudere DEVI chiedere all'utente: \"Aggiorno PROJECT.md e STORICO.md con quanto fatto oggi?\". Attendi conferma esplicita: non aggiornare di tua iniziativa, e non chiudere la sessione senza aver posto la domanda. Se la sessione e' stata puramente informativa, ignora questo promemoria."}}
JSON

exit 0
