# lecturecast Plan

**Goal:** An R package that makes (1) narrated lecture videos from Quarto reveal.js slides and (2) two-voice podcast episodes from course material, reliably enough to run every week of an online course.

**Why not video_explainer:** Tried on 2026-10-13 (log in `coursepack/project/plans/2026-10-13-explainer-video-facility.md`). The video looked good, but it hard-coded a retired model in 10 files, crashed between steps, reported a broken scene as a success, and hung silently unpacking its browser. It runs hidden Claude sessions with permissions skipped, and it has no licence. lecturecast is written from scratch and copies none of its code.

**Tech Stack:** R package (MIT). External tools: Quarto, Chrome, FFmpeg. Voice services by setting: ElevenLabs API, Microsoft Edge voices, or recorded audio.

**Status:** Plan only. Name and licence chosen by the instructor on 2026-10-13. Nothing built.

## Design rules

1. **The instructor approves every word before it is voiced.** Scripts are plain text files in the course repo. Claude drafts them inside the instructor's own session through the shipped skills; the package never calls an LLM.
2. **The voice is a setting, never a fallback.** If the chosen voice fails (bad key, no credits, service down), the build stops and says why. It never switches voice.
3. **Every step checks its own output.** Each external call has a timeout. After each step the package confirms the expected files exist and have the right duration, using `ffprobe`. "Completed" is printed only after that check.
4. **Stop loudly.** Any failure stops the build with a message naming the step, the file and the fix. No silent hangs, no partial output presented as finished.
5. **Pay once.** Each voiced segment is cached by a hash of its text, voice, model and settings. Rebuilding after a slide edit re-voices only the changed segments.
6. **Only named files are read.** A build reads the deck or source files it is given and nothing else. Text sent to ElevenLabs leaves the machine, so only material meant for students goes in.
7. **Optional for coursepack.** coursepack lists lecturecast under `Suggests`, checks `requireNamespace()`, and without it says videos are unavailable. Nothing in coursepack fails.

## Settings

A `lecturecast.yml` next to the deck or at the course root:

```yaml
voice:
  provider: elevenlabs        # elevenlabs | edge | recorded
  narrator: <voice id>        # lecture videos
  host_a: <voice id>          # podcasts
  host_b: <voice id>
  model: eleven_multilingual_v2
video:
  resolution: 1080p
  title_card: true
```

The ElevenLabs key comes only from the `ELEVENLABS_API_KEY` environment variable, never from a file.

## Product 1: lecture video

1. **Script.** Each slide's narration lives in its speaker notes (`::: notes`). A slide with fragments splits its notes into one segment per fragment. A slide with no notes stops the build, unless marked silent with a duration.
2. **Render.** Quarto renders the deck as it already does.
3. **Voice.** One audio file per segment, through the chosen provider. Recorded mode reads the instructor's files by slide and segment name and fails on any missing one.
4. **Capture.** Headless Chrome opens the rendered deck, steps through it with reveal.js's own API, and captures each slide and fragment state at full resolution. Plotly charts are captured fully drawn.
5. **Assemble.** FFmpeg joins the captures to the audio, with crossfades and optional title and end cards.
6. **Captions.** WebVTT built from the script text and the segment timings, so the words match the audio exactly. ElevenLabs timing data sharpens the timing when that provider is used.
7. **Output.** `<deck>.mp4`, `<deck>.vtt`, `<deck>-transcript.md`.

## Product 2: podcast

1. **Sources.** One or more course files, named explicitly.
2. **Script.** A two-host dialogue in a plain-text file (`HOST_A:` and `HOST_B:` lines, with ElevenLabs cues such as `[curious]`). One host explains; the other asks what a student would. Claude drafts it through the podcast skill, then checks every factual line against the named sources, then the instructor approves it.
3. **Voice.** ElevenLabs "Create dialogue" (`POST /v1/text-to-dialogue`, model `eleven_v3`), sent in chunks of at most 2,000 characters as its docs advise, using `previous_text` and `future_text` for continuity. With Edge or single-voice settings, each line is voiced separately and joined. Edge ignores cues, which sounds flatter; the docs say so.
4. **Output.** `<episode>.mp3`, transcript, chapter list. Optionally a video version over chosen slides.

## Skills shipped with the package

- `lecturecast-setup`: install and check Quarto, Chrome, FFmpeg and the voice provider; voice and key setup.
- `lecture-video`: draft or revise speaker notes with the instructor, then build and review.
- `lecture-podcast`: draft the dialogue, fact-check it against the sources, get approval, then build.

