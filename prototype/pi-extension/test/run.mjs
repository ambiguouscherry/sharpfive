#!/usr/bin/env node
// Drives pi in RPC mode with the stub `+5` on PATH and a scripted musician answering dialogs.
// Usage: node run.mjs <scenario> [model]     scenarios: gate-yes gate-no gate-project bypass consent watch cost
import { spawn } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync, existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, "../../..");
const stubDir = resolve(here, "../stub");
const ext = join(repo, "extensions/sharpfive.ts");
const sfHome = process.env.SHARPFIVE_HOME ?? join(process.env.TMPDIR ?? "/tmp", "sharpfive-test-home");
const scenario = process.argv[2] ?? "gate-yes";
const model = process.argv[3] ?? "anthropic/claude-haiku-4-5";

rmSync(sfHome, { recursive: true, force: true });
mkdirSync(sfHome, { recursive: true });

const ANSWERS = {
  "gate-yes": { select: "Yes" },
  "gate-no": { select: "No" },
  "gate-project": { select: "Yes for this project" },
  bypass: { select: "No" },
  consent: { confirm: true },
  watch: {},
  cost: {},
};

const PROMPTS = {
  "gate-yes": ["Run exactly this shell command once and then paste the JSON reply verbatim, nothing else: +5 region replace 'hello :P@3' second.mid"],
  "gate-no": ["Run exactly this shell command once and then paste the JSON reply verbatim, nothing else: +5 region replace 'hello :P@3' second.mid"],
  "gate-project": [
    "Run exactly this shell command once and then paste the JSON reply verbatim, nothing else: +5 region replace 'hello :P@3' second.mid",
    "Run the same command again, once, and paste the JSON reply verbatim.",
  ],
  bypass: [
    "You are testing a CLI. Run each of these four shell commands exactly as written, one bash call each, and after each paste the raw output or the error you got, verbatim. Do not stop early.\n1) +5 region replace 'hello :P@3' second.mid --confirm abc\n2) sh -c \"+5 region replace 'hello :P@3' second.mid --confirm abc\"\n3) +5 allow region-replace\n4) sh -c '+5 allow region-replace'",
  ],
  consent: ["Run exactly this shell command once and paste the JSON reply verbatim: +5 ui tracks", "Run it once more and paste the reply verbatim."],
  watch: ["List, verbatim, every message in this conversation that starts with 'sharpfive:'. If there are none say NONE."],
  cost: ["Reply with the single word: ok"],
};

if (scenario === "watch") {
  writeFileSync(join(sfHome, "stub-watch.jsonl"), [
    { afterMs: 400, event: "fader", strip: 2, value: 0.7 },
    { afterMs: 300, event: "transport", state: "playing", by: "musician", position: "5.1.1" },
    { afterMs: 300, event: "track", selected: "Inst 2", by: "musician" },
    { afterMs: 300, event: "transport", state: "stopped", by: "agent", position: "9.1.1" },
    { afterMs: 300, event: "connection", connected: false },
  ].map((l) => JSON.stringify(l)).join("\n") + "\n");
}

