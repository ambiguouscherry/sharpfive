# Spec: the sharpfive interface

Resolves [#21](https://github.com/ambiguouscherry/sharpfive/issues/21). Designed with Margot in Figma across three sessions on 2026-10-15. Vocabulary in [CONTEXT.md](../CONTEXT.md). The design is a living thing: this spec records the decisions that hold, and the Figma file is the asset. New ideas and needs land as new issues and new frames in the same section; they do not reopen this one.

Figma: https://www.figma.com/design/hrz5vEtiT0UilzyBnYlzcA — page "panel screens", section "sharpfive panel — AU panel in Logic, 1275×756". Earlier passes live on the page "archive — earlier passes (pre v2)" and are not the direction.

## 1. The surface

The interface is the **AU panel inside Logic's plug-in window**, 1275×756. Not the terminal. The terminal command `sf` stays for people who want it; the panel is the product.

## 2. The feel

Pixel idiom, never intimidating: "hacking Logic through an 8-bit video game". Hard edges, limited palette (ink `#1a1a1f`, pale `#f4f3f8`, pink `#ff4fa3`, lavender `#c4b6f7`, white), DotGothic16 for body text, Silkscreen for small-caps labels, VT323 for titles. Icons over labels wherever an icon reads; icons are drawn as pixel rect grids (file, send, play, place, chevrons, viewer modes, the five verbs). The WRITE glyph is a quill; dictation is a speech bubble with a waveform.

## 3. Voice

The tool is an **extension of the musician**: an augmentation, an accelerator, not a character of its own. Every line of interface dialogue is in the **second person**. The tool refers to itself as **"the system"** and to the musician's character as **"your avatar"**. It never says I, me, my or we.

| Not this | This |
|---|---|
| I heard you hum for 6 s and I'm growing a bass line from it | You hummed for 6 s and it's kept as chorus hum. The system is growing a bass line from it |
| I NEED PERMISSION · Can I swap rain loop for verse bass? | YOUR CALL · Swap rain loop for verse bass? |
| Pick the brain I think with, and tell me what I'm allowed to reach | Pick the brain the system thinks with, and set what it may reach |
| Make me yours. I'll draw you | This is your avatar. Drop a photo to base it on you |

## 4. The five regions (home screen)

| Region | Where | What it holds |
|---|---|---|
| Avatar window | top left, 470×470 | the musician's avatar, animated per verb while the system works; a one-line caption of the current step |
| Response box | below it, 470×150 | portrait + a short, plain recap of what is happening, in the voice above |
| Motif viewer | top right, 749×310 | the active motif: name, kind, bars, track, provenance; a visualiser per kind (MIDI piano roll, sample spectrum, stem breakdown); play, PLACE, prev/next motif |
| Conversation history | middle right, 749×310 | the musician's messages, the system's steps (verb-tagged, time-stamped), tool calls, gates |
| Input box | full width, 1200×64 | file drop, dictation, text, model picker, send |

The five verbs HEAR / WRITE / EDIT / BUILD / FETCH appear as glyphs on history rows and in the avatar window, not as a button row. The musician starts work by saying what they want; the verbs are how the system reports what it is doing.

## 5. Screens

1. **home** — the five regions above, mid-task (hum transcribed, bass line growing).
2. **gate** — a gated action (region replace) replaces the response box: header YOUR CALL, one-line ask, facts WHERE / OUT / IN / UNDO, answers NO / YES / YES, DON'T ASK AGAIN with a note on what "don't ask again" covers. The motif viewer highlights what would be replaced; the history row says "needs permission"; the input box is disabled until the gate is answered. Wording stays plain.
3. **live talk** — hands-free mode: listening state in the avatar window, spoken turns in the history labelled `you:` and `system:`, "the system answers out loud when you pause".
4. **setup** — bring your own brain: provider tiles with pixel logos grouped LABS (including Chinese labs) · FAST HOSTS & GATEWAYS · YOUR CLOUD (including a custom URL) · OFFLINE (this Mac); then sign in by OAuth or pasted key; then models per provider; then "what the system may reach" (consents). Groq and xAI are different providers.
5. **dress up** — the avatar: stage with prev/next looks and a NAME field; a wardrobe with a "START FROM A PHOTO" drop strip (take a selfie or pick a file; the system draws the avatar from it) above part rows LENGTH, TEXTURE (hair-type scale 1 / 2a–2c / 3a–3c / 4a–4c), HAIR colour, SKIN, EYES, TOP, BOTTOM, SHOES, EXTRA, each with prev/next and colour swatches; RANDOM / RESET / DONE. Dressing by prompt ("blue hair and white boots") works from the input box too.

## 6. Avatar and animations

The avatar is the musician's, built from a photo or part by part. The **animations are a fixed template**: every verb animation is the same for everyone and only the avatar sprite changes. Whatever the photo path generates must land on the shared sprite grid (24×32 cells today) with the same anchor points. The animations themselves are not designed yet and are not shown on the dress-up screen until they exist.

## 7. Audience and model

Mostly non-technical creatives. Every pi concept is simplified before it reaches the screen. Bring your own model: local or hosted, key or OAuth, chosen in setup and switchable from the input box.

## 8. Still to decide

- What state is always visible. Transport, selected track and active motif have no fixed home on the v2 frames; the top bar was dropped.
- Where the musician steers and where the system runs ahead, beyond the gate.
- Deferred polish: history timestamps, a lavender padlock for undoable gate kinds, the empty space under setup steps 1–2, the EDIT / BUILD / FETCH glyphs in context on the home screen.
