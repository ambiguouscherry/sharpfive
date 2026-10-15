/**
 * sharpfive pi extension (development form; ADR 0004).
 *
 * Does two things only, per spec/tool-schemas.md §1, §4, §5, §7:
 *   1. Gates: a `+5` command that replies `status: gated` is shown to the musician in pi's own
 *      dialog, built from the daemon's payload. On yes the extension re-runs the command with the
 *      gate token. The agent cannot pass `--confirm` itself: the hook blocks it, and the daemon
 *      only accepts a token it issued, which the agent never sees.
 *   2. Context: before each turn, `+5 state` becomes a five-line turn summary appended to the
 *      system prompt. The daemon's `watch` stream pushes three kinds of event into the loop.
 *
 * It defines no verbs and touches no MIDI.
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { spawn, type ChildProcess } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const BIN = process.env.SHARPFIVE_BIN ?? "+5";
const HOME = process.env.SHARPFIVE_HOME ?? join(homedir(), ".sharpfive");
const CONSENT_FILE = join(HOME, "consent.json");

type Reply = Record<string, unknown> & { status?: string; reason?: string; hint?: string; scope?: string; gate?: Gate };
type Gate = { kind: string; action: string; target: string; diff: string; undo: string; allowance: "offered" | "none"; token?: string };

// A `+5` invocation is one simple command: no pipes, no chaining. Anything else is left alone
// (the daemon still enforces the token, so the gate holds; only the dialog UX is lost).
const SIMPLE = /^\s*\+5(?:\s+[^|;&<>`$()]*)?$/;
const MENTIONS = /(^|[\s;&|(`])\+5(\s|$)/;
const isSimplePlusFive = (cmd: string) => SIMPLE.test(cmd);
const mentionsPlusFive = (cmd: string) => MENTIONS.test(cmd);

function lastJsonLine(text: string): Reply | undefined {
  const lines = text.trim().split("\n").filter((l) => l.trim().length > 0);
  for (let i = lines.length - 1; i >= 0; i--) {
    try { return JSON.parse(lines[i]) as Reply; } catch { /* keep looking */ }
  }
  return undefined;
}

