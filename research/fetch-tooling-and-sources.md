# Research: FETCH tooling and sources

Resolves issue #18. Researched 2026-10-10 against official docs, repos and API references, plus checks on this laptop (macOS 26.7.1, Intel x86_64; yt-dlp 2026.03.03 installed via pip; no ffmpeg, no deno; Homebrew at /usr/local; miniconda3 present; Splice.app 5.4.4 installed).

Scope, per the ticket: the producer searches, the agent proposes candidates, downloads happen only on confirmation (a Gated action). This note does not editorialise about copyright; it records which licensing fields each source exposes so provenance can carry them.

## TL;DR / Recommendation

| Source | Search | Fetch | Credentials | Verdict |
|---|---|---|---|---|
| YouTube | `yt-dlp "ytsearchN:…" -j` (no key) | `yt-dlp -f bestaudio -x` | none (optional browser cookies) | **Primary.** Needs ffmpeg + deno installed first. |
| YouTube Data API v3 | `search.list` | n/a (no media endpoint) | Google API key | Optional metadata-only fallback; 100 searches/day. |
| Invidious | `/api/v1/search` | `/api/v1/videos/:id` | none | **Skip.** 1 of 7 public HTTPS instances has the API on; self-host only. |
| Reddit | OAuth Data API (`/r/<sub>/search.json`) | links in posts → yt-dlp/direct | Reddit script-app `client_id`+`secret` | **Secondary.** Unauthenticated `.json` is redirected/403'd from this machine. |
| Freesound | `GET /apiv2/search/` | previews (token) / original (OAuth2) | API key; OAuth2 for originals | **Primary** for CC one-shots/field recordings; richest licence metadata. |
| Splice | local `~/Splice` + `sounds.db`; official MCP server (beta) for catalogue search | MCP download (paid tier) or already-downloaded packs | Splice login (OAuth via browser) | **Local-first.** Index what's on disk; MCP is the only sanctioned remote path. |
| Looperman | none | none | n/a | **Do not automate.** Terms prohibit any programmatic download. Link-out only. |
| archive.org | `advancedsearch.php` / scrape API | `https://archive.org/download/{id}/{file}` or `ia` CLI | none for public items | **Primary** for public-domain / CC archives. |

**Stack:** yt-dlp (pip, `yt-dlp[default]`) + ffmpeg + deno for anything URL-shaped; thin HTTPS clients (fetch) for Freesound, Reddit OAuth and archive.org; a SQLite/filesystem indexer for `~/Splice`. All wrapped as one pi CLI tool (`fetch search …` / `fetch get …`) with the download step gated.

**Credentials** live in pi's agent directory, alongside pi's own `auth.json`: `~/.pi/agent/` (overridable with `PI_CODING_AGENT_DIR`), e.g. `~/.pi/agent/sharpfive/fetch-credentials.json` (mode 0600), with env-var overrides (`FREESOUND_API_KEY`, `REDDIT_CLIENT_ID`/`REDDIT_CLIENT_SECRET`, `YOUTUBE_API_KEY`) for CI and for the mama box. Never in the repo and never in `.pi/` (project config is committed).

## 1. yt-dlp + ffmpeg (YouTube and any URL)

### What is installed and what is missing

