---
name: lecture-video
description: Write, review and revise a Quarto reveal.js deck's speaker notes so they read well aloud, then build the narrated lecture video with lecturecast. Run it as the first step whenever slides are being made or their speaker notes drafted, so notes are written for the ear from the start. Use when the instructor says "make slides", "draft the speaker notes", "review the notes for video", "check my speaker notes", "make the notes sound right for narration", "lint the notes", "build the lecture video", or asks to turn a deck into a narrated video.
---

# Lecture video: notes review, then build

**Run this first when making slides.** Whenever a deck is being written or
its speaker notes drafted, apply the rules and spoken forms below while
drafting, then run `lint_notes()` on the first render. Notes written for
the ear serve the classroom too, and the deck is ready for video without a
second pass.

lecturecast voices each slide's speaker notes word for word. This skill gets
the notes ready for a listener, with the instructor approving every change,
then builds the video. The package never calls an AI and never edits notes;
this skill is where drafting happens, and the instructor decides.

## Rules

1. **The instructor approves every word.** Propose; never edit the deck
   source until the instructor says yes to that change. Show before and
   after for each item.
2. **Edit the source, not the render.** Notes live in the deck's `.qmd`
   (`::: notes` blocks). Every lecturecast function takes the `.qmd` and
   reads its rendered `.html` (found through the project's `_quarto.yml`
   output-dir). lecturecast never renders: if the render is missing or
   older than the `.qmd`, it stops and says so. After approved edits, the
   instructor (or you, if asked) re-renders with `quarto render`.
3. **The deck may belong to another project.** If the `.qmd` is outside the
   current workspace, write the proposals to a file in the current project
   and ask before touching the deck.
4. **Keep what lecturecast depends on:**
   - Quoted button names (`"AD falls"`, `"Play"`, `"Round 1"`) must stay in
     quotes, spelled exactly as the chart button, or the animation will not
     play. Leave abbreviations inside them alone.
   - A `---` line between parts of a slide's notes marks a fragment step.
     Keep the same number of parts.
   - A slide with no notes must stay silent (`data-silent` or
     `video: silent:` in `lecturecast.yml`).
5. **Do not shorten the teaching.** Split long sentences; keep every idea.
6. **Do not change quotations.** A sentence quoting the textbook is flagged
   but left as is unless the instructor chooses to paraphrase.
7. **No em-dashes** in the narration.

## Steps

0. **Settings.** If the project has no `lecturecast.yml`, offer
   `lecturecast::use_lecturecast()`: Edge voice en-US-AndrewNeural, videos
   to `build/video/`. It never overwrites an existing file.
1. **Read the script.** `lecturecast::lecture_script("<deck>.qmd")` shows
   every word as it will be voiced.
2. **Lint.** `lecturecast::lint_notes("<deck>.qmd")` returns one row per
   issue: `slide`, `title`, `issue`, `found`, `sentence`, `advice`.
   Issues: `symbol`, `abbreviation`, `link`, `acronym`, `room`,
   `long sentence`.
3. **Draft the review file** (`<deck>-narration-review.md`): for each
   flagged sentence, a numbered item with Before, Proposed and a one-line
   reason. Group into "Proposed changes" and "Recommend no change" (with
   the reason). Also look for things the lint cannot see: "Ask:" prompts
   meant for the room, references to "last week's slides", gestures
   ("this one here"), and anything that assumes the viewer can interact.
4. **Get decisions.** The instructor answers yes, no or their own wording
   per item.
5. **Apply only the approved items** to the `.qmd`, render, run
   `lint_notes()` again and report what is left.
6. **Preview** the changed slides only:
   `build_video("<deck>.qmd", slides = c(...))`. Unchanged slides come
   from the cache.
7. **Build** the full video with `build_video("<deck>.qmd")`. Report the
   output paths and length.

## Spoken forms

`lint_notes()` flags these abbreviations as `acronym` (case-sensitive, whole
word, optional plural "s"). A voice reads them as a word or as letters. In
the narration, write the spoken form. On a slide where the abbreviation
appears many times, spelling out the first use and using a short spoken
form after ("demand", "supply") is fine if the instructor prefers.
Abbreviations people say as letters (GDP, CPI, Fed) are not flagged.

The table must match `lc_spoken_forms` in `R/lint.R`; a test checks it.

| Abbreviation | Say |
|---|---|
| AD | aggregate demand |
| AS | aggregate supply |
| SRAS | short-run aggregate supply |
| LRAS | long-run aggregate supply |
| MPC | marginal propensity to consume |
| MPS | marginal propensity to save |
| MPI | marginal propensity to import |
| NX | net exports |
| NNP | net national product |
| NAIRU | the non-accelerating inflation rate of unemployment |
| FOMC | the Federal Open Market Committee |
| PPF | production possibilities frontier |
| PPC | production possibilities curve |
| MC | marginal cost |
| MR | marginal revenue |
| MB | marginal benefit |
| MU | marginal utility |
| TC | total cost |
| TR | total revenue |
| FC | fixed cost |
| VC | variable cost |
| ATC | average total cost |
| AVC | average variable cost |
| AFC | average fixed cost |
| MPL | marginal product of labor |
| MRP | marginal revenue product |
| MRS | marginal rate of substitution |
| DWL | deadweight loss |
| SD | standard deviation |
| SE | standard error |
| CI | confidence interval |
| df | degrees of freedom |
| OLS | ordinary least squares |
| MLE | maximum likelihood estimate |
| IID | independent and identically distributed |
| CDF | cumulative distribution function |
| SSE | sum of squared errors |
| SSR | sum of squared residuals |
| SST | total sum of squares |
| MSE | mean squared error |
| RMSE | root mean squared error |
| ANOVA | analysis of variance |
| H0 | the null hypothesis |
| H1 | the alternative hypothesis |

Symbols follow the same idea: "R²" is "R squared", "AD₁" is "aggregate
demand one", "10%" is "10 percent" (some voices read "%" correctly; listen
before changing).

## Background

`vignette("narration", package = "lecturecast")` explains the rules for
writing to be heard, with sources.
