'use strict';
// Node-side client for broker.ps1 — spawns it and speaks NDJSON over stdio.

const { spawn } = require('child_process');
const readline = require('readline');
const path = require('path');

const BROKER = path.join(__dirname, 'broker.ps1');

// Nessun comando del broker ha mai avvicinato questo tempo: `capabilities` sta
// sui 6 s, `setModel` sui 2,5 s, e il piu' lento (`probeEffort`, che spazza
// tutta la scala) sulle decine di secondi. Non e' una stima di quanto ci mette
// una risposta: e' il punto oltre il quale si smette di aspettarla.
const DEFAULT_TIMEOUT_MS = 120000;

class Broker {
  constructor({ verbose = false, onLog = null, onEvent = null, timeoutMs = DEFAULT_TIMEOUT_MS } = {}) {
    this.verbose = verbose;
    this.onLog = onLog;
    // Unsolicited messages from the broker: attached / reattached / detached.
    // The GUI needs these to show when Claude Desktop went away and came back,
    // without polling for it.
    this.onEvent = onEvent;
    this.timeoutMs = timeoutMs;
    this.nextId = 1;
    this.pending = new Map();
    this.ps = null;
    this._attached = null;
    // Set once the child is gone. A request sent after that has nobody to
    // answer it, and must be refused immediately rather than parked forever.
    this.dead = false;
  }

  start() {
    this.ps = spawn('powershell', [
      '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', BROKER,
    ], { stdio: ['pipe', 'pipe', 'pipe'] });

    // The broker's diagnostics go to stderr. Route them into the report rather
    // than letting them reach the console: PowerShell 5.1 turns any stderr from
    // a native command into a NativeCommandError and kills the run.
    if (this.onLog) {
      let buf = '';
      this.ps.stderr.on('data', chunk => {
        buf += String(chunk);
        const parts = buf.split(/\r?\n/);
        buf = parts.pop();
        parts.filter(Boolean).forEach(l => this.onLog(l));
      });
    } else if (this.verbose) {
      this.ps.stderr.on('data', b => process.stderr.write(String(b)));
    }

    const rl = readline.createInterface({ input: this.ps.stdout, crlfDelay: Infinity });
    rl.on('line', line => this._onLine(line));

    // A spawn failure (PowerShell missing) or an exit before the attach event
    // must reject start(), not leave the caller hanging until the deadline.
    // Rejecting an already-settled attach promise is a no-op, so these are
    // safe after a successful attach too.
    // Writing to a dead child raises EPIPE on the stream itself; without a
    // listener that is an unhandled 'error' event, which takes the whole process
    // down. In a GUI that means the app dies because Claude Desktop's broker did.
    this.ps.stdin.on('error', err => this.onLog?.(`[client] stdin: ${err.message}`));

    this.ps.on('error', err => { this.dead = true; this._attachReject?.(err); });
    this.ps.on('close', code => {
      this.dead = true;
      this._attachReject?.(new Error(`broker exited (code ${code}) before attaching`));
      for (const p of this.pending.values()) {
        clearTimeout(p.timer);
        p.reject(new Error(`broker exited (code ${code})`));
      }
      this.pending.clear();
    });

    // Resolves when the broker reports it has attached to Claude Desktop.
    this._attached = new Promise((resolve, reject) => {
      this._attachResolve = resolve;
      this._attachReject = reject;
    });
    return this._attached;
  }

  _onLine(line) {
    line = line.trim();
    if (!line) return;
    let msg;
    try { msg = JSON.parse(line); } catch { return; }

    if (msg.event) {
      if (msg.event === 'attached') this._attachResolve?.({ pid: msg.pid });
      else if (msg.event === 'error') this._attachReject?.(new Error(msg.message));
      this.onEvent?.(msg);
      return;
    }

    const p = this.pending.get(msg.id);
    if (!p) return;   // includes a reply that arrives after its own timeout
    this.pending.delete(msg.id);
    clearTimeout(p.timer);
    if (msg.ok) p.resolve(msg.data ?? null);
    else p.reject(new Error(msg.error ?? 'broker error'));
  }

