'use strict';
// Node-side client for broker.ps1 — spawns it and speaks NDJSON over stdio.

const { spawn } = require('child_process');
const readline = require('readline');
const path = require('path');

const BROKER = path.join(__dirname, 'broker.ps1');

class Broker {
  constructor({ verbose = false, onLog = null, onEvent = null } = {}) {
    this.verbose = verbose;
    this.onLog = onLog;
    // Unsolicited messages from the broker: attached / reattached / detached.
    // The GUI needs these to show when Claude Desktop went away and came back,
    // without polling for it.
    this.onEvent = onEvent;
    this.nextId = 1;
    this.pending = new Map();
    this.ps = null;
    this._attached = null;
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
    this.ps.on('error', err => this._attachReject?.(err));
    this.ps.on('close', code => {
      this._attachReject?.(new Error(`broker exited (code ${code}) before attaching`));
      for (const { reject } of this.pending.values()) {
        reject(new Error(`broker exited (code ${code})`));
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
    if (!p) return;
    this.pending.delete(msg.id);
    if (msg.ok) p.resolve(msg.data ?? null);
    else p.reject(new Error(msg.error ?? 'broker error'));
  }

  send(cmd, args = {}) {
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      this.pending.set(id, { resolve, reject });
      this.ps.stdin.write(JSON.stringify({ id, cmd, ...args }) + '\n');
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