const textOf = (content: { type: string; text?: string }[]) => content.filter((c) => c.type === "text").map((c) => c.text ?? "").join("\n");
const asText = (obj: unknown) => [{ type: "text" as const, text: JSON.stringify(obj) }];
const shq = (s: string) => `'${s.replace(/'/g, `'\\''`)}'`;

function gateLines(g: Gate): string {
  const allowance = g.allowance === "offered"
    ? `allowance  Yes for this project lifts ${g.kind} until the project changes.`
    : `allowance  none: this kind always asks.`;
  return [
    `sharpfive gate · ${g.kind}`,
    `action     ${g.action}`,
    `target     ${g.target}`,
    `change     ${g.diff}`,
    `undo       ${g.undo}`,
    allowance,
  ].join("\n");
}

function readConsent(): { scopes: Record<string, { granted: boolean; at: string }> } {
  try { return JSON.parse(readFileSync(CONSENT_FILE, "utf8")); } catch { return { scopes: {} }; }
}
function grantConsent(scope: string) {
  const c = readConsent();
  c.scopes[scope] = { granted: true, at: new Date().toISOString() };
  mkdirSync(HOME, { recursive: true });
  writeFileSync(CONSENT_FILE, JSON.stringify(c, null, 2) + "\n");
}

export default function sharpfive(pi: ExtensionAPI) {
  // `--` matters: every POSIX shell reads `-c "+5 …"` as an option string, because an argument
  // that starts with `+` toggles shell options. `sh -c -- "+5 …"` is the correct spelling.
  const run = (cmd: string, ctx: ExtensionContext) => pi.exec("sh", ["-c", "--", cmd], { cwd: ctx.cwd, timeout: 30_000 });

  // ---- 1. the agent may not answer gates itself ---------------------------------------------
  pi.on("tool_call", async (event) => {
    if (event.toolName !== "bash") return;
    const cmd = String((event.input as { command?: string }).command ?? "");
    if (!mentionsPlusFive(cmd)) return;
    // pi's bash tool spawns `bash -c <command>` without `--`, so a command that begins with `+5`
    // is read by bash as an option string ("+5: invalid option"). A leading space defuses that
    // and changes nothing else. The pi fork (ADR 0004) should pass `--` instead.
    if (/^\+5(\s|$)/.test(cmd)) (event.input as { command: string }).command = ` ${cmd}`;
    if (/--confirm\b|--allow-project\b/.test(cmd)) {
      return { block: true, reason: "sharpfive: gates are answered by the musician in the dialog, never by the agent. Run the command without --confirm; the dialog opens on its own." };
    }
    if (/\+5\s+allow\s+\S+(?!.*--revoke)/.test(cmd) && !/--revoke\b/.test(cmd)) {
      return { block: true, reason: "sharpfive: allowances are the musician's to grant (the gate dialog offers 'Yes for this project'). Revoking is fine." };
    }
  });

  // ---- 2. gated and no-consent replies become dialogs ---------------------------------------
  pi.on("tool_result", async (event, ctx) => {
    if (event.toolName !== "bash") return;
    const cmd = String((event.input as { command?: string }).command ?? "");
    if (!mentionsPlusFive(cmd)) return;
    const reply = lastJsonLine(textOf(event.content as never));
    if (!reply) return;

    if (reply.status === "gated" && reply.gate) {
      const gate = reply.gate;
      const token = gate.token;
      delete gate.token; // the model never sees the token
      if (!ctx.hasUI || !token) {
        return { content: asText({ status: "failed", reason: "gate-no-dialog", hint: "This action needs the musician's yes in the sharpfive dialog, and no dialog is available here. Nothing was changed." }), isError: true };
      }
      if (!isSimplePlusFive(cmd)) {
        return { content: asText({ status: "failed", reason: "gate-complex-command", hint: "Run the gated +5 command on its own, with no pipes or chaining, so the dialog can re-run it." }), isError: true };
      }
      const options = gate.allowance === "offered" ? ["No", "Yes", "Yes for this project"] : ["No", "Yes"];
      const answer = await ctx.ui.select(gateLines(gate), options, { signal: ctx.signal });
      if (answer !== "Yes" && answer !== "Yes for this project") {
        pi.appendEntry("sharpfive-gate", { kind: gate.kind, answer: "no" });
        return { content: asText({ status: "failed", reason: "gate-declined", hint: "The musician said no. Stop and say so; do not retry.", gate }), isError: true };
      }
      const extra = answer === "Yes for this project" ? " --allow-project" : "";
      const res = await run(`${cmd} --confirm ${shq(token)}${extra}`, ctx);
      pi.appendEntry("sharpfive-gate", { kind: gate.kind, answer, code: res.code });
      const confirmed = lastJsonLine(res.stdout) ?? { status: "failed", reason: "no-reply", hint: res.stderr.trim() || "sharpfive printed nothing." };
      return { content: asText({ ...confirmed, gate: { kind: gate.kind, answer } }), isError: res.code !== 0 };
    }

    if (reply.status === "failed" && reply.reason === "no-consent" && reply.scope) {
      const scope = reply.scope;
      if (!ctx.hasUI) return;
      if (readConsent().scopes[scope]?.granted) return; // already granted; let the failure stand (daemon out of sync)
      const yes = await ctx.ui.confirm(`sharpfive needs access to ${scope}`, `${reply.hint ?? ""}\nAsked once; remembered in ${CONSENT_FILE}. Take it back any time with: +5 consent revoke ${scope}`, { signal: ctx.signal });
      if (!yes) {
        return { content: asText({ status: "failed", reason: "consent-declined", scope, hint: `The musician did not grant ${scope} access. Stop and say so.` }), isError: true };
      }
      grantConsent(scope);
      pi.appendEntry("sharpfive-consent", { scope });
      if (!isSimplePlusFive(cmd)) return { content: asText({ status: "ok", consent: { scope, granted: true }, hint: "Consent granted. Run the command again." }), isError: false };
      const res = await run(cmd, ctx);
      const again = lastJsonLine(res.stdout) ?? { status: "failed", reason: "no-reply", hint: res.stderr.trim() };
      return { content: asText({ ...again, consent: { scope, granted: true } }), isError: res.code !== 0 };
    }
  });

  // ---- 3. the turn summary ------------------------------------------------------------------
  pi.on("before_agent_start", async (event, ctx) => {
    const res = await pi.exec(BIN, ["state"], { cwd: ctx.cwd, timeout: 2_000 }).catch((e: Error) => ({ stdout: "", stderr: String(e), code: 127, killed: false }));
    const summary = turnSummary(lastJsonLine(res.stdout), res);
    pi.appendEntry("sharpfive-summary", { chars: summary.length, estTokens: Math.ceil(summary.length / 4) });
    ctx.ui.setStatus("sharpfive", summary.split("\n")[1]?.slice(0, 48));
    return { systemPrompt: `${event.systemPrompt}\n\n${summary}` };
  });

  function turnSummary(reply: Reply | undefined, res: { code: number; stderr: string }): string {
    const head = "## sharpfive now";
    if (!reply) return `${head}\nsharpfive: the +5 command gave no reply (exit ${res.code}). ${res.code === 127 ? "The binary is not installed; the install is the musician's to do." : res.stderr.trim()}`;
    if (reply.status === "failed") return `${head}\nnot connected. Hint for the musician: ${reply.hint}`;
    const s = (reply as { state?: Record<string, any> }).state ?? {};
    if (s.connection && s.connection.connected === false) return `${head}\nnot connected. Hint for the musician: ${s.connection.hint}`;
    const allow = (s.allowances ?? []) as string[];
    return [
      head,
      `connected to Logic (${s.connection?.surface ?? "control surface"}); project ${s.project?.name ?? "?"}${s.project?.saved === false ? " (unsaved)" : ""}`,
      `selected track: ${s.selected?.track ?? "?"} (strip ${s.selected?.strip ?? "?"})`,
      `transport: ${s.transport?.state ?? "?"} at ${s.transport?.position ?? "?"}${s.transport?.cycle ? ", cycle on" : ""}${s.transport?.replace ? ", REPLACE on" : ""}`,
      `assignment: ${s.assignment ?? "?"}`,
      `allowances: ${allow.length ? allow.join(", ") : "none"}`,
    ].join("\n");
  }

  // ---- 4. pushes from the watch stream ------------------------------------------------------
  let watcher: ChildProcess | undefined;
  pi.on("session_start", async (_event, ctx) => {
    watcher?.kill();
    watcher = spawn(BIN, ["watch"], { cwd: ctx.cwd, stdio: ["ignore", "pipe", "ignore"] });
    let buf = "";
    watcher.stdout?.on("data", (chunk: Buffer) => {
      buf += chunk.toString();
      const lines = buf.split("\n");
      buf = lines.pop() ?? "";
      for (const line of lines) {
        let ev: Record<string, any>;
        try { ev = JSON.parse(line); } catch { continue; }
        const text = pushText(ev);
        if (!text) continue;
        // Connection lost interrupts whatever the agent is doing (steer); the musician's own
        // transport and track moves are information for the next turn, never a reason to speak.
        const deliverAs = ev.event === "connection" ? "steer" : "nextTurn";
        pi.sendMessage({ customType: "sharpfive-push", content: text, display: true, details: ev }, { deliverAs, triggerTurn: false });
        ctx.ui.setStatus("sharpfive", text.slice(0, 48));
      }
    });
    watcher.on("exit", () => { watcher = undefined; });
  });
  pi.on("session_shutdown", async () => { watcher?.kill(); watcher = undefined; });

  function pushText(ev: Record<string, any>): string | undefined {
    if (ev.event === "connection" && ev.connected === false) return "sharpfive: Logic stopped talking to the control surface. Reads and writes will fail until it is back.";
    if (ev.event === "transport" && ev.by === "musician") return `sharpfive: the musician ${ev.state === "playing" ? "started" : ev.state === "recording" ? "started recording" : "stopped"} the transport at ${ev.position}.`;
    if (ev.event === "track" && ev.by === "musician") return `sharpfive: the musician selected the track ${ev.selected}.`;
    return undefined; // everything else is a `+5 state` call
  }
}
