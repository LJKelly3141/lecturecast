# Kokoro Voice Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `voice: provider: kokoro`, a free voice that runs on the instructor's Mac with no account and no internet after the first run, as an option next to Edge.

**Architecture:** A small Python runner shipped in `inst/python/` loads Kokoro once and answers one request per line on stdin. R starts it through `uv run` at pinned versions the first time a build needs a voice, keeps it for the rest of the build, and stops it when the build ends. Each request writes a WAV; R converts it to the MP3 the voice cache expects and turns Kokoro's word timestamps into caption timing.

**Tech Stack:** R (processx, existing `lc_` helpers), Python 3.12 via uv, `kokoro==0.9.4`, `soundfile==0.14.0`, FFmpeg.

**Spec:** this plan, plus Logan's choices of 2026-11-08: Kokoro over Chatterbox; American voices liked (af_heart, af_bella, am_michael, am_fenrir), British not; Edge stays as an option.

## Facts checked 2026-11-08

- Licence: Kokoro-82M model card `license: apache-2.0`; README "With Apache-licensed weights, Kokoro can be deployed anywhere from production environments to personal projects."
- Installed and run on Logan's Mac: kokoro 0.9.4, misaki 0.9.4, torch 2.15.0, soundfile 0.14.0, Python 3.12, through `uv run --with`.
- Loading the model takes about 13 s per process; voicing one sentence about 0.9 s. Hence one long-lived process per build, not one per segment.
- `KPipeline(lang_code=..., repo_id="hexgrad/Kokoro-82M")`; calling it yields results whose `.audio` is a 24 kHz tensor and whose `.tokens` have `.text`, `.start_ts`, `.end_ts` (seconds, relative to that result's chunk; may be None).
- Long text is split into several results. Their timestamps each start at 0, so they must be offset by the length of the audio before them.
- Voice ids: first letter is the language (`a` American, `b` British), second the voice's sex (`f`, `m`). Apple Silicon GPU needs `PYTORCH_ENABLE_MPS_FALLBACK=1`.

## Global Constraints

- Design rule 2 holds: if Kokoro fails, the build stops and says why. It never switches to Edge.
- English voices only: ids matching `^[ab][fm]_[a-z]+$`. Anything else stops at settings time.
- Versions pinned in R constants; the engine string `"kokoro 0.9.4"` goes into the voice cache key.
- No em-dashes in user-facing text (messages, README, vignette, skill). No AI attribution anywhere.
- New settings key: `voice: kokoro_speed:` (number, 0.5 to 2, default 1). It enters the cache key.
- Tests that need uv and the model are skipped on CRAN and CI, like the Manim ones.
- Each task ends with a commit only after Logan says commit.

## Review Focus

1. A long segment (several Kokoro chunks): captions must stay in step past the first chunk. Test in Task 1 checks word times increase across a chunk boundary.
2. First run on a new machine downloads the model: startup must allow minutes, and say why it is waiting. Task 1 uses a 900 s startup timeout and prints one message before starting.
3. The runner dies mid-build (crash, Ctrl-C in an earlier build): the next request must notice, not hang. Task 1 tests a dead process gives a `lecturecast_error` naming the voice step and the runner's last stderr lines; a stale process left in `lc_state` is replaced.
4. Text with numbers and symbols ("3.5%", "$20"): audio must still come back non-empty. Covered by the Task 1 live test text.
5. A mistyped voice id (`af_hart`): Kokoro errors when loading the voice; the build must stop with the id and the fix, at the first segment. Task 1 tests the runner's error reply becomes `lc_abort`.

---

### Task 1: The Kokoro runner and its R wrapper

**Files:**
- Create: `inst/python/lecturecast_kokoro.py`
- Create: `R/kokoro.R`
- Modify: `R/voice.R` (add `lc_state$kokoro <- NULL`)
- Test: `tests/testthat/test-kokoro.R`

**Interfaces:**
- Produces:
  - `lc_kokoro_version <- "0.9.4"`, `lc_kokoro_python <- "3.12"`
  - `lc_kokoro_command()` returns `c(uv, "run", "-q", "--no-project", "--python", "3.12", "--with", "kokoro==0.9.4", "--with", "soundfile==0.14.0", "python", <runner path>)`; aborts with the uv install fix when uv is missing. Versions overridable by options `lecturecast.kokoro_version` as with Edge.
  - `lc_find_kokoro()` returns the command as one string, or `""`.
  - `lc_kokoro_engine()` returns `"kokoro 0.9.4"`.
  - `lc_kokoro_start(timeout = 900)` returns a processx process (stdin and stdout pipes, stderr to a temp file, env adds `PYTORCH_ENABLE_MPS_FALLBACK=1`), after reading the runner's `{"ready": true}` line. Prints "Starting Kokoro (the first run downloads the voice model)." unless quiet.
  - `lc_kokoro_get()` returns the live process in `lc_state$kokoro`, starting a new one if absent or dead.
  - `lc_kokoro_stop()` kills and clears `lc_state$kokoro`; safe to call when none is running.
  - `lc_kokoro_ask(req, timeout = 180)` sends one JSON line, returns the parsed reply list; aborts on timeout, on a dead process (message includes the last 5 stderr lines), or on `ok: false` (message is the runner's `error`).
  - `lc_voice_kokoro(text, voice_id, cfg, out)` returns `list(file = out, timing = data.frame(text, start, end))` like `lc_voice_edge`. `out` is an `.mp3`; the runner writes a WAV beside it and R converts with FFmpeg (`-codec:a libmp3lame -q:a 2`), then deletes the WAV.

**Runner protocol (exact):** one JSON object per line each way.
- On start, after importing kokoro: print `{"ready": true, "version": "<kokoro version>"}`.
- Request: `{"text": str, "voice": str, "speed": number, "out": "<path>.wav"}`.
- Reply: `{"ok": true, "seconds": number, "words": [{"text": str, "start": number, "end": number}, ...]}` or `{"ok": false, "error": str}`.
- One `KPipeline` per language letter, made on first use and kept. Chunks are concatenated; each chunk's token times are offset by the summed length of earlier chunks; tokens with a None time or no letters or digits are dropped. No audio at all is `ok: false` with "Kokoro returned no audio."
- Any exception in a request is caught and replied as `ok: false`; the loop continues. Flush stdout after every line.

- [ ] **Step 1: Write the failing unit tests** (mock `lc_kokoro_ask`; no uv needed)
  - `"Kokoro is run through uv at pinned versions"`: with `lc_find_tool` mocked to give `/x/uv`, `lc_kokoro_command()` contains `"kokoro==0.9.4"`, `"--python"`, `"3.12"` and ends with a path ending `lecturecast_kokoro.py` that exists.
  - `"Kokoro word times become caption timing"`: `lc_kokoro_ask` mocked to write a 1 s sine WAV (FFmpeg) and reply `words = list(list(text="Tea", start=0.28, end=0.55), list(text="is", start=0.55, end=0.66))`; `lc_voice_kokoro()` returns an `.mp3` of about 1 s and `timing` equal to `data.frame(text=c("Tea","is"), start=c(0.28,0.55), end=c(0.55,0.66))`.
  - `"a Kokoro error reply stops the build with the voice id"`: reply `list(ok = FALSE, error = "voice af_hart not found")` gives `expect_error(..., class = "lecturecast_error")` whose message contains `af_hart`, and whose fix says to check the voice id against Kokoro's voice list.
- [ ] **Step 2: Run them; expect failures** (`devtools::test(filter = "kokoro")`: functions not found)
- [ ] **Step 3: Write the runner and `R/kokoro.R`** to the interfaces above.
- [ ] **Step 4: Write the live tests** (skip on CRAN and CI, skip if `lc_find_kokoro()` is empty):
  - `"Kokoro voices a sentence with numbers"`: `lc_voice_kokoro("Prices rose 3.5% to $20.", "af_heart", cfg, out)` gives a file over 1 s and a timing table with at least 3 rows.
  - `"long text keeps word times rising across chunks"`: a 900-word text (the Task 1 sentence repeated); `timing$start` is non-decreasing and its last value is within 2 s of the file's duration.
  - `"a dead Kokoro process is noticed and replaced"`: start, `lc_state$kokoro$kill()`, then `lc_kokoro_ask()` errors with class `lecturecast_error`; `lc_kokoro_get()` then returns a live process.
  - `"a mistyped voice stops with its id"`: voice `af_hart` errors, message contains `af_hart`.
  - Each live test calls `lc_kokoro_stop()` in `withr::defer`.
- [ ] **Step 5: Run the whole file; all pass.** Then the full suite: `[ FAIL 0 ...]`.
- [ ] **Step 6: Commit** (after Logan says so): `Kokoro: local voice runner and its R wrapper`

### Task 2: Kokoro as a provider in builds and podcasts

**Files:**
- Modify: `R/config.R` (providers list; `kokoro_speed` default and check; voice id check)
- Modify: `R/voice.R` (`lc_voice` switch gains `kokoro = lc_voice_kokoro(...)`)
- Modify: `R/build.R:365-375` (cache key: `rate` = `kokoro_speed`, `engine` = `lc_kokoro_engine()` for kokoro), `R/build.R:447` and `R/podcast.R:164` (start Kokoro up front, as Edge's command check does), and stop it when `build_video()` and `build_podcast()` exit (`on.exit(lc_kokoro_stop(), add = TRUE)`)
- Modify: `R/check.R` (row `lc_row("kokoro", lc_find_kokoro(), "voice provider: kokoro")`, roxygen text)
- Modify: `R/use.R` (default `provider = "kokoro"`; narrator default depends on provider: Kokoro `am_michael`, Edge `en-US-AndrewNeural`)
- Test: `tests/testthat/test-config.R`, `test-cache.R`, `test-check.R`, `test-use.R`, `test-kokoro.R`

**Interfaces:**
- Consumes: Task 1's `lc_voice_kokoro`, `lc_kokoro_get`, `lc_kokoro_stop`, `lc_kokoro_engine`, `lc_find_kokoro`.
- Produces: `cfg$voice$kokoro_speed` (numeric, default 1).

- [ ] **Step 1: Write the failing tests**
  - config: `provider: kokoro` with `narrator: am_michael` loads; `narrator: en-US-AndrewNeural` under kokoro stops with "Kokoro voice ids look like af_heart or am_michael"; `kokoro_speed: 3` stops with "must be a number from 0.5 to 2"; default `kokoro_speed` is 1.
  - cache: two configs differing only in `kokoro_speed` give different `lc_cache_key()`s; the key includes `"kokoro 0.9.4"` (mock `lc_kokoro_engine` to a test string and see the key change when it changes).
  - check: the result has a `kokoro` row.
  - use: `use_lecturecast()` with no arguments writes `provider: kokoro` and `narrator: am_michael`; `use_lecturecast(provider = "edge")` still writes `narrator: en-US-AndrewNeural`. Update any existing test-use assertions that expect Edge by default.
  - build (integration, skip like Manim's): the fixture deck with `provider: kokoro`, `lc_voice_kokoro` mocked to write a 1 s sine and word timing, builds; `lc_kokoro_stop` mocked to count calls is called once at the end, also when the build stops on an error.
- [ ] **Step 2: Run them; expect failures.**
- [ ] **Step 3: Make the edits listed under Files.**
- [ ] **Step 4: Run the full suite; all pass.** Then `R CMD check --as-cran`: 0 errors, 0 warnings, 0 notes (`inst/python` must be in the built package; confirm `system.file("python", "lecturecast_kokoro.py", package = "lecturecast")` is not empty after install).
- [ ] **Step 5: Commit** (after Logan says so): `Kokoro: voice provider for videos and podcasts`

### Task 3: Docs and a real build

**Files:**
- Modify: `README.md` (voice list gains Kokoro: free, runs on your computer, no account; needs uv; first run downloads the model. The setup paragraph that says `use_lecturecast()` writes an Edge voice now says Kokoro, am_michael)
- Modify: `inst/skills/lecture-video/SKILL.md:63` (same default change)
- Modify: `inst/skills/lecture-video/SKILL.md` where it names the Edge voice setup (the only skill that mentions providers; `vignettes/narration.Rmd` names none)
- Modify: `project/plans/2026-10-13-lecturecast-plan.md` (Tech Stack and Settings list kokoro), `project/plans/2026-10-13-ledger.md` (task log, research facts above)

- [ ] **Step 1: Make the doc edits.** Show Logan the diffs first.
- [ ] **Step 2: Real build.** Copy `inst/examples/manim/` to `work/kokoro-example/`, set `provider: kokoro`, `narrator: am_michael` (the default), build, and open the video for Logan. Report the build time and how long Kokoro startup took.
- [ ] **Step 3: Check captions by eye** on one slide with a long note: the words on screen match the voice to within a word.
- [ ] **Step 4: Full suite and R CMD check again;** both clean.
- [ ] **Step 5: Commit** (after Logan says so): `Kokoro: docs and example`

## Rulings (Logan, 2026-11-08)

1. Kokoro becomes the default provider in `use_lecturecast()`. Edge stays available.
2. The default Kokoro narrator is `am_michael`.


Note: `use_lecturecast()` already never overwrites a settings file, so decks set to Edge keep Edge.