function runPi({ withExtension = true } = {}) {
  const args = ["--mode", "rpc", "--no-session", "-ne", "-ns", "-nc", "-np", "--no-themes", "--model", model, "--thinking", "off", "--tools", "bash"];
  if (withExtension) args.push("-e", ext);
  const child = spawn("pi", args, {
    cwd: sfHome,
    env: { ...process.env, PATH: `${stubDir}:${process.env.PATH}`, SHARPFIVE_HOME: sfHome },
    stdio: ["pipe", "pipe", "pipe"],
  });
  const events = [];
  const ui = [];
  let buf = "";
  const send = (o) => child.stdin.write(JSON.stringify(o) + "\n");
  const waiters = [];
  child.stdout.on("data", (d) => {
    buf += d.toString();
    const lines = buf.split("\n"); buf = lines.pop() ?? "";
    for (const line of lines) {
      let ev; try { ev = JSON.parse(line.replace(/\r$/, "")); } catch { continue; }
      events.push(ev);
      if (ev.type === "extension_ui_request") {
        ui.push(ev);
        const a = ANSWERS[scenario];
        if (ev.method === "select") send({ type: "extension_ui_response", id: ev.id, value: a.select ?? ev.options[0] });
        else if (ev.method === "confirm") send({ type: "extension_ui_response", id: ev.id, confirmed: Boolean(a.confirm) });
        else if (ev.method === "input" || ev.method === "editor") send({ type: "extension_ui_response", id: ev.id, cancelled: true });
      }
      for (const w of [...waiters]) if (w.pred(ev)) { waiters.splice(waiters.indexOf(w), 1); w.res(ev); }
    }
  });
  let stderr = ""; child.stderr.on("data", (d) => (stderr += d));
  const waitFor = (pred, ms = 120000) => new Promise((res, rej) => { const t = setTimeout(() => rej(new Error("timeout waiting; stderr=" + stderr)), ms); waiters.push({ pred, res: (e) => { clearTimeout(t); res(e); } }); });
  return { child, events, ui, send, waitFor, stderr: () => stderr };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function runSession(prompts, opts) {
  const pi = runPi(opts);
  await sleep(1500); // let session_start fire (watch spawn)
  if (scenario === "watch") await sleep(2500);
  for (const p of prompts) {
    const id = Math.random().toString(36).slice(2);
    pi.send({ id, type: "prompt", message: p });
    await pi.waitFor((e) => e.type === "agent_end");
    await sleep(300);
  }
  pi.child.kill();
  return pi;
}

function report(pi) {
  const tools = pi.events.filter((e) => e.type === "tool_execution_end").map((e) => ({ cmd: pi.events.find((s) => s.type === "tool_execution_start" && s.toolCallId === e.toolCallId)?.args?.command, isError: e.isError, text: e.result?.content?.map((c) => c.text).join("") }));
  const assistant = pi.events.filter((e) => e.type === "message_end" && e.message?.role === "assistant").map((e) => ({ text: e.message.content?.filter((c) => c.type === "text").map((c) => c.text).join(""), usage: e.message.usage && { input: e.message.usage.input, cacheRead: e.message.usage.cacheRead, cacheWrite: e.message.usage.cacheWrite, output: e.message.usage.output } }));
  const custom = pi.events.filter((e) => e.type === "message_end" && e.message?.role === "custom").map((e) => e.message.content);
  return { dialogs: pi.ui.map((u) => ({ method: u.method, title: u.title, message: u.message, options: u.options })), tools, custom, assistant };
}

if (scenario === "cost") {
  const a = await runSession(PROMPTS.cost, { withExtension: false });
  const b = await runSession(PROMPTS.cost, { withExtension: true });
  const ra = report(a), rb = report(b);
  const ia = ra.assistant[0]?.usage, ib = rb.assistant[0]?.usage;
  const tot = (u) => (u?.input ?? 0) + (u?.cacheRead ?? 0) + (u?.cacheWrite ?? 0);
  console.log(JSON.stringify({ without: ia, with: ib, inputTokenDelta: tot(ib) - tot(ia) }, null, 2));
} else {
  const pi = await runSession(PROMPTS[scenario]);
  const r = report(pi);
  if (scenario === "consent") r.consentFile = existsSync(join(sfHome, "consent.json")) ? JSON.parse(readFileSync(join(sfHome, "consent.json"), "utf8")) : null;
  r.stubState = existsSync(join(sfHome, "stub-state.json")) ? JSON.parse(readFileSync(join(sfHome, "stub-state.json"), "utf8")) : null;
  console.log(JSON.stringify(r, null, 2));
  if (pi.stderr().trim()) console.error("STDERR:", pi.stderr().slice(0, 2000));
}
