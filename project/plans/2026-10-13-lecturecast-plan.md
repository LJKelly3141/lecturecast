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