- `yt-dlp 2026.03.03` is present (pip). The README lists **ffmpeg/ffprobe** and **yt-dlp-ejs + a JavaScript runtime** as "strongly recommended"; ffmpeg is "required for merging separate video and audio files, as well as for various post-processing tasks", and yt-dlp-ejs is "required for full YouTube support" ([README, Dependencies](https://github.com/yt-dlp/yt-dlp#dependencies)).
- Verified on this machine: `yt-dlp -F <youtube url>` warns `No supported JavaScript runtime could be found. Only deno is enabled by default` and lists **only format 18 (640x360 mp4 with mp4a audio)** — no audio-only streams at all. Without deno, `-f bestaudio` has nothing to pick from and `-x` has no ffmpeg to transcode with.
- The EJS wiki: yt-dlp "needs to solve JavaScript challenges presented by YouTube using an external JavaScript runtime"; Deno ≥ 2.3.0 is recommended and enabled by default, Node ≥ 22 works with `--js-runtimes node`, QuickJS and (deprecated) Bun also supported. Pip installs should use `pip install -U "yt-dlp[default]"` so the yt-dlp-ejs package version matches ([wiki/EJS](https://github.com/yt-dlp/yt-dlp/wiki/EJS)). Node v25 is on this laptop, so `--js-runtimes node` is a zero-install fallback, but deno is the supported default.

### Getting ffmpeg onto an Intel Mac on macOS 26

- Homebrew's `ffmpeg` formula is 9.0.2 but ships bottles only for Apple Silicon; `brew info --json ffmpeg` here returns an empty bottle list. Intel macOS is **Tier 3**: "Homebrew has stopped building new bottles for Intel systems", "updated formulae may build from source", Intel support removed "in or after September 2027" ([docs.brew.sh/Support-Tiers](https://docs.brew.sh/Support-Tiers), [Installation](https://docs.brew.sh/Installation)). A source build of ffmpeg with Command Line Tools only is possible but slow and fragile.
- yt-dlp's own FFmpeg-Builds: "There are currently no MacOS builds" ([yt-dlp/FFmpeg-Builds README](https://github.com/yt-dlp/FFmpeg-Builds)).
- **conda-forge `ffmpeg` 9.0.2 has an `osx-64` build** (anaconda.org package metadata lists `osx-64` and `osx-arm64`); miniconda3 is already installed here, so `conda install -c conda-forge ffmpeg` is the cleanest Intel path, then point yt-dlp at it with `--ffmpeg-location` (README: "either the path to the binary or its containing directory").
- On mama (M2 Pro) `brew install ffmpeg` is bottled and trivial; if FETCH ever runs remotely that side is easy.

### Audio-only extraction and format choice

From the README / `yt-dlp --help` (verified locally):

- `-f bestaudio` selects the best audio-only stream. yt-dlp's default codec preference for audio is `flac/alac > wav/aiff > opus > vorbis > aac > mp4a > mp3 …` ([Sorting Formats](https://github.com/yt-dlp/yt-dlp#sorting-formats)). YouTube serves Opus (webm) and AAC (m4a); Opus at ~128–160 kbps is usually the top pick.
- `-x, --extract-audio` "Convert video files to audio-only files (requires ffmpeg and ffprobe)". `--audio-format` accepts `best (default), aac, alac, flac, m4a, mp3, opus, vorbis, wav`. `--audio-quality` 0 (best) – 10 for VBR.
- **Recommendation for Seedlings:** `-f bestaudio -x --audio-format wav` only when Logic needs a drop-in file; otherwise keep `--audio-format best` (no re-encode, container-strip only) and convert to WAV/AIFF at import time. Decoding Opus→WAV is lossless with respect to the stream; nothing is gained by asking YouTube for "lossless". Record the source codec/bitrate (`acodec`, `abr`, `asr`) in provenance so nobody mistakes a 128 kbps Opus for a studio stem.
- `--download-sections "*1:23-1:41"` cuts a time range (needs ffmpeg); useful when the producer points at a moment in a long video.
- `--no-overwrites`, `--download-archive FILE` ("Download only videos not listed in the archive file. Record the IDs of all downloaded videos in it") give idempotent re-runs.

### Search without a browser

- `ytsearchN:<query>` is a first-class extractor ("youtube:search … `ytsearch:` prefix"; also `youtube:search_url` for YouTube search URLs with sort/filter params) ([supportedsites.md](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md)). `yt-dlp -j "ytsearch10:amen break"` returns one JSON object per result **without downloading** (`-j, --dump-json`: "Quiet, but print JSON information for each video. Simulate unless --no-simulate is used"). Verified locally: a `ytsearch1:` call returned full metadata in a few seconds with no key.
- `--flat-playlist` makes a search much cheaper (skips per-video extraction) when you only need id/title/duration for the proposal list.
- SoundCloud has the same shape: `scsearch:` prefix (`soundcloud:search`). Bandcamp, archive.org, Freesound and Reddit also have extractors, so one `fetch get <url>` path can cover most pasted links.

### Metadata to keep as provenance

Fields documented in the README's OUTPUT TEMPLATE section and verified present in the local `-j` output: `id`, `title`, `webpage_url` ("A URL to the video webpage which, if given to yt-dlp, should yield the same result again"), `original_url`, `extractor`/`extractor_key`, `uploader`, `uploader_id`, `uploader_url`, `channel`, `channel_id`, `channel_url`, `upload_date` (YYYYMMDD UTC), `timestamp`, `release_date`, `duration`, `license` ("License name the video is licensed under" — `null` on the test video; YouTube only populates it for Creative Commons uploads), `categories`, `tags`, `description`, `track`/`artist`/`album` (YouTube Music), `availability`, `epoch` (when extraction ran), `_version` (yt-dlp version/commit) plus the chosen format's `format_id`, `ext`, `acodec`, `abr`, `asr`, `audio_channels`, `filesize`.

`--write-info-json` dumps all of this beside the file (the README warns it "may contain personal information" — i.e. cookies-derived data; `--clean-info-json` is the default). Easiest provenance path: always write the info.json and copy the subset above into the Seedling record.

### Credentials

None required. `--cookies-from-browser BROWSER` or `--cookies FILE` exists for age-gated/members content; treat it as opt-in and never store the cookie jar in the repo.

### YouTube Data API v3 (optional)

Quota: "a default quota allocation of 100 `search.list` calls, 100 `videos.insert` calls, and 10,000 units per day combined for all other endpoints"; `videos.list` costs 1 unit ([determine_quota_cost](https://developers.google.com/youtube/v3/determine_quota_cost)). The Data API returns metadata only — there is no media endpoint, and the API ToS §16.3 states "no rights or licenses are granted to reproduce or distribute audiovisual content" ([API Services ToS](https://developers.google.com/youtube/terms/api-services-terms-of-service)). `videos.list` does return `status.license` (`youtube` | `creativeCommon`) and `contentDetails.licensedContent`, which is a cleaner licence signal than yt-dlp's. Needs a Google Cloud project + API key. Given 100 searches/day, use it only for licence enrichment, not as the search path.

### Invidious

Has a documented REST API: `GET /api/v1/search?q=&type=video&sort=&date=&duration=&region=` and `/api/v1/videos/:id` exposing `adaptiveFormats` with `itag`, `type`, `bitrate`, `url`, `audioQuality`, `audioSampleRate`, `audioChannels` ([docs.invidious.io/api](https://docs.invidious.io/api/)). The project "does not use official YouTube APIs" and its FAQ attributes playback failures to "Youtube is likely blocking the video stream" ([FAQ](https://docs.invidious.io/faq/)). `https://api.invidious.io/instances.json` fetched today lists **7 HTTPS instances, 1 with the API enabled**. Not a dependable backend; only worth it self-hosted, and yt-dlp already covers the need.

## 2. Reddit

### Official Data API

- Reddit's API rules (the canonical GitHub wiki): "Clients must authenticate with OAuth2", "Clients connecting via OAuth2 may make up to 60 requests per minute", monitor `X-Ratelimit-Used/Remaining/Reset`, User-Agent must be "unique and descriptive" in the form `<platform>:<app ID>:<version string> (by /u/<reddit username>)`, "NEVER lie about your user-agent" ([reddit-archive/reddit wiki/API](https://github.com/reddit-archive/reddit/wiki/API)).
- Reddit's 2023 Data API announcement raised the free tier to "100 queries per minute per OAuth client id … and 10 queries per minute if you are not using OAuth", with paid access at $0.24 per 1,000 calls for apps above that; non-commercial scripts stay free. The canonical pages — the [Reddit Data API Wiki](https://support.reddithelp.com/hc/en-us/articles/16160319875092-Reddit-Data-API-Wiki) and [Data API Terms](https://www.redditinc.com/policies/data-api-terms) — could not be fetched from this session (reddit.com and redditinc.com block this crawler), so those two numbers rest on Reddit's own r/redditdev posts as mirrored; confirm against the wiki before relying on them.
- Registration: a "script" app at reddit.com/prefs/apps yields `client_id` and `client_secret`; PRAW's docs describe the same prerequisites and the User-Agent format ([PRAW quick start](https://praw.readthedocs.io/en/stable/getting_started/quick_start.html)). Password-grant with a personal account works for a single-user CLI; no account creation was done for this research.

### old.reddit `.json` endpoints

Tested today with a descriptive User-Agent: `https://old.reddit.com/r/samples/about.json` → **302 to `/login/?reason=lor2`**; `https://www.reddit.com/r/samples/about.json` → **403**. Unauthenticated JSON is not usable from this network/UA. yt-dlp's `Reddit` extractor uses the same `.json` pages and will hit the same wall for post discovery; it remains useful for v.redd.it media once a post URL is known. Build on OAuth.

### Subreddits to index

The ticket's candidates — r/samples, r/Drumkits, r/isolatedvocals — could not be verified from this session for the reason above (every subreddit metadata request was redirected). Treat them as the seed list, verify `GET /r/<name>/about` via OAuth in the first prototype, and let the producer add subs in config. Reddit posts are mostly link posts, so the Reddit stage yields candidate URLs (Google Drive, Mega, YouTube, SoundCloud, direct .zip/.wav); the fetch stage then dispatches by host (yt-dlp for anything it supports, plain HTTPS for direct files, nothing for Drive/Mega without their own clients).

### Provenance exposed

Per post: `id`, `permalink`, `subreddit`, `author`, `title`, `url` (link target), `created_utc`, `link_flair_text`, `selftext`, `score`. Reddit exposes **no licence field**; the only licensing signal is whatever the poster wrote, so record `license: null` with `license_note` carrying flair/title text verbatim.

## 3. Freesound

- **Auth:** request a key at `https://freesound.org/apiv2/apply` (one per application). Token auth: `Authorization: Token YOUR_API_KEY` header (or `?token=`). OAuth2 authorization-code flow for user-scoped actions: authorize at `/apiv2/oauth2/authorize/`, exchange at `/apiv2/oauth2/access_token/`, use `Authorization: Bearer`; access tokens last 24 h, refresh tokens rotate, one live token per app/user ([authentication docs](https://freesound.org/docs/api/authentication.html)).
- **Search:** `GET /apiv2/search/` with `query` (+/- terms), `filter` (Solr syntax, e.g. `filter=duration:[0 TO 10] license:"Creative Commons 0"`), `sort` (`score`, `downloads_desc`, `created_desc`…), `fields` (default `id,name,tags,username,license`), `page_size` ≤ 150 ([resources docs](https://freesound.org/docs/api/resources_apiv2.html)). Content-based descriptors (tempo, key, loudness) are requestable through the `descriptors`/analysis resources on the same page.
- **Fetch:** `previews` on each Sound object gives direct `preview-hq-mp3` / `preview-hq-ogg` / `preview-lq-*` URLs usable with token auth — enough for auditioning a candidate before the gate. The original file is `GET /apiv2/sounds/<id>/download/` and **requires OAuth2** ("in its original format/quality").
- **Throttling:** 60 req/min and 2,000 req/day standard; 30 req/min and 500/day for original-quality downloads and write actions; 429 with a `detail` naming the exceeded limit; higher limits by contacting Freesound ([overview, Throttling](https://freesound.org/docs/api/overview.html)). API terms: free for non-commercial use, credit Freesound and the uploader per each sound's licence, do not replicate Freesound ([terms of use](https://freesound.org/docs/api/terms_of_use.html)).
- **Provenance fields exposed:** `id`, `url`, `name`, `tags`, `description`, `license` (filter values documented as `Attribution`, `Attribution NonCommercial`, `Creative Commons 0`; store whatever string the Sound object returns verbatim), `username`, `pack`, `type`, `duration`, `samplerate`, `bitdepth`, `channels`, `filesize`, `md5`, `created`. This is the richest licence metadata of any source here; keep `license` and `username` verbatim.
- Official client: [MTG/freesound-python](https://github.com/MTG/freesound-python) (MIT, last pushed 2025-12). A plain `fetch` wrapper in Node is small enough that the dependency is optional.

## 4. Splice

- **No public API.** Splice publishes no REST API, SDK or partner programme; the only developer-facing surface is the **Splice MCP Server (beta, article dated 2026-04-06)** at `https://mcp.splice.com/mcp`, streamable HTTP, browser login on first use, capabilities: search sounds from a description, build/edit/share stacks, download samples; "Searching and building stacks work on free accounts", downloads need "a Sounds+, Creator, or Creator+ subscription"; you choose the save location per download ([support article 14442749](https://support.splice.com/en/articles/14442749-getting-started-with-the-splice-mcp-server-beta)).
  - Note for the map: current pi docs describe first-class MCP support (`pi mcp add docs --url https://example.com/mcp`, user config `~/.pi/agent/mcp.json`, project `.pi/mcp.json`) ([pi docs/mcp.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/mcp.md)). The map's "pi is MCP-less by design" is out of date; the Splice server could be attached directly rather than wrapped in a CLI. Whether to is a map decision, not this ticket's.
- **Local folder convention (official):** downloaded samples go to `Macintosh HD/Users/[your username]/Splice`, "organized by pack"; if moved, the new location must be set in app Preferences; MIDI goes to `~/Downloads`; presets go to plugin-specific folders (`~/Library/Application Support/Splice/<Astra|Beatmaker>/Presets/From Splice`, Serum/Sylenth/Massive paths) ([where is my Splice folder](https://support.splice.com/en/articles/8652662-where-is-my-splice-folder), [where do downloads go](https://support.splice.com/en/articles/8652631-where-do-my-downloaded-samples-presets-midi-files-go)). The Splice Sounds plugin writes to `~/Library/Splice/Plug-in/samples` and that path is not configurable (support search result; not re-verified).
- **Observed on this machine:** `~/Splice/` contains `sounds/`, `presets/` (both empty — nothing has been downloaded) and a `.splice` marker file holding the numeric Splice user id. The desktop app keeps its state under `~/Library/Application Support/com.splice.Splice/`: `appState.json` (app version 5.4.4, user profile), `port.conf` (`127.0.0.1:<port>` — the local helper the DAW plugin talks to), `logs/`, and **`users/default/<username>/sounds.db`**, a SQLite catalogue of downloaded sounds. Its schema was not inspected here (user-profile directory; also holds `settings.json` which may contain tokens). The community tool [ebai101/splorganizer](https://github.com/ebai101/splorganizer) reads this same `sounds.db` (obtained via the app's "Download logs" export) to reorganise samples by type, which confirms it carries per-sample tags/metadata.
- **Recommended path:** FETCH's Splice limb is a **local indexer**: walk `~/Splice/sounds/<pack>/…` (or the path from app Preferences) and, read-only, join against `sounds.db` for tags/bpm/key. Provenance for a Splice Seedling: `source: splice`, `path`, `pack`, `filename`, plus whatever `sounds.db` row fields exist (sample id, pack id/name, tags, bpm, key). Licence: Splice's own terms govern (the API exposes no per-sample licence field); record `license: "splice-terms"` and the user id from `.splice`. Remote search is the MCP server or nothing.

## 5. Looperman

Terms of use: "We strictly prohibit unauthorised access or downloading of data using any computer program", no "robot, spider, rover, scraper, or any other data mining technology", and content may not be used "for the training or improvement of any algorithm". Loops: registered users get a "non-exclusive, royalty free right to copy, reproduce, edit, adapt, modify, remix" loops in new original recordings; acapellas default to "personal, non-commercial use" unless the uploader specifies otherwise, with per-upload credit requirements ([looperman.com/help/terms](https://www.looperman.com/help/terms)). No API. **FETCH must not search or download from Looperman programmatically**; at most, if the producer pastes a Looperman URL they downloaded by hand, record it as provenance (`source: looperman`, `url`, `license: per-upload, see page`).

## 6. archive.org

- **Search:** `https://archive.org/advancedsearch.php?q=<lucene>&fl[]=identifier&fl[]=title&fl[]=licenseurl&rows=50&page=1&output=json` (paged results capped at 10,000) and the cursor-based Scrape API `https://archive.org/services/search/v1/scrape?q=&fields=&count=&cursor=` (`count` ≥ 100) ([aboutsearch](https://archive.org/help/aboutsearch.htm)). Queries use field syntax such as `mediatype:audio AND subject:"drum breaks"`.
- **Metadata:** `GET https://archive.org/metadata/{identifier}` returns `metadata`, `files` (each with `name`, `source`, `format`, `mtime`, `size`, `md5`, `crc32`, `sha1`), `server`, `dir`, `item_last_updated` ([Metadata Read API](https://archive.org/developers/md-read.html)). Plain GET; no credentials for public items.
- **Fetch:** `https://archive.org/download/{identifier}/{filename}` (standard download URL; the `ia` CLI wraps it: `ia search`, `ia metadata`, `ia download <id> --glob="*.wav"`; `ia configure` is tied to upload and private items in the docs) ([ia CLI](https://archive.org/developers/internetarchive/cli.html)). yt-dlp also has an `archive.org` extractor for pasted item URLs.
- **Provenance fields exposed:** `identifier`, `mediatype`, `collection`, `title`, `creator`, `date`, `description`, `subject`, `source`, `licenseurl` ("URL of the selected license … should point to a recognized license, like Creative Commons or GNU"), `rights` ("Rights statement" for non-URL cases), `addeddate`; and per-file `md5`/`sha1`/`size`/`format` ([metadata schema](https://archive.org/developers/metadata-schema/index.html)). Filter searches with `licenseurl:*` to surface items that declare a licence.

## 7. Credentials: what is needed and where it lives

| Source | Needs | Form |
|---|---|---|
| YouTube via yt-dlp | nothing | optional `--cookies-from-browser` |
| YouTube Data API | API key | `YOUTUBE_API_KEY` |
| Reddit | script app id + secret (+ username/password for password grant, or a stored refresh token) | `REDDIT_CLIENT_ID`, `REDDIT_CLIENT_SECRET`, user-agent string |
| Freesound | API key; OAuth2 client secret + refresh token for original downloads | `FREESOUND_API_KEY`, `FREESOUND_CLIENT_SECRET`, token cache |
| Splice | app login (browser OAuth) for the MCP server; none for local index | handled by the MCP client |
| archive.org | none for public read | optional `ia configure` (`~/.config/internetarchive/ia.ini`) |

Where: pi keeps user configuration in the agent directory (`~/.pi/agent`, overridable with `PI_CODING_AGENT_DIR`), with `auth.json` for "Saved API keys and OAuth credentials", `extensions/`, `skills/`, and user-level `mcp.json`; project config is `.pi/` under the repo and loads only after project trust. Pi resolves provider credentials as `--api-key` → `auth.json` → `models.json` → environment variables, and the docs say to "Keep `auth.json` and any credential commands private" ([configuration.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/configuration.md), [models.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/models.md), [environment-variables.md](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/environment-variables.md)). Mirror that: the fetch tool reads `~/.pi/agent/sharpfive/fetch-credentials.json` (0600, `.gitignore`d by location), env vars override, nothing credential-shaped in `.pi/` or the repo. Pi's `mcp.json` supports `${ENV_VAR}` substitution in headers, so the Splice server can be declared without inlining a token.

## 8. Provenance every fetched Seedling must carry

Common envelope (write it as `<file>.seedling.json` beside the audio, and keep the raw source response — e.g. yt-dlp's `.info.json` — alongside):

```
source            youtube | soundcloud | reddit | freesound | splice | archive | looperman | local | url
source_id         video id / sound id / post id / archive identifier / splice sample id
source_url        canonical page URL (yt-dlp webpage_url, Freesound url, Reddit permalink, archive details URL)
media_url         the exact stream/file URL fetched, if different
title
creator           uploader / username / creator / channel  (+ creator_id, creator_url where exposed)
published_at      upload_date / created / date  (ISO 8601 UTC)
license           verbatim licence value from the source (yt-dlp license, Freesound license, archive licenseurl + rights, Splice "splice-terms", Reddit null)
license_note      free text the source attaches (Reddit flair/title, archive rights, Freesound description)
duration_s, codec, bitrate_kbps, samplerate, channels, filesize   of the fetched media as received
sha256            of the fetched file (plus source-provided md5/sha1 when offered — Freesound md5, archive md5/sha1)
fetched_at        ISO 8601
fetched_by        tool + version (yt-dlp 2026.03.03 / ffmpeg x.y / fetch-cli commit)
query             the producer's search text and the candidate rank, so "why this one" is answerable
confirmed_by      the gate record: who approved, when
transforms        [] of post-fetch steps (section cut, transcode opus→wav, normalise) with parameters
local_path        where it landed in the project
```

Source-specific extras ride in a `source_meta` object (yt-dlp `tags`/`categories`/`availability`; Freesound `tags`/`pack`/`samplerate`/`bitdepth`; Reddit `subreddit`/`score`/`flair`; archive `collection`/`subject`/`mediatype`; Splice `pack`/`bpm`/`key`/`tags`). The WRITE verb's traceability rule (every WRITE traces to a Seedling) hangs off `source_url` + `sha256`; everything else is there so the producer can answer "where did this come from and under what terms" without re-opening the source.

## 9. Open items for the FETCH prototype

1. Install `deno` and a conda-forge `ffmpeg`, re-run `yt-dlp -F` and confirm audio-only formats appear on Intel/macOS 26.
2. Register a Reddit script app and verify the three seed subreddits and the OAuth search endpoint; confirm the 100 QPM figure against the Data API Wiki.
3. Apply for a Freesound key; exercise `search` → `previews` → gated `download` (OAuth2) end to end.
4. Inspect `~/Library/Application Support/com.splice.Splice/users/default/<user>/sounds.db` read-only and record its schema (not done here).
5. Decide at the map level whether the Splice MCP server attaches via pi's native MCP support or stays out of scope.
