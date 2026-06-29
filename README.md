# /watch

**Give Claude the ability to watch any video.**

Claude Code (recommended — auto-updates via marketplace):
```
/plugin marketplace add bradautomates/claude-video
/plugin install watch@claude-video
```

Codex, Cursor, Copilot, Gemini CLI, or any of 50+ [Agent Skills](https://agentskills.io) hosts:
```bash
npx skills add bradautomates/claude-video -g
```
(`-g` installs globally for your user, available across all projects. Drop it to scope per-project.)

More install options (claude.ai web, manual) in the [Install](#install) section below.

Zero config to start — `yt-dlp` and `ffmpeg` install on first run via `brew` on macOS (Linux/Windows print exact commands). Captions cover most public videos for free. Whisper API key is only needed when a video has no captions.

---

Claude can read a webpage, run a script, browse a repo. What it can't do, out of the box, is *watch a video*. You paste a YouTube link and it has to either guess from the title or pull a transcript that's missing 90% of what's on screen.

With Claude Video `/watch` you can paste a URL or a local path, ask a question, and Claude fetches captions first, downloads only what it needs, extracts frames (scene-aware, or fast keyframes at `efficient` detail), pulls a timestamped transcript (free captions when available, Whisper API as fallback), and `Read`s every frame as an image. By the time it answers, it has *seen* the video and *heard* the audio.

```
/watch https://youtu.be/dQw4w9WgXcQ what happens at the 30 second mark?
```

## Why this exists

I built this because I'm constantly using video to keep up with content. If I see a YouTube video that's blowing up, I want to know how the creator structured the hook — what's on screen in the first 3 seconds, what they said, why it worked. That used to mean watching it myself with a notepad. Now I just paste the URL and ask.

The other half is summarization. Most YouTube videos don't deserve 20 minutes of my attention. I hand the URL to Claude, it pulls the transcript, and tells me what actually happened. If the visual matters, frames come along too. If it's a podcast or a talking head, transcript is enough.

Claude is great at reading and synthesizing — but until now, video was the one input I couldn't hand it. Pasting a YouTube link got you nothing useful. `/watch` closes that gap.

## What people actually use it for

**Analyze someone else's content.** `/watch https://youtu.be/<viral-video> what hook did they open with?` Claude looks at the first frames, reads the opening transcript, breaks down the structure. Same for ad creative, competitor launches, podcast intros, anything where the *how* matters as much as the *what*.

**Diagnose a bug from a video.** Someone sends you a screen recording of something broken. `/watch bug-repro.mov what's going wrong?` Claude watches the recording, finds the frame where the issue appears, describes what's on screen, often catches the cause without you ever opening the file.

**Summarize a video.** `/watch https://youtu.be/<long-thing> summarize this` does the obvious thing — pulls the structure, the key moments, what was actually said and shown. Faster than watching at 2x.

## How it works

1. **You paste a video and a question.** URL (anything yt-dlp supports — YouTube, Loom, TikTok, X, Instagram, plus a few hundred more) or a local path (`.mp4`, `.mov`, `.mkv`, `.webm`).
2. **`yt-dlp` checks captions first.** At `transcript` detail, captioned URLs return without downloading video. Otherwise, or when Whisper needs audio, it downloads only what the run needs.
3. **`ffmpeg` extracts frames at the chosen detail.** `efficient` decodes keyframes only (near-instant); `balanced`/`token-burner` prefer scene-change frames and fall back to the duration-aware uniform sampler when they under-produce. JPEGs are 512px wide by default and clamped to 1998px tall for Claude Read compatibility.
4. **The transcript comes from one of two places.** First try: `yt-dlp` pulls native captions (manual or auto-generated) from the source. Free, instant, accurate-ish. Fallback: extract a mono 16 kHz audio clip and ship it to Whisper — Groq's `whisper-large-v3` (preferred — cheaper and faster) or OpenAI's `whisper-1`.
5. **Frames + transcript are handed to Claude.** The script prints frame paths with `t=MM:SS` markers and the transcript with timestamps. Claude `Read`s each frame in parallel — JPEGs render directly as images in its context.
6. **Claude answers grounded in what's actually on screen and in the audio.** Not "based on the description" or "according to the title." It saw the frames. It heard the transcript. It answers the way someone who watched the video would.
7. **Cleanup.** The script prints a working directory at the end. If you're not asking follow-ups, Claude removes it.

## Frame budget — why it matters

Token cost is dominated by frames. Every frame is an image; image tokens add up fast. The script's auto-fps logic exists so you don't blow your context budget on a sparse scan of a 30-minute video that would have been better answered by a focused 30-second window.

| Duration | Default frame budget | What you get |
|----------|---------------------|--------------|
| ≤30 s | ~30 frames | Dense — basically every key moment |
| 30 s - 1 min | ~40 frames | Still dense |
| 1 - 3 min | ~60 frames | Comfortable |
| 3 - 10 min | ~80 frames | Sparse but workable |
| > 10 min | 100 frames | "Sparse scan" warning — re-run focused |

When the user names a moment ("around 2:30", "the last 30 seconds", "from 0:45 to 1:00"), pass `--start` / `--end`. Focused mode gets denser per-second budgets, capped at 2 fps. Far more useful than a sparse pass over the whole thing.

## Detail modes — measured

The `--detail` dial trades speed and token cost for visual fidelity. Numbers below are from a real run against a **49:08 (2948 s)** YouTube video (1280×720 source, English auto-captions, 1394 caption segments) — a long, mostly-static screen recording, which is the case that stresses the caps hardest. Frame-extraction times are measured against a pre-downloaded local copy so they reflect the *mode's* CPU cost, not network speed. The one-time video download for this clip was **~37 s** / 76 MB (shared by `efficient` / `balanced` / `token-burner`).

| Mode | Engine | Frames | Cap | Extraction time | Temporal coverage | Est. image tokens |
|------|--------|--------|-----|-----------------|-------------------|-------------------|
| `transcript` | none (captions) | 0 | — | **~4.5 s** (network-bound — one yt-dlp call, no video download) | full (text) | 0 (transcript ≈26.6k text tokens) |
| `efficient` | keyframe (`-skip_frame nokey`) | 50 | 50 | **~0.5 s** | 0:00 → 49:04 (full) | **~9.8k** |
| `balanced` | scene-change | 100 | 100 | **~20.9 s** | 0:00 → 48:38 (full) | **~19.7k** |
| `token-burner` | scene-change | 116 | uncapped | **~21.0 s** | 0:00 → 48:38 (full) | **~22.8k** |

Image-token estimate uses Anthropic's `(width × height) / 750` per image. At the default 512px width these 720p frames are 512×288, so **≈197 tokens/frame**; total image tokens ≈ `frames × 197`. Bumping `--resolution` to 1024 roughly **4×s** that. The transcript (~26.6k tokens here) is surfaced in *every* mode that has captions, so on the frame modes it adds to the image tokens above — on long videos the transcript, not the frames, is often the larger cost.

**Note on the `transcript` time.** It looks slower than `efficient` only because the two numbers measure different things: `transcript`'s ~4.5 s is a network round-trip to the source (its *only* step — no video download, no ffmpeg), while the frame modes' times are local CPU with the shared ~37 s download billed separately. End-to-end from a cold URL, `transcript` is the **cheapest** mode by far; `efficient` from a cold URL would be ~37 s of download + 0.5 s of decode.

What the numbers show:

- **One consistent sampling rule across every frame mode.** All three detect *all* candidates across the full range, then even-sample (first + last always kept) down to the cap via a shared `_even_sample` helper — `transcript` excepted. Keyframes (`efficient`) and scene-cuts (`balanced`/`token-burner`) differ only in the candidate *source* and the cap, never in how coverage is spread.
- **`efficient` is the speed tier** — ~0.5 s because it only reconstructs keyframes (P/B frames are skipped). For this clip it decoded **675 keyframes** and evenly sampled down to its 50-frame cap, spread across the whole 49 minutes.
- **Caps are enforced and coverage spans the full clip.** `efficient` (675 → 50) and `balanced` (116 → 100) both sample first→last, so the last frame lands at 48:38–49:04, not partway through. Verified on the full video and on focused ranges (`--start`/`--end` of 30 s → 10 frames, 3 min → 37 frames). The even-sample step (`len(indices) == cap`) cannot return more than the cap. *(This addresses the "sometimes returns too many / drops the tail" concern: the `N selected from 675 candidates` line shows the pre-sample candidate count, not what gets surfaced — only the sampled frames are written and Read.)*
- **`balanced` now full-decodes like `token-burner`** (~21 s vs `efficient`'s ~0.5 s). Detecting every scene cut requires decoding the whole video; the old `-frames:v` early-exit was ~3× faster but kept only the *first* 100 cuts and dropped the tail of long videos — so it was removed in favor of even coverage.
- **`token-burner` only diverges from `balanced` past the cap.** This recording had **116** cuts over 49 min, so `balanced` sampled 100 of them and `token-burner` kept all 116 — both spanning the full video. On a high-motion video with hundreds of cuts, `token-burner` keeps everything (and the >250-frame token warning kicks in) while `balanced` thins to 100.
- **`efficient` can return *more* frames than `balanced`** on low-motion footage (50 keyframes vs. few scene cuts) — the tiers differ by extraction *method* and cap, not by a guaranteed frame-count ordering. "Efficient" means near-instant extraction, not always fewer frames.

Bottom line on timing: every mode finished its own work in **under 22 s** (plus the shared ~37 s download for the frame modes). `efficient` is ~40× faster than the scene modes here because the scene detector decodes every frame of the full 49 minutes, while `efficient` only reconstructs keyframes.

## Install

| Surface | Install |
|---------|---------|
| **Claude Code** | `/plugin marketplace add bradautomates/claude-video` then `/plugin install watch@claude-video` |
| **Codex, Cursor, Copilot, Gemini CLI, +50 more** | `npx skills add bradautomates/claude-video -g` |
| **claude.ai** (web) | [Download `watch.skill`](https://github.com/bradautomates/claude-video/releases/latest) → Settings → Capabilities → Skills → `+` |
| **Manual / dev** | `git clone` then symlink `skills/watch` into your host's skills dir (see below) |

### Claude Code

```
/plugin marketplace add bradautomates/claude-video
/plugin install watch@claude-video
```

Update later with `/plugin update watch@claude-video`.

### Codex, Cursor, Copilot, Gemini CLI, and 50+ other hosts

The [Agent Skills](https://agentskills.io) CLI installs the skill into whatever agents it detects:

```bash
npx skills add bradautomates/claude-video -g
```

`-g` installs globally for your user (`~/.codex/skills`, `~/.cursor/skills`, etc.); drop it to install into the current project instead. Useful flags:

- `-a, --agent <names…>` — target specific hosts, e.g. `-a codex -a cursor`
- `-l, --list` — list the skills in this repo without installing
- `--copy` — copy files instead of symlinking (for filesystems without symlink support)

The CLI discovers the skill from `skills/watch/SKILL.md` and copies the whole folder — `SKILL.md` plus its `scripts/` runtime — as a self-contained unit. `SKILL.md` resolves its own scripts relative to wherever it was installed, so it works the same on every host.

Update later with `npx skills update watch -g`.

### claude.ai (web)

1. [Download `watch.skill`](https://github.com/bradautomates/claude-video/releases/latest) from the latest release.
2. Go to Settings → Capabilities → Skills.
3. Click `+` and drop the file in.

Enable "Code execution and file creation" under Capabilities first — the skill shells out to `ffmpeg` and `yt-dlp`, so it won't run without it.

### Manual (developer)

Clone the repo and symlink the self-contained skill folder into your host's skills directory — the symlink keeps the install in sync with your working tree as you edit:

```bash
git clone https://github.com/bradautomates/claude-video.git
ln -s "$(pwd)/claude-video/skills/watch" ~/.claude/skills/watch   # or ~/.codex/skills/watch
```

For claude.ai, build the `.skill` bundle from source: `bash skills/watch/scripts/build-skill.sh` produces `dist/watch.skill`.

## First run

On the first `/watch` call, the skill runs `scripts/setup.py --check`. If `ffmpeg` / `yt-dlp` aren't on your PATH, or no Whisper API key is set, it walks you through fixing it:

- **macOS** — auto-runs `brew install ffmpeg yt-dlp`.
- **Linux** — prints the exact `apt` / `dnf` / `pipx` commands.
- **Windows** — prints the `winget` / `pip` commands.
- **API key** — scaffolds `~/.config/watch/.env` (mode `0600`) with commented placeholders for `GROQ_API_KEY` (preferred) and `OPENAI_API_KEY`.

After setup, preflight is silent and `/watch` just works. The check is a sub-100ms lookup, so it doesn't slow you down on subsequent runs.

## Bring your own keys

Captions cover the majority of public videos for free. The Whisper fallback only kicks in when a video genuinely has no caption track — typically local files, TikToks, some Vimeos, and the occasional caption-less YouTube upload.

| Capability | What you need | Cost |
|------------|---------------|------|
| Download + native captions | `yt-dlp` + `ffmpeg` | Free |
| Whisper fallback (preferred) | [Groq API key](https://console.groq.com/keys) — `whisper-large-v3` | Cheap, fast |
| Whisper fallback (alt) | [OpenAI API key](https://platform.openai.com/api-keys) — `whisper-1` | Standard pricing |
| Disable Whisper entirely | `--no-whisper` | Free, frames-only when no captions |

## Usage

```
/watch https://youtu.be/dQw4w9WgXcQ what happens at the 30 second mark?
/watch https://www.tiktok.com/@user/video/123 summarize this
/watch ~/Movies/screen-recording.mp4 when does the UI break?
/watch https://vimeo.com/123 what tools does she mention?
```

Focused on a specific section — denser frame budget, lower token cost:
```
/watch https://youtu.be/abc --start 2:15 --end 2:45
/watch video.mp4 --start 50 --end 60
/watch "$URL" --start 1:12:00            # from 1h12m to end
```

Other knobs (passed to `scripts/watch.py`):

- `--detail transcript|efficient|balanced|token-burner` — fidelity/speed dial. `transcript` skips frames (transcript only); `efficient` uses fast keyframes (cap 50); `balanced` uses scene-aware frames (cap 100); `token-burner` is scene-aware and uncapped.
- `--timestamps T1,T2,…` — grab a frame at each absolute timestamp (`SS`/`MM:SS`/`HH:MM:SS`). Claude reads the transcript first, then targets the moments the presenter flags ("look here", "as you can see"). Added on top of the detail frames (reserved against the cap); out-of-window cues are dropped in focus mode; with `--detail transcript` these become the only frames.
- `--max-frames N` — lower the frame cap for a tighter token budget.
- `--resolution W` — bump frame width to 1024 px when Claude needs to read on-screen text (slides, terminals, code).
- `--fps F` — override the auto-fps calculation (still capped at 2 fps).
- `--whisper groq|openai` — force a specific Whisper backend.
- `--no-whisper` — disable transcription entirely; frames only.
- `--out-dir DIR` — keep working files somewhere specific (default: auto-generated tmp dir).

## Limits

- **Best accuracy: under 10 minutes.** Past that the script prints a "sparse scan" warning — re-run focused on the part you actually care about with `--start`/`--end`.
- **Detail is one dial.** Defaults are balanced: scene-aware frames, 2 fps max, 100-frame cap. Use `--detail efficient` for a fast 50-frame keyframe pass, or `--detail token-burner` for uncapped scene candidates. Set `WATCH_DETAIL` in `~/.config/watch/.env` to change the default.
- **Whisper upload limit: 25 MB.** At mono 16 kHz that's about 50 minutes of audio. Longer videos need either captions or `--start`/`--end` to a smaller window.

## Structure

```
.
├── skills/watch/                 # self-contained skill — copied as a unit by every installer
│   ├── SKILL.md                  # skill contract — the source of truth across all surfaces
│   └── scripts/
│       ├── watch.py              # entry point — orchestrates download → frames → transcript
│       ├── download.py           # yt-dlp wrapper
│       ├── frames.py             # ffmpeg frame extraction + auto-fps logic
│       ├── transcribe.py         # VTT parsing + dedupe + Whisper orchestration
│       ├── whisper.py            # Groq / OpenAI clients (pure stdlib)
│       ├── config.py             # shared config (~/.config/watch/.env)
│       ├── setup.py              # preflight + installer
│       └── build-skill.sh        # build dist/watch.skill for claude.ai upload (dev-only)
├── hooks/                        # SessionStart status hook (Claude Code only)
├── .claude-plugin/               # plugin.json + marketplace.json (Claude Code)
├── .codex-plugin/                # plugin.json — Codex/agents manifest ("skills": "./skills/")
├── .agents/plugins/              # marketplace.json — Agent Skills marketplace listing
├── AGENTS.md → CLAUDE.md         # generic-agent entry point
├── tests/                        # pytest suite (ffmpeg-synthesized clips, no network)
└── .github/workflows/            # release.yml — auto-builds watch.skill on tag push
```

## Develop

```bash
# Run the test suite (stdlib + pytest; ffmpeg required for frame tests):
python3 -m pytest -q

# Build the claude.ai upload bundle:
bash skills/watch/scripts/build-skill.sh      # → dist/watch.skill
```

Releasing: tag `vX.Y.Z`, push the tag. The workflow builds `dist/watch.skill` and attaches it to the GitHub release. Keep the version in sync across `skills/watch/SKILL.md`, `.claude-plugin/plugin.json`, and `.codex-plugin/plugin.json`.

See [CHANGELOG.md](CHANGELOG.md) for version history.

## Open source

MIT license.

Built on `yt-dlp`, `ffmpeg`, and Claude's multimodal `Read` tool. Whisper transcription via [Groq](https://groq.com) or [OpenAI](https://openai.com).

## Star History

<a href="https://star-history.com/#bradautomates/claude-video&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=bradautomates/claude-video&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=bradautomates/claude-video&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=bradautomates/claude-video&type=Date" />
  </picture>
</a>

---

[github.com/bradautomates/claude-video](https://github.com/bradautomates/claude-video) · [LICENSE](LICENSE)
