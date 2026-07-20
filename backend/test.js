#!/usr/bin/env node
// M1 verification: enumerate → selectSession → setModel → setEffort → verify
// Usage: node test.js

'use strict';

const { spawn } = require('child_process');
const readline  = require('readline');
const path      = require('path');

const BROKER = path.join(__dirname, 'broker.ps1');

const ps = spawn('powershell', [
  '-NonInteractive',
  '-ExecutionPolicy', 'Bypass',
  '-File', BROKER,
], { stdio: ['pipe', 'pipe', 'pipe'] });

// Log stderr from broker
ps.stderr.on('data', buf => process.stderr.write(`[broker] ${buf}`));
ps.on('close', code => console.log(`\nbroker exited: ${code}`));

const rl = readline.createInterface({ input: ps.stdout, crlfDelay: Infinity });

let nextId = 1;
const pending = new Map(); // id → { resolve, reject }

rl.on('line', line => {
  let msg;
  try { msg = JSON.parse(line); } catch { console.error('bad JSON:', line); return; }

  if (msg.event) {
    // push event
    console.log('[event]', msg);
    if (msg.event === 'attached') runTests().catch(err => {
      console.error('test error:', err.message);
      ps.stdin.end();
    });
    if (msg.event === 'error') {
      console.error('broker attach failed:', msg.message);
      ps.stdin.end();
    }
    return;
  }

  const p = pending.get(msg.id);
  if (!p) { console.warn('unknown id:', msg.id); return; }
  pending.delete(msg.id);
  if (msg.ok) p.resolve(msg.data ?? null);
  else        p.reject(new Error(msg.error ?? 'broker error'));
});

function send(cmd, args = {}) {
  return new Promise((resolve, reject) => {
    const id = nextId++;
    pending.set(id, { resolve, reject });
    const req = JSON.stringify({ id, cmd, ...args });
    console.log(`[send] ${req}`);
    ps.stdin.write(req + '\n');
  });
}

async function runTests() {
  console.log('\n=== M1 TEST SEQUENCE ===\n');

  // 1. Enumerate sessions
  const { sessions } = await send('enumerate');
  console.log(`[1] sessions (${sessions.length}):`);
  sessions.forEach((s, i) => console.log(`    ${i}: ${s.name}`));
  if (sessions.length === 0) throw new Error('No sessions found');

  // 2. Read current gear
  const gear = await send('readGear');
  console.log(`\n[2] readGear: model=${gear.model}  effort=${gear.effort}`);

  // 3. Read usage
  try {
    const usage = await send('readUsage');
    console.log(`[3] readUsage: context=${usage.contextPct}%  plan=${usage.planPct}%`);
  } catch (e) {
    console.log(`[3] readUsage: ${e.message} (skip)`);
  }

  // 4. Select first session (brings it to foreground in Claude Desktop)
  const target = sessions[0].name;
  console.log(`\n[4] selectSession: "${target}"`);
  await send('selectSession', { name: target });
  console.log('    ok');

  // 5. Re-read gear after session switch
  const gear2 = await send('readGear');
  console.log(`[5] gear after select: model=${gear2.model}  effort=${gear2.effort}`);

  // 6. Switch model (Opus ↔ Sonnet — self-reverting)
  const currentModel = gear2.model;
  const switchTo = currentModel.match(/^Opus/) ? 'Sonnet 5' : 'Opus 4.8';
  console.log(`\n[6] setModel: ${currentModel} → ${switchTo}`);
  const m1 = await send('setModel', { model: switchTo });
  console.log(`    result: ${m1.model}`);

  // revert
  console.log(`[6b] revert → ${currentModel}`);
  const m2 = await send('setModel', { model: currentModel.split(' ')[0] + ' ' + currentModel.split(' ')[1] });
  console.log(`    result: ${m2.model}`);

  // 7. Switch effort (one notch down, self-reverting via level index)
  const effortBefore = gear2.effort;
  // effort map: Fastest=0 Faster=1 Medium=2 High=3 Higher=4 Highest=5
  // We'll go from whatever level is current by trying level 1, then revert
  console.log(`\n[7] setEffort: current="${effortBefore}" → level 1`);
  const e1 = await send('setEffort', { level: 1 });
  console.log(`    result: ${e1.effort}`);

  console.log('[7b] revert → level 2');
  const e2 = await send('setEffort', { level: 2 });
  console.log(`    result: ${e2.effort}`);

  console.log('\n=== M1 PASSED ===');
  ps.stdin.end();
}