  // Every request carries a deadline, and one sent to a dead broker is refused
  // on the spot.
  //
  // Without this a request could sit in `pending` forever: the broker dies, and
  // the promise for a command sent afterwards is neither resolved nor rejected
  // -- nothing failed, time simply passed. Measured: killing the broker and
  // sending readGear produced no answer and no error, ever. `withDeadline` does
  // not cover this; it kills the whole process, which is fine for a script and
  // useless inside a GUI, where the result would be a lever stuck on "sto
  // cambiando..." with no way out.
  //
  // The timer is deliberately NOT unref'd: a script awaiting only this promise
  // must fail loudly, not let Node exit 0 as if nothing had been asked.
  send(cmd, args = {}, { timeoutMs = this.timeoutMs } = {}) {
    return new Promise((resolve, reject) => {
      if (this.dead) return reject(new Error(`${cmd}: il broker non e' piu' in esecuzione`));
      if (!this.ps || !this.ps.stdin || !this.ps.stdin.writable) {
        return reject(new Error(`${cmd}: broker non avviato (manca start())`));
      }

      const id = this.nextId++;
      const entry = { resolve, reject, timer: null };
      if (timeoutMs > 0) {
        entry.timer = setTimeout(() => {
          this.pending.delete(id);
          reject(new Error(`${cmd}: nessuna risposta entro ${Math.round(timeoutMs / 1000)}s`));
        }, timeoutMs);
      }
      this.pending.set(id, entry);

      try {
        this.ps.stdin.write(JSON.stringify({ id, cmd, ...args }) + '\n');
      } catch (err) {
        this.pending.delete(id);
        clearTimeout(entry.timer);
        reject(new Error(`${cmd}: invio fallito (${err.message})`));
      }
    });
  }

  // One round trip, everything the lever needs to draw itself. See Op-Capabilities
  // in broker.ps1 for why this is one command and not three.
  //
  // The lists are normalised here because PowerShell 5.1's JSON serialiser turns
  // a one-element array into a bare object, so `models` arrives as an array of
  // seven but would arrive as a lone object if the app ever offered one model.
  // The GUI must never have to know that.
  async capabilities() {
    const c = await this.send('capabilities');
    return {
      ...c,
      models: [].concat(c.models ?? []),
      errors: [].concat(c.errors ?? []),
    };
  }

  // Same trap capabilities() guards against, and the reason this is a method
  // rather than a raw send: PowerShell 5.1 serialises a one-element array as a
  // bare object, so an app offering a single model would answer with an object
  // and every caller doing .length or .forEach on it would break. Callers get a
  // list, always.
  async listModels() {
    const r = await this.send('listModels');
    return [].concat(r.models ?? []);
  }

  stop() {
    this.ps?.stdin.end();
    // The child normally exits on stdin close; make sure a stuck one can never
    // hold the caller open forever.
    const ps = this.ps;
    const t = setTimeout(() => { try { ps?.kill(); } catch {} }, 3000);
    t.unref();
  }
}

// Collects every line of a run and writes it to a file. Scripts report through
// this instead of the console so results survive regardless of how the shell
// treats the process's output streams.
function makeReport(file) {
  const fs = require('fs');
  const lines = [];
  const flush = () => { try { fs.writeFileSync(file, lines.join('\n') + '\n', 'utf8'); } catch {} };
  return {
    log: (...a) => { lines.push(a.join(' ')); flush(); },
    flush,
    file,
  };
}

// Kill the whole run after `seconds`, so a hung UIA call surfaces as a written
// result instead of a command that never returns.
// Accepts a report from makeReport or null: the console-only diagnostics pass
// null and still get the timeout message (on stderr) and the exit code.
function withDeadline(seconds, report, label = 'operazione') {
  const t = setTimeout(() => {
    const msg = `\nTIMEOUT: ${label} non ha risposto entro ${seconds}s.`;
    if (report?.log) { report.log(msg); report.flush?.(); }
    else console.error(msg);
    process.exit(2);
  }, seconds * 1000);
  t.unref();
  return t;
}

module.exports = { Broker, withDeadline, makeReport };