## Phases

0. **Skeleton.** `DESCRIPTION`, `lecturecast_check()` reporting which tools and keys are present, test setup, GitHub's automatic test run with no external tools.
1. **Lecture video, simplest form.** Static slides, one segment per slide, Edge and ElevenLabs, captions. Tested on one real deck.
2. **Polish.** Fragments on cue, crossfades, title and end cards, segment cache.
3. **Podcast.** Dialogue script format, ElevenLabs dialogue, single-voice path, transcript.
4. **Animated Plotly.** Charts animated in step with the narration, if still wanted after phase 2.
4b. **Notes written for the ear.** A vignette, "Writing notes for narration": rules for spoken text (contractions, one idea per sentence, symbols and abbreviations written out, no live-room phrases) plus the deck conventions lecturecast reads (`---` fragment steps, quoted button names, silent slides). Sources: ElevenLabs' text-to-speech best-practices page, and The eLearning Coach's voice-over script guide. A `lint_notes(deck)` that reports, and never edits, what reads badly aloud: symbols ("%", subscripts), "e.g." and "etc.", long sentences, room phrases ("the room can see"). Any AI rewrite of notes stays in the `lecture-video` skill, with every change approved by the instructor; the package only checks.
4c. **Manim scenes.** A `.manim` div on a slide names a scene file and class. Manim renders it locally (uvx, pinned version), and lecturecast plays its sections on quoted cues in the notes, either in a box on the slide or full frame. Explainer videos are decks of full-frame scenes. Data comes from R as files the scene reads. Plan: `project/plans/2026-10-14-phase-4c-manim-plan.md`. Proposal: https://claude.ai/code/artifact/21997ce6-c273-4770-bda7-28e85b9c6f03. Not started.
    Plan review (Codex, checked 2026-10-14). Plan edits to make before Task 1, diffs to Logan first:
    1. Fixture `manim.qmd` and the example deck set `title:`, so Quarto adds a title slide with no notes and the build stops (`R/script.R:44-48`). Mark slide 1 silent in both configs; renumber slides, `s02.wav`, and message assertions.
    2. `lc_frames()` keeps old frames when work_dir is reused; delete the prefix's old PNGs before extracting.
    3. Vignette says a section starts at its quote; the scheduler waits for the previous run (`R/animate.R:124`). Reword; add a test for an overrunning section.
    4. Ruling 7 (silent slide = max(scene, silent)) contradicts the code, which adds lead-in and tail (test expects 1.8 s). Recommended: change the ruling to match the code.
    5. A Manim div inside a fragment shows before its fragment. Abort with a clear message.
    6. Cache covers only sibling `.py` files and `inputs=`; vignette must say so.
    7. `lc_manim_cached()` should validate index values (NA or non-numeric seconds, missing names) and give the delete-folder fix.
    8. Missing mistyped-cue test (Review Focus 2); fake render lacks the real scene's opening section. Add both.
    9. Task 0 Step 5 `PATH=/usr/bin:/bin` hides uvx; use uvx's full path.
    10. Minor: unique temp folder per render (`tempfile(tmpdir = cache)`) instead of `<key>.tmp`; handle another build having published the key.
    Not a defect: Manim CLI facts are unverified by design; Task 0 is the gate. Vignette's "nothing beyond uv" waits on Task 0.
    Open for Logan: (A) should `video: animations: false` also disable Manim (show the scene's final picture as a still), or control Plotly only? (B) approve making edits 1-10. Also pending: proposal doc edits (pinning bullet, 5a-5c relabeled 4c).
5. **coursepack link.** `Suggests`, availability check, install skill in coursepack, a place for outputs outside git. coursepack links to the narration vignette and can run `lint_notes()` in its build.
6. **Public release.** Repo made public; CRAN optional.

## To verify before building

1. Licences of the R packages chosen for Chrome control and HTTP (likely `chromote` and `httr2`), and of `edge-tts`, which the Edge provider would need through Python.
2. ElevenLabs' terms for university course videos, and whether the free tier allows them.
3. Whether ElevenLabs' character timing data is available for the dialogue endpoint, for podcast captions.
4. How reveal.js fragments and Plotly behave under headless capture in the UWRF slide format.

## Open decisions (the instructor's)

1. Where finished videos and episodes are hosted.
2. Default voices, and whether to clone the instructor's voice.
3. Whether to remove the video_explainer install (about 700 MB in `~/Library/Application Support/coursepack/video_explainer`) and mark the coursepack plan for it superseded.
