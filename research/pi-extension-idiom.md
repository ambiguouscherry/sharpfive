# Research: pi's extension and skill idiom

Fact check for [Grilling: spec pi tool schemas and skill docs](https://github.com/ambiguouscherry/sharpfive/issues/11). Fetched 2026-10-11 from pi.dev and the pi repository. Verbatim quotes are from the docs at that date.

## Naming

The repository moved from `github.com/badlogic/pi-mono` to `github.com/earendil-works/pi` (the old path redirects). The package is `@earendil-works/pi-coding-agent`; `@mariozechner/pi-coding-agent` no longer appears in the README. Docs live at `packages/coding-agent/docs/*.md`.

## Skills

Source: `docs/skills.md`.

- "Pi implements the Agent Skills specification" (agentskills.io/specification).
- A skill is a directory with `SKILL.md` (frontmatter plus instructions); "Skills can bundle scripts, references, and assets alongside their instructions." Frontmatter: `name` (lowercase, digits, hyphens, max 64), `description` (max 1024; routing text), `license`, `compatibility`, `metadata`, `allowed-tools` (experimental), `disable-model-invocation`. A missing description means the skill is not loaded.
- Locations: `~/.pi/agent/skills/`, `.pi/skills/`, plus the Agent Skills locations `~/.agents/skills/` and `.agents/skills/` ("discovered from the working directory through its ancestors"). Directories containing `SKILL.md` are discovered recursively. Packages can declare skills too.
- Progressive disclosure, verbatim: "At startup, Pi scans configured skill locations and adds each skill's name, description, and path to the system prompt. It does not add the full instructions." "This keeps detailed guidance out of context until it is needed." `/skill:name` forces a load; `disable-model-invocation: true` makes a skill command-only. `/reload` picks up edits.
- No body-length guidance beyond the 64 and 1024 limits.

## Extensions and custom tools

Sources: `docs/extensions.md`, `examples/extensions/README.md`, `src/core/extensions/types.ts`.

- Layout: `~/.pi/agent/extensions/` and `.pi/extensions/`; `.ts` or `.js` files, or directories with `index.ts`. Dev: `pi --extension ./hello.ts`. Factory: `export default function (pi: ExtensionAPI)`.
- Register a tool (verbatim from the examples README):

```ts
pi.registerTool({
  name: "greet", label: "Greeting", description: "Generate a greeting",
  parameters: Type.Object({ name: Type.String({ description: "Name to greet" }) }),
  async execute(toolCallId, params, signal, onUpdate, ctx) {
    return { content: [{ type: "text", text: `Hello, ${params.name}!` }], details: {} };
  },
});
```

- Result: `content` (text or image, sent to the model), `details` (arbitrary, for logs or UI), optional `structuredContent` (not sent to the model), `isError`, `terminate`. Rendering: `renderCall` and `renderResult` draw a tool's calls in the transcript; `registerToolRenderer` applies to any tool name.

## Permission and confirmation

- UI: `ctx.ui.confirm(title, message)`, `select`, `input`, `editor`, `notify`, `setWidget`, `custom`. Guard with `ctx.hasUI`.
- Interception: the `tool_call` event "can mutate input or block execution. A handler failure blocks the tool." Result `{ block?: boolean; reason?: string }`. Verbatim example:

```ts
pi.on("tool_call", async (event, ctx) => {
  if (event.toolName === "bash" && event.input.command?.includes("rm -rf")) {
    const ok = await ctx.ui.confirm("Dangerous!", "Allow rm -rf?");
    if (!ok) return { block: true, reason: "Blocked by user" };
  }
});
```

- State: `appendEntry(customType, data)` "persists non-context session data, which is excluded from model context." Rebuild from `ctx.sessionManager.getBranch()` on `session_start`.

## Dynamic context injection

- `before_agent_start` "exposes both the current prompt and its structured `systemPromptOptions`"; the docs prefer editing sections over replacing the whole prompt, to keep the cache delta small. Returning `systemPrompt` replaces the prompt for that run. The example `pirate.ts` demonstrates `systemPromptAppend`.
- `context` transforms conversation messages for one run; `message_end` can replace a finalised message.
- Async push: `pi.sendMessage(msg, { triggerTurn?, deliverAs?: "steer" | "followUp" | "nextTurn" })`. "Steering messages enter after the current assistant turn." "Follow-up messages enter after the agent has finished its pending work." `nextTurn` is in the type union; its semantics are not described in the docs (unverified).

## Packaging

Source: `docs/packages.md`, `docs/configuration.md`.

- `pi install npm:@scope/pkg@1.0.0`, `pi install git:github.com/org/repo@v1`, `pi install ./local`. `--local` writes to `.pi/settings.json`.
- `package.json`: `"keywords": ["pi-package"]`, `"pi": { "extensions": [...], "skills": [...], "prompts": [...], "themes": [...] }`; without a manifest, conventional `extensions/`, `skills/`, `prompts/`, `themes/` directories.
- Context files: `AGENTS.md` (and `CLAUDE.md`) loaded from the agent directory, the working directory and its parents. "Context-file discovery does not require project trust."

## MCP

- Historically absent on purpose (Armin Ronacher, 2026-01-31: "this is not a lazy omission. This is from the philosophy of how Pi works... you ask the agent to extend itself").
- Native since v0.99.0 (2026-09-29): "Added codemode, tool search, and MCP support as built-in extensions." Rationale (earendil.com/posts/you-said-no-mcp, 2026-09-29): "The biggest issue with MCP continues to be that it's hard to compose." "The reason CLIs are so functional is that the agent and model just wire stuff together with efficient bashisms."
- `docs/mcp.md`: `~/.pi/agent/mcp.json` and `.pi/mcp.json`, stdio or HTTP servers. Exposure per tool: `codemode` (default: callable from scripts, not declared to the model), `deferred`, `direct`, `hidden`. Extensions: `pi.registerMcpServer`.

## What this means for sharpfive

- The shell-plus-skill path is pi's own stated idiom; the CLI is composable from bash.
- The two things the shell cannot do, a gate the agent cannot talk past and per-turn context, are exactly the `tool_call` and `before_agent_start` hooks.
- One package ships the extension and the skill. The binary installs separately.
- Typed tools and MCP exposure remain available as later layers over the same CLI.

## Sources

- https://pi.dev and https://pi.dev/docs/latest/
- https://github.com/earendil-works/pi/tree/main/packages/coding-agent/docs (skills.md, extensions.md, packages.md, configuration.md, mcp.md, how-pi-works.md)
- https://github.com/earendil-works/pi/blob/main/packages/coding-agent/examples/extensions/README.md
- https://lucumr.pocoo.org/2026/1/31/pi.md
- https://earendil.com/posts/you-said-no-mcp/
