# lecturecast

Turn Quarto reveal.js slides into narrated lecture videos, and course material into two-voice podcast episodes.

Each slide's speaker notes are its script. lecturecast voices them, captures the rendered slides in headless Chrome, plays fragments and Plotly chart animations on cue, and joins everything with FFmpeg. Every step checks its own output and stops with a plain message naming the step, the file and the fix.

## What it makes

- **Lecture videos.** `<deck>.mp4`, captions (`<deck>.vtt`) and a transcript (`<deck>-transcript.md`). Fragments appear when the narration reaches them. A quoted button name in the notes, such as "AD falls", plays that chart button at that moment. Optional title and end cards.
- **Podcasts.** `<episode>.mp3` with embedded chapters, a transcript and a chapter list, from a plain-text two-host script.

The voice is a setting: Microsoft Edge voices (free, no account), ElevenLabs (stock or cloned voices, with an ElevenLabs account), or your own recordings. If the chosen voice fails, the build stops; it never switches to another voice.

Each voiced segment is cached. After editing one slide's notes, a rebuild voices only that slide.

## Install

The repository is private for now, so installing needs a GitHub token with access to it (`GITHUB_PAT` in `~/.Renviron`):

```r
remotes::install_github("LJKelly3141/lecturecast")
```

lecturecast also needs these tools:

- [Quarto](https://quarto.org), to render the decks (lecturecast never renders them itself).
- Google Chrome, for capturing slides.
- [FFmpeg](https://ffmpeg.org), including `ffprobe`.
- For Edge voices, [uv](https://docs.astral.sh/uv/). lecturecast runs the `edge-tts` voice tool through `uvx` at a pinned version, so nothing else needs installing.
- For ElevenLabs, an API key in the `ELEVENLABS_API_KEY` environment variable. The key is never read from a settings file.

Check what is found:

```r
lecturecast::lecturecast_check()
```

## Use

Start a settings file at the project root, beside `_quarto.yml`:

```r
library(lecturecast)
use_lecturecast()
```

This writes `lecturecast.yml` with an Edge voice (en-US-AndrewNeural) and sends videos to `build/video/`, outside the rendered site. Keep `build/` in `.gitignore`. An existing settings file is never overwritten.

Render the deck with Quarto, then build:

```r
build_video("slides/week7.qmd")
```

`build_video()` takes the deck's `.qmd` or its rendered `.html`. Given a `.qmd`, it finds the render through the project's `_quarto.yml` and stops if the render is missing or older than the `.qmd`. A slide without notes must be marked silent, with a length in seconds, in `lecturecast.yml` or with `data-silent` on the slide. To build only some slides, for a test, use `build_video("slides/week7.qmd", slides = 1:5)`.

Before building, check that the notes read well aloud:

```r
lecture_script("slides/week7.qmd")   # every word, as it will be voiced
lint_notes("slides/week7.qmd")       # what a listener will stumble on
```

`lint_notes()` reports symbols, abbreviations such as "e.g.", web addresses, economics and statistics acronyms such as SRAS (with the words to say instead), phrases written for a live room, and long sentences. It changes nothing. `vignette("narration", package = "lecturecast")` explains how to write notes for the ear.

For a podcast, write a script with `HOST_A:` and `HOST_B:` lines and `##` chapter headings, then:

```r
build_podcast("podcasts/sticky-wages.txt")
```

## With an AI assistant

lecturecast is designed to be used with an AI assistant. It ships a skill, `lecture-video`, which reviews a deck's notes with `lint_notes()`, drafts each rewrite for the instructor to approve, applies only the approved changes, previews the changed slides and builds the video. The package itself never calls an AI.

In a coursepack course, `coursepack::install_skills()` copies the `lecture-video` skill into the course when lecturecast is installed, and coursepack's course-slides skill hands off to it when a deck should become a video.

## Licence

MIT. See `LICENSE.md`.
