# lecturecast

Turn Quarto reveal.js slides into narrated lecture videos, and course material into two-voice podcast episodes.

Status: planning. Nothing is built yet. The plan is in `project/plans/`.

## What it will do

- **Lecture videos.** Each slide's speaker notes become its narration. Slides are captured as they render, Plotly charts included, with fragments revealed on cue. The output is an MP4 with captions taken from the script text.
- **Podcasts.** A two-host conversation is written from named course files, reviewed by the instructor, and voiced with two different voices. The output is an MP3 with a transcript.

The voice is a setting: ElevenLabs (stock or cloned voice), Microsoft Edge voices, or the instructor's own recording.

## Licence

MIT. See `LICENSE.md`.
