# Prototype: the sharpfive pi extension (#40)

Built 2026-10-15 against stock pi 0.83.0 (first as `sf`, renamed `sf` the same day; see finding 1) (`@earendil-works/pi-coding-agent`), driven by a stub `sf` that replays canned replies in the shape `spec/tool-schemas.md` fixes. The extension itself is product code in its development form (ADR 0004) and lives at [`extensions/sharpfive.ts`](../../extensions/sharpfive.ts). Everything in this folder is throwaway.

## What is here

| Path | What |
|---|---|
| `stub/sf` | Node script. `state`, `watch`, `mute`, `region replace` (gate `region-replace`), `plugin remove` (gate `plugin-remove`, always ask), `ui tracks` (needs `screen` consent), `consent`, `allow`, `help`. State in `$SHARPFIVE_HOME` (default `~/.sharpfive`). |
| `test/run.mjs` | Drives pi in RPC mode with the stub on PATH and a scripted musician answering the dialogs. Scenarios: `gate-yes`, `gate-no`, `gate-project`, `bypass`, `consent`, `watch`, `cost`. |

Run: `SHARPFIVE_HOME=/tmp/sf node prototype/pi-extension/test/run.mjs gate-yes openai-codex/gpt-5.6-sol`. Interactive: `PATH=$PWD/prototype/pi-extension/stub:$PATH pi -e extensions/sharpfive.ts`.

## Results (2026-10-15, model gpt-5.6-sol via pi)

**The gate dialog, as pi's TUI renders it** (captured through a pty):

```
sharpfive gate · region-replace
action     Replace the region on hello :P at bar 3.
target     hello :P, bar 3 to 4.3, named "second"
change     2 notes moved, 1 added: C3 3.2 → 3.3, + E3 4.1. Everything else stays.
undo       Snapshot kept; Edit > Undo verified by export.
allowance  Yes for this project lifts region-replace until the project changes.

→ No
  Yes
  Yes for this project

↑↓ navigate  enter select  escape/ctrl+c cancel
```

Five lines from the daemon payload, three buttons, cursor on No. The TUI's `confirm` is a `select` with the message folded into the title, so a multi-line title is the supported way to show the lines.

| Scenario | Result |
|---|---|
| gate-yes | Dialog shown; musician picks Yes; extension re-runs with the gate token; model receives `status: confirmed … gate: {kind, answer: "Yes"}`. Token never appears in the model's context. |
| gate-no | Model receives `status: failed, reason: gate-declined` with the payload and the hint "stop and say so; do not retry". It stopped. |
| gate-project | "Yes for this project" → confirmed with `--allow-project`; the second identical command in the same session returned `confirmed, allowance: region-replace` with **no dialog**. |
| bypass | `sf … --confirm abc` → blocked in `tool_call` before it ran; `sf allow region-replace` → blocked; the `sh -c "sf …"` wrappings of both → blocked too (re-run after the rename). Run directly against the stub they fail anyway: `confirm-token-invalid` and `tty-required`. **The agent did not get past a gate without the dialog on any path.** |
| consent | `sf ui tracks` → `no-consent` → confirm dialog → `consent.json` written → command re-run → tracks. Second call: no dialog. |
| watch | Five scripted events; three pushed (transport by musician, track by musician, connection lost), two filtered (fader, transport by agent). All three in the next turn's context, no extra model reply. |
| cost | Turn summary = 190 chars, 6 lines. Measured **54 input tokens** per turn (626 vs 572 on the first call of an otherwise identical session). Estimate chars/4 = 48. |

## Findings that change the spec

1. **`+5` broke under `sh -c`, so the command was renamed `sf`** (Margot, 2026-10-15). Every POSIX shell reads `bash -c "+5 state"` as an option string, because an argument beginning with `+` toggles shell options: `bash: +5: invalid option` (bash, sh and zsh, all tested). pi's bash tool spawns `bash -c <command>` with no `--`, so every call failed until the extension prepended a space. With `sf` the workaround is gone; the harness re-ran clean after the rename.
2. **The gate needs a token.** `tool_call` fires before the command runs and cannot see the reply, so the dialog lives in `tool_result`; the re-run is a second command, and the agent could write `--confirm` itself. Fix: the `gated` reply carries a one-time `token` the extension strips from the model's view; `--confirm <token>` is accepted once, within ten minutes; a bare `--confirm` fails `confirm-token-invalid`. The `tool_call` block on `--confirm` is UX; the token is the guard.
3. **`sf allow` from the agent's shell is indistinguishable from the musician's terminal.** The stub refuses `allow <kind>` when stdin is not a TTY (`tty-required`); the hook blocks it too. Revoke stays allowed.
4. **The skill's `gated` row is wrong**: the agent does not repeat the command with `--confirm`; the extension re-runs it and the agent sees the final reply. Fixed in `spec/skill/SKILL.md`.
5. **Pushes**: `steer` for connection lost (interrupts the agent), `nextTurn` for the musician's transport and track moves (information, never a reason to speak). With `steer` for everything the agent spent an extra reply acknowledging a push.
6. **No dialog, no gate.** In print mode (`ctx.hasUI` false) a gated reply becomes `failed, reason: gate-no-dialog`. A gated `sf` inside a pipeline becomes `gate-complex-command` (the dialog cannot safely re-run a compound command).

## Not proven here

The real daemon's `watch` stream, the `by: musician | agent` attribution on transport events (the stub asserts it; the daemon has to derive it from MCU echo vs its own sends), and the ten-minute token expiry choice.
