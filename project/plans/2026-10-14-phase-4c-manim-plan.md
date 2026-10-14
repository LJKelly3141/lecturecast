# Phase 4c: Manim Scenes on Cue, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A slide can hold a Manim scene whose sections play when the speaker notes quote their names, either in a box on the slide or filling the whole frame, so lecturecast makes both lecture videos with embedded animations and 3Blue1Brown-style explainer videos.

**Architecture:** A `.manim` div on a slide names a scene file and class. During capture, Chrome measures the div's box. After Chrome closes, Manim renders the scene once at exactly that size with `--save_sections` (one video per `self.next_section()`), cached by a hash of everything that changes the pictures. Each section video is split into PNG frames, and the existing Plotly scheduler (`lc_animation_schedule`) places them against the narration. A new clip builder lays the frames over the slide capture at the box. Voice, captions, cards, fades and the voice cache are unchanged: Manim only supplies pictures.

**Tech Stack:** R package (existing). Manim Community Edition run through `uvx --from manim==<pinned> manim` (same pattern as edge-tts), FFmpeg, headless Chrome via chromote.

**Spec:** the proposal doc "Proposal: Manim Scenes in lecturecast" (https://claude.ai/code/artifact/21997ce6-c273-4770-bda7-28e85b9c6f03), plus Logan's rulings of 2026-10-14 recorded below.

## Rulings from Logan (2026-10-14)

- Scope: core feature plus the data-from-R handoff, with one economics and one statistics example in a vignette. The four parameterized starter scenes get their own plan later.
- Placement: both. A scene can sit in a box on a slide, and a scene can fill the whole frame for explainer videos.
- Python: `uvx`, pinned, same as edge-tts. A `manim` on PATH is used first.
- Name: Phase 4c.

## Design rulings in this plan (for Logan's review before execution)

These go beyond the proposal. Each is the plan's recommendation; any can be changed before work starts.

1. **Explainer videos are decks, not a new product.** An explainer is a Quarto deck whose slides each hold one `fill="frame"` scene, with the narration in the speaker notes. It reuses `build_video()` whole, so explainers get the voice cache, captions, transcript, cards and fades for free. No `build_explainer()`.
2. **Sections nobody quotes play straight on** after the section before them, instead of the proposal's "warn". Sections before the first cue open the first segment of the slide. A scene with no cues at all plays from the start of the slide. The build prints, per slide, how many sections were cued, so a mistyped cue is visible.
3. **Cues must follow the scene's order.** A quote naming a section that comes before one already cued stops the build, unless that section was itself already cued (a back-reference such as "as after 'demand shifts right'", which is ignored, as with Plotly).
4. **One scene per slide, and no Plotly buttons on the same slide.** Both stop the build with a clear message.
5. **Paths:** `file=` is relative to the folder holding `lecturecast.yml`. `inputs=` (the data files the scene reads) are relative to the scene file's folder, because Manim runs in that folder and the scene opens them by the same relative path.
6. **A box must have a size.** An empty div has no height in HTML, so a `fill="box"` div needs a `style=` with a width and height. A box under 16 pixels stops the build and says how to fix it. No CSS is injected.
7. **A silent slide plays its whole scene,** and the clip is as long as the scene or the silent duration, whichever is longer.
8. **The render cache key** covers the Manim version, the scene class, the contents of every `.py` file in the scene's folder (so helper modules count), the contents of each `inputs=` file, the box size, the frame rate and the background setting. Notes and voice do not affect it.

## Global Constraints

- Workspace: `/Volumes/SSD8TB/Sync/Developer/lecturecast` only. Never write into `/Volumes/SSD8TB/Sync/UWRF/Teaching/macro_principles` or any other repo.
- Renders, frames, audio and video go in gitignored places (`work/`, temp dirs, the cache dir). Never render a `.qmd` in place outside lecturecast.
- Manim version pinned in `lc_manim_version` (Task 0 confirms the value; the proposal found v0.20.1). Option `lecturecast.manim_version` overrides it, as `lecturecast.edge_tts_version` does for edge-tts.
- Manim never voices anything. No manim-voiceover.
- Every failure stops with `lc_abort(step, problem, file, fix)`. Nothing partial is reported as finished.
- No em-dashes in user-facing text: vignette, messages, example files, README.
- No mention of Claude, AI or assistants in commits, code comments or docs. No `Co-Authored-By` trailers.
- Commits only with Logan's explicit approval for each one, unless an unattended-run authorization covering this plan is quoted in the ledger's RESUME HERE block.
- `R CMD check` stays 0 errors, 0 warnings, 0 notes. CI has no Manim, Quarto or Chrome, so tests that need them use `skip_*`.
- Code matches the package's style: `lc_` prefix for internals, base R, `%||%`, short comments that say why, `vapply` with explicit types.

## Review Focus

1. **A scene that uses `MathTex` when LaTeX is missing.** Manim fails partway through. Expected: the build stops at step `manim`, shows the tail of Manim's error, and the fix says to run the scene in a terminal and to check `lecturecast_check()` for latex and dvisvgm. Test in Task 4 (`lc_manim_run` with a failing fake command).
2. **A mistyped cue** ("demand shift right"). Expected: no failure, the section plays straight on, and the build message for that slide shows fewer sections cued than the scene has. Test in Task 6 (message text).
3. **A box div with no size.** Expected: stop with the slide number and a `style=` example. Test in Task 2.
4. **Rebuilding after a notes-only edit.** Expected: no re-render. After editing a helper `.py` beside the scene: re-render. Test in Task 4 (key unchanged / changed).
5. **Changing `video: resolution:`.** Expected: the box is measured again at the new size and the scene re-renders at that size. Test in Task 4 (key includes width and height) and Task 2 (box scales with the measured rect).

## File map

- Create `R/manim.R`: everything Manim-specific (command, slide spec, box, cue runs, render and cache, frames, overlay, clip).
- Modify `R/deck.R`: `lc_read_slides()` reads `.manim` divs into a `manim` list column.
- Modify `R/build.R`: capture loop measures boxes; after Chrome closes, render, plan runs, composite stills; clip loop builds Manim clips.
- Modify `R/config.R`: `manim:` settings block and validation.
- Modify `R/check.R`: rows for manim, latex, dvisvgm.
- Modify `DESCRIPTION`: `cli (>= 3.6.0)` for `cli::hash_file_sha256()`.
- Create `tests/testthat/test-manim.R`, `tests/testthat/test-manim-integration.R`, `tests/testthat/fixtures/manim/scene.py`, `tests/testthat/fixtures/manim/manim.qmd`.
- Modify `tests/testthat/test-check.R`, `tests/testthat/test-config.R`.
- Create `inst/examples/manim/` (deck, settings, two scenes) and `vignettes/manim.Rmd`.
- Modify `project/plans/2026-10-13-lecturecast-plan.md` (add 4c to Phases) and `project/plans/2026-10-13-ledger.md` (task log, research, rulings).

---

### Task 0: Verify Manim facts before building

Nothing in this task is committed except ledger notes. Every later task assumes these facts; if one is wrong, stop and correct this plan first (tell Logan what changed).

**Files:**
- Modify: `project/plans/2026-10-13-ledger.md` (Research section)
- Scratch only: `work/manim-spike/` (gitignored)

- [ ] **Step 1: Find the current release.** Open https://pypi.org/project/manim/ and record the latest version and its date. Use it as `lc_manim_version` if it is at least two weeks old; otherwise the one before.

- [ ] **Step 2: Confirm uvx runs it on this Mac.**

Run: `uvx --from manim==<version> manim --version`
Expected: prints the version. Record how long the first run took (it downloads wheels) and whether any system library (cairo, pango) was needed.

- [ ] **Step 3: Confirm the CLI flags.**

Run: `uvx --from manim==<version> manim render --help`
Expected: these flags exist with these spellings: `--save_sections`, `--format`, `--disable_caching`, `--progress_bar`, `--resolution` (takes `W,H`), `--frame_rate` (or `--fps`), `--media_dir`, `--background_color`. Record any differences; Task 4's `lc_manim_run()` uses them.

- [ ] **Step 4: Render the test fixture scene** (copy `tests/testthat/fixtures/manim/scene.py` from Task 6, Step 1 into `work/manim-spike/`).

Run (in `work/manim-spike/`): `uvx --from manim==<version> manim render --save_sections --format mp4 --disable_caching --progress_bar none --resolution 640,360 --frame_rate 30 --media_dir media scene.py Tiny`
Expected, to record:
  - where the section list lands (expected: `media/videos/scene/<h>p<fps>/sections/Tiny.json`);
  - its form (expected: a JSON array of objects with at least `name` and `video`, `video` null for a section with no animations);
  - that section videos are 640x360 at 30 fps (`ffprobe`);
  - the name Manim gives the automatic first section.

- [ ] **Step 5: Confirm failure behaviour.** Run the same command with scene name `NoSuchScene`, and once with a scene that uses `MathTex` while `latex` is hidden from PATH (`PATH=/usr/bin:/bin`). Record the exit status and the last stderr lines. If a missing class exits 0, `lc_manim_run()` must rely on the missing section list (it already does).

- [ ] **Step 6: Confirm Pandoc writes div attributes as `data-*`.** Render `tests/testthat/fixtures/manim/manim.qmd` (Task 6, Step 1) in `work/manim-spike/` with `quarto render` and run `grep -o '<div class="manim"[^>]*>' manim.html`.
Expected: `data-file="scene.py" data-scene="Tiny"` and the `style` attribute. `lc_read_slides()` reads both `data-x` and `x`, so either form works; record which.

- [ ] **Step 7: Confirm the example scenes render** (Task 7's `demand.py` and `clt.py`, with their CSVs written by hand from the R code in Task 7). Record any Manim API errors (`get_lines_to_point`, `x_axis.unit_size`) and fix the scene code in this plan before Task 7.

- [ ] **Step 8: Confirm `cli::hash_file_sha256()` exists** in the installed cli and the version that added it: `Rscript -e 'packageVersion("cli"); cli::hash_file_sha256(system.file("DESCRIPTION", package = "cli"))'`.

- [ ] **Step 9: Record findings** in the ledger's Research section under "Phase 4c". Show Logan the findings and any plan changes before Task 1.

---

### Task 1: Settings, the manim command, and the check

**Files:**
- Create: `R/manim.R`
- Modify: `R/config.R` (`lc_config_defaults`, `lc_config_validate`)
- Modify: `R/check.R` (`lecturecast_check`)
- Modify: `DESCRIPTION` (Imports: `cli (>= 3.6.0)`)
- Test: `tests/testthat/test-manim.R`, `tests/testthat/test-config.R`, `tests/testthat/test-check.R`

**Interfaces:**
- Produces: `lc_manim_version` (chr), `lc_manim_command()` -> character vector `c(command, leading args)`, `lc_find_manim()` -> chr ("" if absent), `lc_manim_engine()` -> chr version label, `cfg$manim$background` (NULL or hex string), `cfg$manim$timeout` (number of seconds, default 900).

- [ ] **Step 1: Write the failing tests** in `tests/testthat/test-manim.R`:

```r
test_that("manim on PATH is used first, then uvx with the pinned version", {
  local_mocked_bindings(lc_find_tool = function(tool) if (tool == "manim") "/fake/manim" else "/fake/uvx")
  expect_equal(lc_manim_command(), "/fake/manim")
  local_mocked_bindings(lc_find_tool = function(tool) if (tool == "uvx") "/fake/uvx" else "")
  expect_equal(lc_manim_command(), c("/fake/uvx", "--from", paste0("manim==", lc_manim_version), "manim"))
  withr::local_options(lecturecast.manim_version = "0.1.0")
  expect_equal(lc_manim_command()[3], "manim==0.1.0")
})

test_that("no manim and no uv stops with a fix", {
  local_mocked_bindings(lc_find_tool = function(tool) "")
  expect_error(lc_manim_command(), "Manim was not found")
  expect_equal(lc_find_manim(), "")
})

test_that("the engine label under uvx is the pinned version, without running anything", {
  local_mocked_bindings(lc_find_tool = function(tool) if (tool == "uvx") "/fake/uvx" else "",
                        lc_run = function(...) stop("not called"))
  expect_equal(lc_manim_engine(), paste0("manim==", lc_manim_version))
})
```

Add to `tests/testthat/test-config.R`:

```r
test_that("manim settings have defaults and are checked", {
  cfg <- lecturecast_config(config = write_config(c("voice:", "  provider: edge")))
  expect_null(cfg$manim$background)
  expect_equal(cfg$manim$timeout, 900)
  ok <- lecturecast_config(config = write_config(c("voice:", "  provider: edge", "manim:", "  background: \"#ffffff\"", "  timeout: 60")))
  expect_equal(ok$manim$background, "#ffffff")
  expect_error(lecturecast_config(config = write_config(c("voice:", "  provider: edge", "manim:", "  background: white"))),
               "manim: background: must be a hex colour")
  expect_error(lecturecast_config(config = write_config(c("voice:", "  provider: edge", "manim:", "  timeout: 0"))),
               "manim: timeout: must be a number of seconds")
})
```

In `tests/testthat/test-check.R`, change the expected items in "check reports every item without external tools" to:

```r
  expect_equal(
    out$item,
    c("quarto", "chrome", "ffmpeg", "ffprobe", "edge-tts", "manim", "latex", "dvisvgm", "ELEVENLABS_API_KEY")
  )
```

and add to "check finds tools that are present":

```r
  expect_equal(out$detail[out$item == "manim"], "/fake/bin/manim")
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `Rscript -e 'devtools::test(filter = "manim|config|check")'`
Expected: FAIL, `could not find function "lc_manim_command"` and the item list mismatch.

- [ ] **Step 3: Implement.** Create `R/manim.R`:

```r
# Manim scenes played on cue. A slide holds a div with class manim naming a
# scene file and class. Manim renders the scene once per size, one video per
# section (self.next_section("name")), and each section plays when the notes
# quote its name. The scene is laid over the slide capture at the div's box,
# or over the whole frame with fill="frame".

lc_manim_version <- "0.20.1"

# The manim command as c(command, leading args): manim on PATH, else the
# pinned version through uvx.
lc_manim_command <- function() {
  path <- lc_find_tool("manim")
  if (nzchar(path)) return(path)
  uvx <- lc_find_tool("uvx")
  if (nzchar(uvx)) {
    return(c(uvx, "--from", paste0("manim==", getOption("lecturecast.manim_version", lc_manim_version)), "manim"))
  }
  lc_abort("manim", "Manim was not found, and uv is not installed to run it.",
           fix = "Install uv (https://docs.astral.sh/uv/), or install Manim Community Edition so manim is on PATH.")
}

lc_find_manim <- function() {
  cmd <- tryCatch(lc_manim_command(), lecturecast_error = function(e) "")
  paste(cmd, collapse = " ")
}

# The Manim version that will run, for the render cache key: the pinned
# version under uvx, or what an installed manim reports. Looked up once per
# session.
lc_manim_engine <- function() {
  cmd <- lc_manim_command()
  if (length(cmd) > 1) return(cmd[3])
  if (is.null(lc_state$manim_engine[[cmd]])) {
    res <- lc_run(cmd, "--version", step = "manim", timeout = 120)
    lc_state$manim_engine[[cmd]] <- trimws(res$stdout)
  }
  lc_state$manim_engine[[cmd]]
}
```

(Use the version Task 0 recorded in place of `"0.20.1"` if it differs.)

In `R/config.R`, `lc_config_defaults()`: add `manim <- raw$manim %||% list()` beside the other blocks, and add to the returned list:

```r
    manim = list(
      background = manim$background,
      timeout = manim$timeout %||% 900
    ),
```

In `lc_config_validate()`, before `invisible(TRUE)`:

```r
  bg <- cfg$manim$background
  if (!is.null(bg) && !(is.character(bg) && length(bg) == 1 && grepl("^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$", bg))) {
    lc_abort(step, "manim: background: must be a hex colour such as \"#ffffff\".", file = path)
  }
  to <- cfg$manim$timeout
  if (!is.numeric(to) || length(to) != 1 || is.na(to) || to <= 0) {
    lc_abort(step, "manim: timeout: must be a number of seconds above 0.", file = path)
  }
```

In `R/check.R`, update the roxygen sentence to name Manim, LaTeX and dvisvgm, and add after the edge-tts row:

```r
    lc_row("manim", lc_find_manim(), "Manim scenes"),
    lc_row("latex", lc_find_tool("latex"), "math text in Manim scenes"),
    lc_row("dvisvgm", lc_find_tool("dvisvgm"), "math text in Manim scenes"),
```

In `DESCRIPTION`, change `cli,` to `cli (>= 3.6.0),` (or the version Task 0 recorded).

- [ ] **Step 4: Run the tests to see them pass**

Run: `Rscript -e 'devtools::document(); devtools::test(filter = "manim|config|check")'`
Expected: PASS.

- [ ] **Step 5: Commit** (with Logan's approval)

```bash
git add R/manim.R R/config.R R/check.R DESCRIPTION man/lecturecast_check.Rd tests/testthat/test-manim.R tests/testthat/test-config.R tests/testthat/test-check.R
git commit -m "Phase 4c: manim command, settings and check rows"
```

---

### Task 2: Read the scene div and measure its box

**Files:**
- Modify: `R/deck.R` (`lc_read_slides`)
- Modify: `R/manim.R`
- Test: `tests/testthat/test-manim.R`

**Interfaces:**
- Consumes: `lc_abort`, `lc_js` (existing).
- Produces:
  - `slides$manim`: list column; element k is a list of raw div records `list(file, scene, inputs, fill)` (empty list when none).
  - `lc_manim_spec(m, slide, deck)` -> NULL or `list(file = chr, scene = chr, inputs = chr vector, fill = "box" | "frame")`.
  - `lc_manim_paths(spec, cfg)` -> `list(scene = absolute path, inputs = absolute paths)`.
  - `lc_manim_box(r, wh, slide, deck)` -> named integer `c(x, y, w, h)`; `r` is `list(x, y, w, h)` in CSS pixels.
  - `lc_manim_rect(b, spec, wh, deck, slide)` -> same as `lc_manim_box`.

- [ ] **Step 1: Write the failing tests** (append to `tests/testthat/test-manim.R`):

```r
div <- function(...) list(modifyList(list(file = "scenes/a.py", scene = "A", inputs = "", fill = ""), list(...)))

test_that("a slide's manim div becomes a spec", {
  expect_null(lc_manim_spec(list(), 1, "d.html"))
  s <- lc_manim_spec(div(inputs = "data/x.csv, data/y.csv"), 2, "d.html")
  expect_equal(s$file, "scenes/a.py")
  expect_equal(s$scene, "A")
  expect_equal(s$fill, "box")
  expect_equal(s$inputs, c("data/x.csv", "data/y.csv"))
  expect_equal(lc_manim_spec(div(fill = "frame"), 2, "d.html")$fill, "frame")
})

test_that("bad manim divs stop the build", {
  expect_error(lc_manim_spec(c(div(), div()), 3, "d.html"), "Slide 3 has 2 Manim divs")
  expect_error(lc_manim_spec(div(scene = ""), 3, "d.html"), "no scene= attribute")
  expect_error(lc_manim_spec(div(file = ""), 3, "d.html"), "no file= attribute")
  expect_error(lc_manim_spec(div(fill = "page"), 3, "d.html"), "fill= must be box or frame")
  expect_error(lc_manim_spec(div(scene = "A; rm"), 3, "d.html"), "not a Python class name")
})

test_that("scene paths are relative to the settings file, inputs to the scene", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "scenes", "data"), recursive = TRUE)
  writeLines("", file.path(dir, "scenes", "a.py"))
  writeLines("x", file.path(dir, "scenes", "data", "x.csv"))
  cfg <- list(path = file.path(dir, "lecturecast.yml"))
  p <- lc_manim_paths(lc_manim_spec(div(inputs = "data/x.csv"), 1, "d.html"), cfg)
  expect_equal(p$scene, normalizePath(file.path(dir, "scenes", "a.py")))
  expect_equal(unname(p$inputs), file.path(dir, "scenes", "data", "x.csv"))
  expect_error(lc_manim_paths(lc_manim_spec(div(file = "nope.py"), 1, "d.html"), cfg), "scene file does not exist")
  expect_error(lc_manim_paths(lc_manim_spec(div(inputs = "data/none.csv"), 1, "d.html"), cfg), "input file does not exist")
})

test_that("the box is rounded to even pixels and kept on screen", {
  b <- lc_manim_box(list(x = 101.4, y = 50.6, w = 801.2, h = 451), c(1920L, 1080L), 1, "d.html")
  expect_equal(unname(b), c(102L, 50L, 802L, 452L))
  expect_equal(names(b), c("x", "y", "w", "h"))
  edge <- lc_manim_box(list(x = 1800, y = 0, w = 400, h = 200), c(1920L, 1080L), 1, "d.html")
  expect_equal(unname(edge[["w"]]), 120L)
})

test_that("a box with no size stops with a fix", {
  expect_error(lc_manim_box(list(x = 10, y = 10, w = 900, h = 0), c(1920L, 1080L), 4, "d.html"),
               "slide 4 is 900x0 pixels")
  expect_error(lc_manim_box(NULL, c(1920L, 1080L), 4, "d.html"), "not found on slide 4")
})

test_that("fill frame covers the whole video without asking Chrome", {
  r <- lc_manim_rect(NULL, list(fill = "frame"), c(1280L, 720L), "d.html", 1)
  expect_equal(unname(r), c(0L, 0L, 1280L, 720L))
})
```

- [ ] **Step 2: Run to see them fail**

Run: `Rscript -e 'devtools::test(filter = "manim")'`
Expected: FAIL, `could not find function "lc_manim_spec"`.

- [ ] **Step 3: Implement.** In `R/deck.R`, inside the JS object returned per slide in `lc_read_slides()`, after the `buttons:` entry, add:

```js
        manim: Array.from(s.querySelectorAll('div.manim')).map(d => {
          // Pandoc writes key=value attributes as data-key in HTML.
          const a = n => d.getAttribute('data-' + n) || d.getAttribute(n) || '';
          return {file: a('file'), scene: a('scene'), inputs: a('inputs'), fill: a('fill')};
        })
```

and to the returned `data.frame(...)`, after `buttons = ...`:

```r
    manim = I(lapply(x, function(s) s$manim %||% list())),
```

Append to `R/manim.R`:

```r
# The Manim div on a slide as a spec, or NULL when the slide has none.
lc_manim_spec <- function(m, slide, deck) {
  step <- "manim"
  if (length(m) == 0) return(NULL)
  if (length(m) > 1) {
    lc_abort(step, sprintf("Slide %d has %d Manim divs; a slide can hold one.", slide, length(m)), file = deck)
  }
  m <- m[[1]]
  example <- "Write it as ::: {.manim file=\"scenes/market.py\" scene=\"DemandShift\"}"
  for (k in c("file", "scene")) {
    if (is.null(m[[k]]) || !nzchar(m[[k]])) {
      lc_abort(step, sprintf("The Manim div on slide %d has no %s= attribute.", slide, k), file = deck, fix = example)
    }
  }
  if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", m$scene)) {
    lc_abort(step, sprintf("scene=\"%s\" on slide %d is not a Python class name.", m$scene, slide), file = deck, fix = example)
  }
  fill <- if (is.null(m$fill) || !nzchar(m$fill)) "box" else m$fill
  if (!fill %in% c("box", "frame")) {
    lc_abort(step, sprintf("fill= must be box or frame (slide %d has \"%s\").", slide, fill), file = deck)
  }
  inputs <- if (is.null(m$inputs) || !nzchar(trimws(m$inputs))) character(0) else trimws(strsplit(m$inputs, ",", fixed = TRUE)[[1]])
  list(file = m$file, scene = m$scene, inputs = inputs[nzchar(inputs)], fill = fill)
}

# Scene paths are relative to the folder holding lecturecast.yml; inputs to
# the scene's own folder, where Manim runs and the scene opens them.
lc_manim_paths <- function(spec, cfg) {
  step <- "manim"
  absolute <- function(p, root) if (grepl("^(/|~|[A-Za-z]:)", p)) path.expand(p) else file.path(root, p)
  scene <- absolute(spec$file, dirname(cfg$path))
  if (!file.exists(scene)) {
    lc_abort(step, "The scene file does not exist.", file = scene,
             fix = "Paths in file= are relative to the folder holding lecturecast.yml.")
  }
  inputs <- vapply(spec$inputs, absolute, "", root = dirname(scene))
  for (f in inputs) {
    if (!file.exists(f)) {
      lc_abort(step, "An input file does not exist.", file = f,
               fix = "Paths in inputs= are relative to the scene file's folder. Render the deck first if R writes them.")
    }
  }
  list(scene = normalizePath(scene), inputs = unname(inputs))
}

# The div's box in video pixels, rounded to even numbers for the encoder and
# kept inside the frame.
lc_manim_box <- function(r, wh, slide, deck) {
  step <- "manim"
  if (is.null(r)) lc_abort(step, sprintf("The Manim div was not found on slide %d during capture.", slide), file = deck)
  even <- function(v) 2L * as.integer(round(v / 2))
  x <- max(0L, even(r$x))
  y <- max(0L, even(r$y))
  w <- min(even(r$w), wh[1] - x)
  h <- min(even(r$h), wh[2] - y)
  if (w < 16 || h < 16) {
    lc_abort(step, sprintf("The Manim div on slide %d is %dx%d pixels on screen, too small to show a scene.", slide, w, h),
             file = deck, fix = "Give the div a size, for example style=\"width: 100%; height: 480px;\", or use fill=\"frame\".")
  }
  c(x = x, y = y, w = w, h = h)
}

# Measure the div on the current slide. fill = frame covers the whole video.
lc_manim_rect <- function(b, spec, wh, deck, slide) {
  if (identical(spec$fill, "frame")) return(c(x = 0L, y = 0L, w = as.integer(wh[1]), h = as.integer(wh[2])))
  js <- "(() => {
    const d = Reveal.getCurrentSlide().querySelector('div.manim');
    if (!d) return null;
    const r = d.getBoundingClientRect();
    return JSON.stringify({x: r.left, y: r.top, w: r.width, h: r.height});
  })()"
  v <- lc_js(b, js, "manim", deck)
  lc_manim_box(if (is.null(v)) NULL else jsonlite::fromJSON(v), wh, slide, deck)
}
```

Note for the reviewer: `getBoundingClientRect()` includes reveal.js's scale transform, and the Chrome viewport equals the video size, so CSS pixels are video pixels.

- [ ] **Step 4: Run to see them pass**

Run: `Rscript -e 'devtools::test(filter = "manim")'`
Expected: PASS. Also run the whole suite (`devtools::test()`) to confirm `lc_read_slides` changes broke nothing.

- [ ] **Step 5: Commit** (with Logan's approval)

```bash
git add R/deck.R R/manim.R tests/testthat/test-manim.R
git commit -m "Phase 4c: read Manim divs and measure their box"
```

---

### Task 3: Which sections play when

**Files:**
- Modify: `R/manim.R`
- Test: `tests/testthat/test-manim.R`

**Interfaces:**
- Consumes: `lc_quotes(text)` (data frame `phrase`, `pos`), `lc_label_key(x)` (both in `R/animate.R`).
- Produces: `lc_manim_runs(texts, names, slide, deck = NULL)` -> data frame with columns `seg` (int, 1-based segment within the slide), `pos` (num, cue position in non-space characters, 0 for the opening), `from`, `to` (int section indices), `cued` (logical).

- [ ] **Step 1: Write the failing tests:**

```r
test_that("a scene with no cues plays whole from the start of the slide", {
  r <- lc_manim_runs("No quotes here.", c("a", "b", "c"), 1)
  expect_equal(r$seg, 1L)
  expect_equal(r$pos, 0)
  expect_equal(c(r$from, r$to), c(1L, 3L))
  expect_false(r$cued)
})

test_that("each quoted section starts at its quote; the opening plays first", {
  text <- "First the square. Now “grow” it. Then \"spin\" it."
  r <- lc_manim_runs(text, c("autocreated", "grow", "spin"), 1)
  expect_equal(r$from, 1:3)
  expect_equal(r$to, 1:3)
  expect_equal(r$pos, c(0, lc_nows("First the square. Now "), lc_nows("First the square. Now “grow” it. Then ")))
  expect_equal(r$cued, c(FALSE, TRUE, TRUE))
})

test_that("unquoted sections play straight on after the one before", {
  r <- lc_manim_runs("Then \"c\".", c("a", "b", "c", "d"), 1)
  expect_equal(r$from, c(1L, 3L))
  expect_equal(r$to, c(2L, 4L))
})

test_that("cues can come from later segments of the same slide", {
  r <- lc_manim_runs(c("Here is \"b\".", "And then \"c\"."), c("a", "b", "c"), 1)
  expect_equal(r$seg, c(1L, 1L, 2L))
  expect_equal(r$from, 1:3)
})

test_that("a quoted first section has no separate opening", {
  r <- lc_manim_runs("\"a\" then \"b\".", c("a", "b"), 1)
  expect_equal(r$from, 1:2)
  expect_equal(r$cued, c(TRUE, TRUE))
})

test_that("a back-reference is ignored, but out-of-order cues stop the build", {
  r <- lc_manim_runs("\"b\" then \"c\", as after \"b\".", c("a", "b", "c"), 1)
  expect_equal(r$from, 1:3)
  expect_error(lc_manim_runs("\"c\" before \"b\".", c("a", "b", "c"), 5, "d.html"),
               "Slide 5 quotes its scene's sections out of order")
})

test_that("silent segments (empty text) cue nothing", {
  r <- lc_manim_runs("", c("a", "b"), 1)
  expect_equal(c(r$from, r$to), c(1L, 2L))
})
```

- [ ] **Step 2: Run to see them fail**

Run: `Rscript -e 'devtools::test(filter = "manim")'`
Expected: FAIL, `could not find function "lc_manim_runs"`.

- [ ] **Step 3: Implement** (append to `R/manim.R`):

```r
# Which sections play when, for one slide. `texts` holds the narration of
# the slide's segments in order ("" for silent ones). A section plays when
# the notes first quote its name; sections nobody quotes play straight on
# after the one before; sections before the first cue open the slide.
# Returns one row per run: its segment, cue position, first and last section.
lc_manim_runs <- function(texts, names, slide, deck = NULL) {
  key <- lc_label_key(names)
  cued <- data.frame(seg = integer(0), pos = numeric(0), sec = integer(0))
  for (s in seq_along(texts)) {
    q <- lc_quotes(texts[s])
    for (k in seq_len(nrow(q))) {
      hit <- match(lc_label_key(q$phrase[k]), key)
      # A section already cued is a back-reference, not a second cue.
      if (is.na(hit) || hit %in% cued$sec) next
      cued <- rbind(cued, data.frame(seg = s, pos = q$pos[k], sec = hit))
    }
  }
  if (is.unsorted(cued$sec, strictly = TRUE)) {
    lc_abort("manim", sprintf("Slide %d quotes its scene's sections out of order (%s). They play in the order the scene defines them.",
                              slide, paste0("\"", names[cued$sec], "\"", collapse = ", ")), file = deck,
             fix = "Reorder the quotes in the notes, or the next_section() calls in the scene.")
  }
  from <- sort(unique(c(1L, cued$sec)))
  to <- c(from[-1] - 1L, length(names))
  hit <- match(from, cued$sec)
  data.frame(seg = ifelse(is.na(hit), 1L, cued$seg[hit]),
             pos = ifelse(is.na(hit), 0, cued$pos[hit]),
             from = from, to = to, cued = !is.na(hit))
}
```

- [ ] **Step 4: Run to see them pass**

Run: `Rscript -e 'devtools::test(filter = "manim")'`
Expected: PASS.

- [ ] **Step 5: Commit** (with Logan's approval)

```bash
git add R/manim.R tests/testthat/test-manim.R
git commit -m "Phase 4c: plan which Manim sections play at which cue"
```

---

### Task 4: Render with Manim, through a cache

**Files:**
- Modify: `R/manim.R`
- Test: `tests/testthat/test-manim.R`

**Interfaces:**
- Consumes: `lc_manim_command()`, `lc_manim_engine()` (Task 1); `lc_manim_paths()` result (Task 2); `lc_run`, `lc_duration`, `lc_dimensions`, `lc_dir_create`, `lc_label_key`.
- Produces:
  - `lc_manim_key(paths, spec, rect, cfg)` -> sha256 chr.
  - `lc_manim_run(paths, spec, rect, cfg, media)` -> path to Manim's section list JSON.
  - `lc_manim_sections(json, spec, scene_file)` -> data frame `name`, `file` (absolute), scene order, only sections with video.
  - `lc_manim_render(paths, spec, rect, cfg, cache)` -> data frame `name`, `file` (absolute, inside the cache), `seconds`; attribute `"cached"` (logical).

- [ ] **Step 1: Write the failing tests.** Helpers first (top of the new block in `tests/testthat/test-manim.R`):

```r
manim_fixture <- function(dir = withr::local_tempdir(.local_envir = parent.frame())) {
  dir.create(file.path(dir, "scenes", "data"), recursive = TRUE)
  writeLines("class Tiny: pass", file.path(dir, "scenes", "tiny.py"))
  writeLines("def helper(): pass", file.path(dir, "scenes", "util.py"))
  writeLines("x,y\n1,2", file.path(dir, "scenes", "data", "d.csv"))
  cfg <- lecturecast_config(config = write_config(c("voice:", "  provider: edge"), dir = dir))
  spec <- list(file = "scenes/tiny.py", scene = "Tiny", inputs = "data/d.csv", fill = "box")
  list(dir = dir, cfg = cfg, spec = spec, paths = lc_manim_paths(spec, cfg))
}

# A fake manim run: writes two coloured section videos and a section list in
# the form Task 0 recorded.
fake_manim_run <- function(paths, spec, rect, cfg, media) {
  out <- file.path(media, "videos", "tiny", "fake", "sections")
  dir.create(out, recursive = TRUE)
  for (k in 1:2) {
    processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi",
                              "-i", sprintf("color=c=%s:s=%dx%d:r=%s:d=0.5", c("red", "blue")[k], rect[["w"]], rect[["h"]], cfg$video$fps),
                              "-pix_fmt", "yuv420p", file.path(out, sprintf("Tiny_%04d.mp4", k))))
  }
  json <- file.path(out, "Tiny.json")
  writeLines('[{"name": "autocreated", "video": null},
               {"name": "grow", "video": "Tiny_0001.mp4"},
               {"name": "spin", "video": "Tiny_0002.mp4"}]', json)
  json
}
```

Tests:

```r
test_that("the render key ignores notes but follows every input to the pictures", {
  local_mocked_bindings(lc_manim_engine = function() "manim==test")
  f <- manim_fixture()
  rect <- c(x = 0L, y = 0L, w = 640L, h = 360L)
  k <- lc_manim_key(f$paths, f$spec, rect, f$cfg)
  expect_equal(k, lc_manim_key(f$paths, f$spec, rect, f$cfg))
  expect_false(k == lc_manim_key(f$paths, f$spec, c(x = 0L, y = 0L, w = 1280L, h = 720L), f$cfg))
  expect_false(k == lc_manim_key(f$paths, modifyList(f$spec, list(scene = "Other")), rect, f$cfg))
  cfg2 <- f$cfg; cfg2$video$fps <- 60
  expect_false(k == lc_manim_key(f$paths, f$spec, rect, cfg2))
  cfg3 <- f$cfg; cfg3$manim$background <- "#000000"
  expect_false(k == lc_manim_key(f$paths, f$spec, rect, cfg3))
  writeLines("def helper(): return 1", file.path(f$dir, "scenes", "util.py"))
  k2 <- lc_manim_key(f$paths, f$spec, rect, f$cfg)
  expect_false(k == k2)
  writeLines("x,y\n1,3", file.path(f$dir, "scenes", "data", "d.csv"))
  expect_false(k2 == lc_manim_key(f$paths, f$spec, rect, f$cfg))
})

test_that("the section list keeps sections with video, in scene order", {
  dir <- withr::local_tempdir()
  json <- file.path(dir, "Tiny.json")
  writeLines('[{"name": "autocreated", "video": null}, {"name": "grow", "video": "Tiny_0001.mp4"}]', json)
  s <- lc_manim_sections(json, list(scene = "Tiny"), "tiny.py")
  expect_equal(s$name, "grow")
  expect_equal(s$file, file.path(dir, "Tiny_0001.mp4"))
})

test_that("a scene with no animations or duplicate names stops", {
  dir <- withr::local_tempdir()
  json <- file.path(dir, "Tiny.json")
  writeLines('[{"name": "autocreated", "video": null}]', json)
  expect_error(lc_manim_sections(json, list(scene = "Tiny"), "tiny.py"), "has no animations")
  writeLines('[{"name": "Grow", "video": "a.mp4"}, {"name": "grow.", "video": "b.mp4"}]', json)
  expect_error(lc_manim_sections(json, list(scene = "Tiny"), "tiny.py"), "two sections named")
  writeLines('{"unexpected": true}', json)
  expect_error(lc_manim_sections(json, list(scene = "Tiny"), "tiny.py"), "not in the form")
})

test_that("a render is stored once and reused", {
  skip_if_no_ffmpeg()
  local_mocked_bindings(lc_manim_engine = function() "manim==test")
  f <- manim_fixture()
  cache <- withr::local_tempdir()
  calls <- 0
  local_mocked_bindings(lc_manim_run = function(...) { calls <<- calls + 1; fake_manim_run(...) })
  rect <- c(x = 0L, y = 0L, w = 320L, h = 180L)
  a <- lc_manim_render(f$paths, f$spec, rect, f$cfg, cache)
  b <- lc_manim_render(f$paths, f$spec, rect, f$cfg, cache)
  expect_equal(calls, 1)
  expect_false(attr(a, "cached"))
  expect_true(attr(b, "cached"))
  expect_equal(b$name, c("grow", "spin"))
  expect_equal(b$seconds, c(0.5, 0.5), tolerance = 0.05)
  expect_true(all(startsWith(b$file, file.path(cache, "manim"))))
})

test_that("a render of the wrong size stops the build", {
  skip_if_no_ffmpeg()
  local_mocked_bindings(lc_manim_engine = function() "manim==test")
  f <- manim_fixture()
  local_mocked_bindings(lc_manim_run = function(paths, spec, rect, cfg, media) {
    fake_manim_run(paths, spec, c(x = 0L, y = 0L, w = 200L, h = 100L), cfg, media)
  })
  expect_error(lc_manim_render(f$paths, f$spec, c(x = 0L, y = 0L, w = 320L, h = 180L), f$cfg, withr::local_tempdir()),
               "Manim rendered 200x100, expected 320x180")
})

test_that("a damaged cached render stops with the folder to delete", {
  skip_if_no_ffmpeg()
  local_mocked_bindings(lc_manim_engine = function() "manim==test")
  f <- manim_fixture()
  cache <- withr::local_tempdir()
  local_mocked_bindings(lc_manim_run = fake_manim_run)
  rect <- c(x = 0L, y = 0L, w = 320L, h = 180L)
  r <- lc_manim_render(f$paths, f$spec, rect, f$cfg, cache)
  file.remove(r$file[2])
  expect_error(lc_manim_render(f$paths, f$spec, rect, f$cfg, cache), "cached section video is missing")
})

test_that("a failed manim run shows its error and the fix", {
  f <- manim_fixture()
  local_mocked_bindings(lc_manim_command = function() c("/bin/sh", "-c", "echo 'LaTeX error: latex not found' >&2; exit 1", "manim"))
  err <- expect_error(lc_manim_run(f$paths, f$spec, c(x = 0L, y = 0L, w = 320L, h = 180L), f$cfg, withr::local_tempdir()),
                      "latex not found")
  expect_match(conditionMessage(err), "lecturecast_check", fixed = TRUE)
})

test_that("a run that writes no section list names the class", {
  f <- manim_fixture()
  local_mocked_bindings(lc_manim_command = function() c("/bin/sh", "-c", "exit 0", "manim"))
  expect_error(lc_manim_run(f$paths, f$spec, c(x = 0L, y = 0L, w = 320L, h = 180L), f$cfg, withr::local_tempdir()),
               "wrote no section list for scene Tiny")
})
```

Note: the `/bin/sh -c` mock works because `lc_manim_run()` passes `cmd[-1]` before its own arguments; `sh -c 'script' manim render ...` ignores the extra arguments. Skip these two tests on Windows (`skip_on_os("windows")`).

- [ ] **Step 2: Run to see them fail**

Run: `Rscript -e 'devtools::test(filter = "manim")'`
Expected: FAIL, `could not find function "lc_manim_key"`.

- [ ] **Step 3: Implement** (append to `R/manim.R`; adjust flag spellings and the section-list form to what Task 0 recorded):

```r
# The render cache key: everything that changes the pictures. Every .py file
# beside the scene counts, so a change to a helper module re-renders.
lc_manim_key <- function(paths, spec, rect, cfg) {
  py <- sort(list.files(dirname(paths$scene), pattern = "\\.py$", full.names = TRUE))
  hashes <- function(f, nm) stats::setNames(as.list(vapply(f, cli::hash_file_sha256, "", USE.NAMES = FALSE)), nm)
  parts <- list(
    engine = lc_manim_engine(), scene = spec$scene, file = basename(paths$scene),
    py = hashes(py, basename(py)), inputs = hashes(paths$inputs, spec$inputs),
    w = rect[["w"]], h = rect[["h"]], fps = cfg$video$fps, background = cfg$manim$background
  )
  cli::hash_sha256(as.character(jsonlite::toJSON(parts, auto_unbox = TRUE, null = "null")))
}

# Run Manim on one scene and return the path of its section list.
lc_manim_run <- function(paths, spec, rect, cfg, media) {
  step <- "manim"
  cmd <- lc_manim_command()
  args <- c(cmd[-1], "render", "--save_sections", "--format", "mp4", "--disable_caching",
            "--progress_bar", "none",
            "--resolution", sprintf("%d,%d", rect[["w"]], rect[["h"]]),
            "--frame_rate", as.character(cfg$video$fps), "--media_dir", media,
            if (!is.null(cfg$manim$background)) c("--background_color", cfg$manim$background),
            basename(paths$scene), spec$scene)
  lc_run(cmd[1], args, step = step, file = paths$scene, timeout = cfg$manim$timeout, wd = dirname(paths$scene),
         fix = "Run the scene with manim in a terminal to see the whole error. For math text, check latex and dvisvgm with lecturecast_check().")
  json <- list.files(media, pattern = paste0("^", spec$scene, "\\.json$"), recursive = TRUE, full.names = TRUE)
  json <- json[basename(dirname(json)) == "sections"]
  if (length(json) != 1) {
    lc_abort(step, sprintf("Manim finished but wrote no section list for scene %s.", spec$scene), file = paths$scene,
             fix = "Check that scene= names a Scene class in the file.")
  }
  json
}

# Manim's section list as name and video file, in scene order. Sections with
# no animation have no video and are dropped.
lc_manim_sections <- function(json, spec, scene_file) {
  step <- "manim"
  x <- tryCatch(jsonlite::fromJSON(json), error = function(e) NULL)
  if (!is.data.frame(x) || !all(c("name", "video") %in% names(x))) {
    lc_abort(step, "Manim's section list is not in the form lecturecast expects.", file = json,
             fix = paste0("lecturecast is tested with Manim ", lc_manim_version, "."))
  }
  x <- x[!is.na(x$video) & nzchar(x$video), , drop = FALSE]
  if (nrow(x) == 0) {
    lc_abort(step, sprintf("Scene %s has no animations, so there is nothing to play.", spec$scene), file = scene_file)
  }
  dup <- duplicated(lc_label_key(x$name))
  if (any(dup)) {
    lc_abort(step, sprintf("Scene %s has two sections named \"%s\"; cue names must differ.", spec$scene, x$name[dup][1]),
             file = scene_file)
  }
  data.frame(name = x$name, file = file.path(dirname(json), x$video), stringsAsFactors = FALSE)
}

# Render a scene's sections, or reuse them from the cache. The render is
# copied into a temporary folder with its index, then the folder is renamed
# into place, so an index file marks a finished entry.
lc_manim_render <- function(paths, spec, rect, cfg, cache) {
  step <- "manim"
  key <- lc_manim_key(paths, spec, rect, cfg)
  dir <- file.path(cache, "manim", key)
  index <- file.path(dir, "sections.json")
  if (file.exists(index)) return(structure(lc_manim_cached(dir, index), cached = TRUE))
  tmp <- paste0(dir, ".tmp")
  unlink(tmp, recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  json <- lc_manim_run(paths, spec, rect, cfg, lc_dir_create(file.path(tmp, "media")))
  secs <- lc_manim_sections(json, spec, paths$scene)
  out <- lc_dir_create(file.path(tmp, "out"))
  stored <- sprintf("%03d.mp4", seq_len(nrow(secs)))
  if (!all(file.copy(secs$file, file.path(out, stored)))) lc_abort(step, "Could not copy the rendered sections.", file = out)
  for (f in file.path(out, stored)) {
    wh <- lc_dimensions(f, step)
    if (!identical(wh, unname(c(rect[["w"]], rect[["h"]])))) {
      lc_abort(step, sprintf("Manim rendered %dx%d, expected %dx%d.", wh[1], wh[2], rect[["w"]], rect[["h"]]), file = f)
    }
  }
  secs$seconds <- vapply(file.path(out, stored), lc_duration, numeric(1), step = step, USE.NAMES = FALSE)
  secs$file <- stored
  writeLines(jsonlite::toJSON(list(scene = spec$scene, sections = secs), dataframe = "rows", auto_unbox = TRUE, digits = NA),
             file.path(out, "sections.json"))
  lc_dir_create(dirname(dir))
  if (!file.rename(out, dir)) lc_abort(step, "Could not store the render in the cache.", file = dir)
  secs$file <- file.path(dir, stored)
  structure(secs, cached = FALSE)
}

lc_manim_cached <- function(dir, index) {
  step <- "manim (cache)"
  fix <- paste0("Delete the folder ", dir, " and build again; the scene will be rendered afresh.")
  m <- tryCatch(jsonlite::fromJSON(index), error = function(e) lc_abort(step, "The cached render is damaged.", file = index, fix = fix))
  secs <- m$sections
  if (!is.data.frame(secs) || nrow(secs) == 0 || !all(c("name", "file", "seconds") %in% names(secs))) {
    lc_abort(step, "The cached render is damaged.", file = index, fix = fix)
  }
  secs$file <- file.path(dir, secs$file)
  for (k in seq_len(nrow(secs))) {
    if (!file.exists(secs$file[k])) lc_abort(step, "A cached section video is missing.", file = secs$file[k], fix = fix)
    d <- lc_duration(secs$file[k], step)
    if (abs(d - secs$seconds[k]) > 0.05) {
      lc_abort(step, "A cached section video is not the length recorded for it.", file = secs$file[k], fix = fix)
    }
  }
  secs[, c("name", "file", "seconds")]
}
```

- [ ] **Step 4: Run to see them pass**

Run: `Rscript -e 'devtools::test(filter = "manim")'`
Expected: PASS.

- [ ] **Step 5: Commit** (with Logan's approval)

```bash
git add R/manim.R tests/testthat/test-manim.R
git commit -m "Phase 4c: render Manim sections through a checked cache"
```

---

### Task 5: Frames, stills and the clip

**Files:**
- Modify: `R/manim.R`
- Test: `tests/testthat/test-manim.R`

**Interfaces:**
- Consumes: `lc_run`, `lc_tool`, `lc_duration`, `lc_dimensions`, `lc_ffmpeg_video_args` (`R/assemble.R`), `lc_resolutions`; a schedule from `lc_animation_schedule()` (`list(files, seconds, total)`).
- Produces:
  - `lc_frames(video, dir, prefix, fps)` -> `list(files = chr, seconds = 1 / fps)`.
  - `lc_overlay_png(base, top, rect, out)` -> `out`.
  - `lc_manim_clip(schedule, base, rect, out, cfg, audio = NULL)` -> clip duration in seconds.

- [ ] **Step 1: Write the failing tests:**

```r
ff <- function(...) processx::run("ffmpeg", c("-y", "-loglevel", "error", ...))

# RGB of one pixel of an image or the first frame of a video.
pixel <- function(file, x, y) {
  raw <- tempfile(fileext = ".rgb")
  ff("-i", file, "-frames:v", "1", "-vf", sprintf("crop=1:1:%d:%d,format=rgb24", x, y), "-f", "rawvideo", raw)
  as.integer(readBin(raw, "raw", 3))
}

test_that("every frame of a section becomes a picture", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  v <- file.path(dir, "s.mp4")
  ff("-f", "lavfi", "-i", "testsrc=s=160x90:r=10:d=1", "-pix_fmt", "yuv420p", v)
  fr <- lc_frames(v, file.path(dir, "frames"), "s01-001", 10)
  expect_length(fr$files, 10)
  expect_equal(fr$seconds, 0.1)
})

test_that("a still lays the scene frame over the slide at the box", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  base <- file.path(dir, "base.png"); top <- file.path(dir, "top.png")
  ff("-f", "lavfi", "-i", "color=c=white:s=320x180", "-frames:v", "1", base)
  ff("-f", "lavfi", "-i", "color=c=red:s=80x60", "-frames:v", "1", top)
  out <- lc_overlay_png(base, top, c(x = 100L, y = 40L, w = 80L, h = 60L), file.path(dir, "out.png"))
  inside <- pixel(out, 140, 70); outside <- pixel(out, 10, 10)
  expect_gt(inside[1], 200); expect_lt(inside[2], 60)
  expect_true(all(outside > 200))
})

test_that("a Manim clip has the scene in its box, the narration and the planned length", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  cfg <- lecturecast_config(config = write_config(c("voice:", "  provider: edge", "video:", "  resolution: 720p", "  lead_in: 0.3"), dir = dir))
  base <- file.path(dir, "base.png"); top <- file.path(dir, "top.png"); audio <- file.path(dir, "a.mp3")
  ff("-f", "lavfi", "-i", "color=c=white:s=1280x720", "-frames:v", "1", base)
  ff("-f", "lavfi", "-i", "color=c=blue:s=400x200", "-frames:v", "1", top)
  ff("-f", "lavfi", "-i", "sine=duration=1", audio)
  sched <- list(files = top, seconds = 2, total = 2)
  rect <- c(x = 100L, y = 100L, w = 400L, h = 200L)
  d <- lc_manim_clip(sched, base, rect, file.path(dir, "clip.mp4"), cfg, audio = audio)
  expect_equal(d, 2, tolerance = 0.1)
  expect_equal(lc_dimensions(file.path(dir, "clip.mp4"), "t"), c(1280L, 720L))
  expect_gt(pixel(file.path(dir, "clip.mp4"), 300, 200)[3], 180)
  expect_true(all(pixel(file.path(dir, "clip.mp4"), 50, 50) > 200))
  silent <- lc_manim_clip(sched, base, rect, file.path(dir, "silent.mp4"), cfg)
  expect_equal(silent, 2, tolerance = 0.1)
})
```

- [ ] **Step 2: Run to see them fail**

Run: `Rscript -e 'devtools::test(filter = "manim")'`
Expected: FAIL, `could not find function "lc_frames"`.

- [ ] **Step 3: Implement** (append to `R/manim.R`):

```r
# Every frame of a section video as PNG files, each shown for 1 / fps.
lc_frames <- function(video, dir, prefix, fps) {
  step <- "manim"
  lc_dir_create(dir)
  lc_run(lc_tool("ffmpeg", step),
         c("-y", "-hide_banner", "-loglevel", "error", "-i", video, "-vf", sprintf("fps=%s", fps),
           file.path(dir, paste0(prefix, "-%05d.png"))),
         step = step, file = video, timeout = 600)
  files <- sort(list.files(dir, pattern = paste0("^", prefix, "-[0-9]{5}\\.png$"), full.names = TRUE))
  if (length(files) == 0) lc_abort(step, "No frames could be read from the section video.", file = video)
  list(files = files, seconds = 1 / fps)
}

# One scene frame laid over the slide capture at the box, as a PNG. These
# are the pictures the fades between slides start from and end on.
lc_overlay_png <- function(base, top, rect, out) {
  step <- "manim"
  lc_run(lc_tool("ffmpeg", step),
         c("-y", "-hide_banner", "-loglevel", "error", "-i", base, "-i", top,
           "-filter_complex", sprintf("[0:v][1:v]overlay=%d:%d", rect[["x"]], rect[["y"]]), "-frames:v", "1", out),
         step = step, file = out, timeout = 60)
  lc_dimensions(out, step)
  out
}

# A clip of the slide capture with a schedule of scene frames laid over it
# at the box. With audio the narration starts after the lead-in; without,
# the clip is silent.
lc_manim_clip <- function(schedule, base, rect, out, cfg, audio = NULL) {
  step <- "assemble"
  v <- cfg$video
  wh <- lc_resolutions[[v$resolution]]
  list_file <- paste0(out, ".txt")
  on.exit(unlink(list_file), add = TRUE)
  esc <- gsub("'", "'\\\\''", normalizePath(schedule$files))
  body <- as.vector(rbind(paste0("file '", esc, "'"), sprintf("duration %.4f", schedule$seconds)))
  # The concat demuxer needs the last picture listed again to honour its duration.
  writeLines(c("ffconcat version 1.0", body, paste0("file '", esc[length(esc)], "'")), list_file)
  if (is.null(audio)) {
    audio_in <- c("-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo")
    afilter <- "[2:a]anull[a]"
  } else {
    audio_in <- c("-i", audio)
    afilter <- sprintf("[2:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,adelay=%d:all=1,apad[a]",
                       round(v$lead_in * 1000))
  }
  graph <- paste(
    sprintf("[0:v]scale=%d:%d:flags=lanczos,setsar=1,fps=%s[bg]", wh[1], wh[2], v$fps),
    sprintf("[1:v]fps=%s,setsar=1[fg]", v$fps),
    sprintf("[bg][fg]overlay=%d:%d:eof_action=repeat,format=yuv420p[v]", rect[["x"]], rect[["y"]]),
    afilter, sep = ";")
  args <- c("-y", "-hide_banner", "-loglevel", "error",
            "-loop", "1", "-framerate", as.character(v$fps), "-i", base,
            "-f", "concat", "-safe", "0", "-i", list_file,
            audio_in,
            "-filter_complex", graph, "-map", "[v]", "-map", "[a]",
            "-t", sprintf("%.3f", schedule$total), lc_ffmpeg_video_args(v$fps), out)
  lc_run(lc_tool("ffmpeg", step), args, step = step, file = out, timeout = 900)
  got <- lc_duration(out, step)
  if (abs(got - schedule$total) > 0.2) {
    lc_abort(step, sprintf("Manim clip is %.2f s long, expected %.2f s.", got, schedule$total), file = out)
  }
  got
}
```

- [ ] **Step 4: Run to see them pass**

Run: `Rscript -e 'devtools::test(filter = "manim")'`
Expected: PASS.

- [ ] **Step 5: Commit** (with Logan's approval)

```bash
git add R/manim.R tests/testthat/test-manim.R
git commit -m "Phase 4c: Manim frames laid over the slide capture"
```

---

### Task 6: Wire it into build_video()

**Files:**
- Modify: `R/build.R` (`build_video`)
- Create: `tests/testthat/fixtures/manim/scene.py`, `tests/testthat/fixtures/manim/manim.qmd`
- Create: `tests/testthat/test-manim-integration.R`

**Interfaces:**
- Consumes: everything from Tasks 2 to 5, plus `lc_animation_schedule()` unchanged.
- Produces: `build_video()` handles `.manim` slides; its return value's `segments` gains column `base` (the slide capture before compositing).

- [ ] **Step 1: Write the fixtures.**

`tests/testthat/fixtures/manim/scene.py`:

```python
from manim import *


class Tiny(Scene):
    def construct(self):
        sq = Square(color=BLUE, fill_opacity=0.5)
        self.play(Create(sq), run_time=0.5)
        self.next_section("grow")
        self.play(sq.animate.scale(1.5), run_time=0.5)
        self.next_section("spin")
        self.play(Rotate(sq, PI / 4), run_time=0.5)
```

`tests/testthat/fixtures/manim/manim.qmd`:

```markdown
---
title: "Manim fixture"
format:
  revealjs:
    embed-resources: true
---

## Title {data-silent="1"}

## In a box

::: {.manim file="scene.py" scene="Tiny" style="width: 100%; height: 300px;"}
:::

::: notes
First the square. Now "grow" it. Then "spin" it.
:::

## Full frame {data-silent="1"}

::: {.manim file="scene.py" scene="Tiny" fill="frame"}
:::
```

- [ ] **Step 2: Write the failing integration tests** in `tests/testthat/test-manim-integration.R`:

```r
# End to end. Needs Quarto, Chrome and FFmpeg, so it runs locally and is
# skipped on CRAN and in CI. The first test fakes Manim; the second runs it.
manim_deck <- function(dir) {
  file.copy(test_path("fixtures", "manim", c("manim.qmd", "scene.py")), dir)
  processx::run("quarto", c("render", "manim.qmd"), wd = dir)
  rec <- file.path(dir, "audio", "manim")
  dir.create(rec, recursive = TRUE)
  processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=duration=2", file.path(rec, "s02.wav")))
  write_config(c("voice:", "  provider: recorded", "  recorded_dir: audio",
                 "video:", "  resolution: 720p", "  crossfade: 0"), dir = dir)
  file.path(dir, "manim.html")
}

skip_if_no_deck_tools <- function() {
  skip_on_cran()
  skip_on_ci()
  skip_if_no_ffmpeg()
  skip_if(!nzchar(Sys.which("quarto")), "Quarto not installed")
  skip_if(!nzchar(lc_find_chrome()), "Chrome not found")
}

test_that("a deck with boxed and full-frame scenes builds (Manim faked)", {
  skip_if_no_deck_tools()
  dir <- withr::local_tempdir()
  deck <- manim_deck(dir)
  local_mocked_bindings(lc_manim_engine = function() "manim==test", lc_manim_run = fake_manim_run)
  msgs <- testthat::capture_messages(
    r <- build_video(deck, config = file.path(dir, "lecturecast.yml"), out_dir = file.path(dir, "out"),
                     cache_dir = file.path(dir, "cache"))
  )
  expect_true(all(file.exists(c(r$video, r$captions, r$transcript))))
  expect_equal(lc_dimensions(r$video, "t"), c(1280L, 720L))
  # Slide 2: 0.3 lead-in + 2 s narration + 0.5 tail; the two 0.5 s sections fit inside.
  # Slide 3: silent 1 s, but its scene runs 0.3 + 1 + 0.5 = 1.8 s.
  expect_equal(r$seconds, 1 + 2.8 + 1.8, tolerance = 0.3)
  expect_true(any(grepl("Slide 2: scene Tiny, 2 sections, 2 cued", msgs, fixed = TRUE)))
  expect_true(any(grepl("Slide 3: scene Tiny, 2 sections, 0 cued", msgs, fixed = TRUE)))
  # The boxed scene renders at the box's size, the full-frame one at 1280x720.
  sizes <- vapply(list.files(file.path(dir, "cache", "manim"), full.names = TRUE), function(d) {
    paste(lc_dimensions(file.path(d, "001.mp4"), "t"), collapse = "x")
  }, "")
  expect_true("1280x720" %in% sizes)
  expect_length(sizes, 2)
})

test_that("a second build reuses the renders", {
  skip_if_no_deck_tools()
  dir <- withr::local_tempdir()
  deck <- manim_deck(dir)
  calls <- 0
  local_mocked_bindings(lc_manim_engine = function() "manim==test",
                        lc_manim_run = function(...) { calls <<- calls + 1; fake_manim_run(...) })
  for (k in 1:2) build_video(deck, config = file.path(dir, "lecturecast.yml"), out_dir = file.path(dir, "out"),
                             cache_dir = file.path(dir, "cache"), quiet = TRUE)
  expect_equal(calls, 2)
})

test_that("the fixture deck builds with real Manim", {
  skip_if_no_deck_tools()
  skip_if(!nzchar(lc_find_manim()), "Manim not available")
  dir <- withr::local_tempdir()
  deck <- manim_deck(dir)
  r <- build_video(deck, config = file.path(dir, "lecturecast.yml"), out_dir = file.path(dir, "out"),
                   cache_dir = file.path(dir, "cache"), quiet = TRUE)
  expect_true(file.exists(r$video))
  # Real Manim also saves the opening Create as a section, so the silent
  # slide's scene runs 0.3 + 1.5 + 0.5 = 2.3 s.
  expect_equal(r$seconds, 1 + 2.8 + 2.3, tolerance = 0.3)
})
```

`fake_manim_run` is defined in `test-manim.R`; move it and `manim_fixture` into `tests/testthat/helper.R` so both files see it.

- [ ] **Step 3: Run to see them fail**

Run: `Rscript -e 'devtools::test(filter = "manim-integration")'`
Expected: FAIL: the boxed slide's video shows an empty slide and the messages are missing (no Manim handling yet).

- [ ] **Step 4: Implement in `R/build.R`.** Four edits.

(a) After `segs <- lc_segments(...)` and its `lc_say`, read every slide's scene before anything costs money:

```r
  # Manim scenes: read and check every slide's div before voicing anything.
  manim <- lapply(seq_len(nrow(slides)), function(k) lc_manim_spec(slides$manim[[k]], k, deck))
  manim_paths <- lapply(manim, function(m) if (is.null(m)) NULL else lc_manim_paths(m, cfg))
  for (k in which(!vapply(manim, is.null, logical(1)))) {
    if (nrow(slides$buttons[[k]]) > 0) {
      lc_abort("manim", sprintf("Slide %d holds a Manim scene and a Plotly chart with buttons; a slide can animate one or the other.", k),
               file = deck)
    }
  }
  manim_rect <- list()
```

(b) In the capture loop, right after `lc_screenshot(b, segs$png[i], wh[1], wh[2], deck)`:

```r
    m <- manim[[segs$slide[i]]]
    if (!is.null(m)) {
      key <- as.character(segs$slide[i])
      if (is.null(manim_rect[[key]])) manim_rect[[key]] <- lc_manim_rect(b, m, wh, deck, segs$slide[i])
      next
    }
```

(c) After `lc_done(quiet, sprintf("Captured %d slide states ...` (Chrome is closed by then), add:

```r
  # Manim scenes render after Chrome closes. For each scene slide: render
  # (or reuse), plan which sections play at which cue, split them into
  # frames, and composite the first and last picture of each segment.
  segs$base <- segs$png
  mevents <- vector("list", nrow(segs))
  mcaptured <- vector("list", nrow(segs))
  mstill <- rep(NA_character_, nrow(segs))
  mout <- rep(NA_character_, nrow(segs))
  for (key in names(manim_rect)) {
    k <- as.integer(key)
    rect <- manim_rect[[key]]
    rows <- which(segs$slide == k)
    secs <- lc_manim_render(manim_paths[[k]], manim[[k]], rect, cfg, cache)
    runs <- lc_manim_runs(ifelse(is.na(segs$silent[rows]), segs$text[rows], ""), secs$name, k, deck)
    frames <- lapply(seq_len(nrow(secs)), function(j) {
      lc_frames(secs$file[j], file.path(work, "png", "manim"), sprintf("slide%03d-%03d", k, j), cfg$video$fps)
    })
    top <- frames[[1]]$files[1]
    for (r in seq_along(rows)) {
      i <- rows[r]
      mstill[i] <- top
      mine <- runs[runs$seg == r, , drop = FALSE]
      if (nrow(mine)) {
        mevents[[i]] <- data.frame(label = secs$name[mine$from], pos = mine$pos, stringsAsFactors = FALSE)
        mcaptured[[i]] <- lapply(seq_len(nrow(mine)), function(j) {
          fr <- frames[mine$from[j]:mine$to[j]]
          list(label = secs$name[mine$from[j]], files = unlist(lapply(fr, function(x) x$files)), seconds = 1 / cfg$video$fps)
        })
        last <- mcaptured[[i]][[nrow(mine)]]$files
        top <- last[length(last)]
      }
      segs$png[i] <- lc_overlay_png(segs$base[i], mstill[i], rect, file.path(work, "png", paste0(segs$id[i], "-in.png")))
      mout[i] <- lc_overlay_png(segs$base[i], top, rect, file.path(work, "png", paste0(segs$id[i], "-out.png")))
    }
    lc_done(quiet, sprintf("Slide %d: scene %s, %d sections, %d cued in the notes%s.", k, manim[[k]]$scene, nrow(secs),
                           sum(runs$cued), if (isTRUE(attr(secs, "cached"))) " (render reused from the cache)" else ""))
  }
```

(d) In the clip loop, make the Manim branch come first:

```r
    segs$clip_seconds[i] <- if (!is.na(mstill[i])) {
      silent <- !is.na(segs$silent[i])
      mcfg <- cfg
      # A silent slide has no sentences to pace against.
      if (silent) mcfg$video$animation_pace <- "deck"
      a_dur <- if (silent) max(0, segs$silent[i] - cfg$video$lead_in - cfg$video$tail) else segs$audio_seconds[i]
      ev <- mevents[[i]] %||% data.frame(label = character(0), pos = numeric(0))
      sched <- lc_animation_schedule(mstill[i], ev, mcaptured[[i]], if (silent) "" else segs$text[i],
                                     timings[[i]], a_dur, mcfg)
      lc_manim_clip(sched, segs$base[i], manim_rect[[as.character(segs$slide[i])]], segs$clip[i], cfg,
                    audio = if (silent) NULL else segs$audio[i])
    } else if (!is.null(events[[i]])) {
```

(the existing Plotly, voiced-still and silent-still branches follow unchanged), and after the existing `segs$png_out <- vapply(...)` line:

```r
  segs$png_out[!is.na(mout)] <- mout[!is.na(mout)]
```

- [ ] **Step 5: Run to see them pass**

Run: `Rscript -e 'devtools::test(filter = "manim")'` then the whole suite `Rscript -e 'devtools::test()'`.
Expected: PASS, including the existing integration test for fragments.

- [ ] **Step 6: Commit** (with Logan's approval)

```bash
git add R/build.R tests/testthat/helper.R tests/testthat/test-manim.R tests/testthat/test-manim-integration.R tests/testthat/fixtures/manim
git commit -m "Phase 4c: Manim scenes in build_video, boxed or full frame"
```

---

### Task 7: Data from R, the examples and the vignette

**Files:**
- Create: `inst/examples/manim/lecturecast.yml`, `inst/examples/manim/scenes.qmd`, `inst/examples/manim/scenes/demand.py`, `inst/examples/manim/scenes/clt.py`
- Create: `vignettes/manim.Rmd`

**Interfaces:**
- Consumes: the finished feature. No new R functions: the data handoff is the instructor's own R chunk writing a CSV, plus `inputs=` so the cache follows it.

- [ ] **Step 1: Write the example deck** `inst/examples/manim/scenes.qmd`:

````markdown
---
title: "Two animated scenes"
format: revealjs
---

```{r}
#| include: false
# The scenes read these files. Writing them here keeps the numbers in the
# same pipeline as the rest of the deck.
dir.create("scenes/data", recursive = TRUE, showWarnings = FALSE)
curves <- data.frame(curve = c("supply", "demand", "demand_new"),
                     intercept = c(1, 9, 11), slope = c(0.8, -0.8, -0.8))
write.csv(curves, "scenes/data/curves.csv", row.names = FALSE)
set.seed(730)
means <- data.frame(mean = replicate(200, mean(rexp(30, rate = 1 / 3))))
write.csv(means, "scenes/data/means.csv", row.names = FALSE)
```

## A rise in income

::: {.manim file="scenes/demand.py" scene="DemandShift" inputs="data/curves.csv" style="width: 100%; height: 520px;"}
:::

::: notes
Start from a market in balance, where supply meets demand. When incomes rise, "demand shifts right". The new balance sits up and to the right, so "price and quantity rise" together.
:::

## Where the bell curve comes from

::: {.manim file="scenes/clt.py" scene="SampleMeans" inputs="data/means.csv" fill="frame"}
:::

::: notes
Each block is the average of one sample of thirty. "Draw a sample" and its average lands in a bin. Now take "many more samples". The averages pile up in "the bell shape", even though the data behind them are skewed.
:::
````

`inst/examples/manim/lecturecast.yml`:

```yaml
voice:
  provider: edge
  narrator: en-US-AndrewNeural
video:
  resolution: 1080p
```

- [ ] **Step 2: Write the scenes** (fix any API error Task 0, Step 7 recorded).

`inst/examples/manim/scenes/demand.py`:

```python
import csv
from pathlib import Path

from manim import *


def read_csv(name):
    with open(Path(__file__).parent / "data" / name, newline="") as f:
        return list(csv.DictReader(f))


class DemandShift(Scene):
    def construct(self):
        c = {r["curve"]: (float(r["intercept"]), float(r["slope"])) for r in read_csv("curves.csv")}
        ax = Axes(x_range=[0, 10, 2], y_range=[0, 10, 2], x_length=7, y_length=4.5, tips=False)
        labels = ax.get_axis_labels(Text("Quantity", font_size=24), Text("Price", font_size=24))

        def line(name, color):
            a, b = c[name]
            return ax.plot(lambda x: a + b * x, x_range=[0, 10], color=color)

        def equilibrium(name):
            (a1, b1), (a2, b2) = c["supply"], c[name]
            x = (a2 - a1) / (b1 - b2)
            return ax.c2p(x, a1 + b1 * x)

        supply = line("supply", BLUE)
        demand = line("demand", RED)
        dot = Dot(equilibrium("demand"), color=YELLOW)
        self.add(ax, labels)
        self.play(Create(supply), Create(demand), run_time=1.5)
        self.play(FadeIn(dot))

        self.next_section("demand shifts right")
        self.play(Transform(demand, line("demand_new", RED)), dot.animate.move_to(equilibrium("demand_new")), run_time=2)

        self.next_section("price and quantity rise")
        self.play(Create(ax.get_lines_to_point(dot.get_center(), color=GRAY)), run_time=1.5)
```

`inst/examples/manim/scenes/clt.py`:

```python
import csv
import math
from pathlib import Path

from manim import *


def read_csv(name):
    with open(Path(__file__).parent / "data" / name, newline="") as f:
        return list(csv.DictReader(f))


class SampleMeans(Scene):
    def construct(self):
        means = [float(r["mean"]) for r in read_csv("means.csv")]
        lo, hi, nbins = min(means), max(means), 20
        width = (hi - lo) / nbins
        bin_of = lambda m: min(int((m - lo) / width), nbins - 1)
        counts = [0] * nbins
        for m in means:
            counts[bin_of(m)] += 1
        ymax = max(counts) * 1.1
        ax = Axes(x_range=[lo, hi, (hi - lo) / 4], y_range=[0, ymax, max(1, round(ymax / 4))],
                  x_length=11, y_length=5.5, tips=False, axis_config={"include_numbers": False})
        title = Text("Averages of samples of 30", font_size=36).to_edge(UP)
        self.add(ax, title)

        heights = [0] * nbins

        def block(m):
            b = bin_of(m)
            heights[b] += 1
            return Rectangle(width=ax.x_axis.unit_size * width, height=ax.y_axis.unit_size,
                             stroke_width=0.5, fill_opacity=0.8, color=BLUE).move_to(
                ax.c2p(lo + (b + 0.5) * width, heights[b] - 0.5))

        self.next_section("draw a sample")
        for m in means[:8]:
            self.play(FadeIn(block(m), shift=DOWN), run_time=0.4)

        self.next_section("many more samples")
        self.play(LaggedStart(*[FadeIn(block(m)) for m in means[8:]], lag_ratio=0.02), run_time=4)

        self.next_section("the bell shape")
        mu = sum(means) / len(means)
        sd = (sum((m - mu) ** 2 for m in means) / (len(means) - 1)) ** 0.5
        scale = len(means) * width / (sd * math.sqrt(2 * math.pi))
        curve = ax.plot(lambda x: scale * math.exp(-((x - mu) / sd) ** 2 / 2), x_range=[lo, hi], color=YELLOW)
        self.play(Create(curve), run_time=2)
```

- [ ] **Step 3: Write the vignette** `vignettes/manim.Rmd`. Chunks are `eval = FALSE`, because CI has no Manim. No em-dashes.

````markdown
---
title: "Animated scenes with Manim"
output: rmarkdown::html_vignette
vignette: >
  %\VignetteIndexEntry{Animated scenes with Manim}
  %\VignetteEngine{knitr::rmarkdown}
  %\VignetteEncoding{UTF-8}
---

```{r, include = FALSE}
knitr::opts_chunk$set(eval = FALSE)
```

[Manim](https://www.manim.community/) is the Python animation library used
for the 3Blue1Brown videos. lecturecast can play a Manim scene on a slide and
start each part of it when the narration reaches a quoted phrase, the same
way it plays Plotly buttons. Use it when the motion is the idea: a curve
shifting, a distribution building up, an equation rearranging.

lecturecast keeps control of the voice, the timing and the captions. Manim
only draws the pictures.

## Setup

lecturecast runs Manim Community Edition through
[uv](https://docs.astral.sh/uv/), at a version fixed in the package, so
there is nothing to install beyond uv. A `manim` command on your PATH is
used instead when there is one. Scenes that use math text (`MathTex`) also
need LaTeX and `dvisvgm`. Check what is found with:

```{r}
lecturecast::lecturecast_check()
```

## A scene on a slide

Put a div with class `manim` on the slide. `file=` is relative to the folder
holding `lecturecast.yml`; `scene=` is the Python class. A scene in a box
needs a size:

```markdown
## A rise in income

::: {.manim file="scenes/demand.py" scene="DemandShift" style="width: 100%; height: 520px;"}
:::
```

In the scene, `self.next_section("name")` marks each place a cue can start:

```python
class DemandShift(Scene):
    def construct(self):
        ...
        self.play(Create(supply), Create(demand))
        self.next_section("demand shifts right")
        self.play(Transform(demand, demand_new))
        self.next_section("price and quantity rise")
        self.play(Create(guides))
```

In the speaker notes, quote a section's name where it should start:

```markdown
::: notes
When incomes rise, "demand shifts right". The new balance sits up and to
the right, so "price and quantity rise" together.
:::
```

The rules:

- Whatever the scene does before its first `next_section()` plays as the
  slide opens.
- A section starts when the narration reaches the first quote of its name.
  Case and trailing punctuation do not matter.
- A section that is never quoted plays straight after the one before it.
- Quotes must follow the scene's order. Quoting a section again later, as a
  reminder, does nothing.
- On a silent slide the whole scene plays, and the slide lasts as long as
  the scene.

The build prints how many sections each slide cued. If that number is lower
than you expect, check the spelling of the quotes.

## Explainer videos

For a 3Blue1Brown-style video, make a deck whose slides each hold one scene
that fills the whole frame, with the narration in the notes:

```markdown
## Where the bell curve comes from

::: {.manim file="scenes/clt.py" scene="SampleMeans" fill="frame"}
:::
```

`build_video()` treats it like any other deck, so the voice cache,
captions, transcript, title and end cards all work as usual. To set the
background of every scene, add to `lecturecast.yml`:

```yaml
manim:
  background: "#1e1e1e"
```

## Data from R

A scene can read data that an R chunk in the deck writes. The numbers then
come from the same code as the rest of the deck. Write a CSV next to the
scene in a hidden chunk:

```{r}
dir.create("scenes/data", recursive = TRUE, showWarnings = FALSE)
set.seed(730)
means <- data.frame(mean = replicate(200, mean(rexp(30, rate = 1 / 3))))
write.csv(means, "scenes/data/means.csv", row.names = FALSE)
```

Name the file in `inputs=` so a change to the data renders the scene again.
`inputs=` is relative to the scene's folder, which is also where the scene
opens it:

```markdown
::: {.manim file="scenes/clt.py" scene="SampleMeans" inputs="data/means.csv" fill="frame"}
:::
```

```python
import csv
from pathlib import Path

def read_csv(name):
    with open(Path(__file__).parent / "data" / name, newline="") as f:
        return list(csv.DictReader(f))
```

Render the deck with Quarto first, so the data exist, then build the video.

## The examples

The package ships a deck with one economics scene (a demand shift, in a box)
and one statistics scene (sample means building a bell curve, full frame):

```{r}
ex <- system.file("examples", "manim", package = "lecturecast")
file.copy(ex, tempdir(), recursive = TRUE)
dir <- file.path(tempdir(), "manim")
quarto::quarto_render(file.path(dir, "scenes.qmd"))
lecturecast::build_video(file.path(dir, "scenes.html"))
```

## When a build stops

- **Manim errors** are shown with the last lines of Manim's own message.
  Run the same scene with `manim` in a terminal to see all of it.
- **A box too small** means the div has no size. Give it a `style=` with a
  width and a height, or use `fill="frame"`.
- **Sections out of order** means the notes quote a later section before an
  earlier one.

Renders are cached by everything that changes the pictures: the scene
files, the data files, the size and the frame rate. Editing the notes or
changing the voice does not render a scene again.
````

- [ ] **Step 4: Check the package and the example**

Run: `Rscript -e 'devtools::document(); devtools::check()'`
Expected: 0 errors, 0 warnings, 0 notes.

Run a live build of the example in `work/manim-example/` (copy `inst/examples/manim` there, `quarto render scenes.qmd`, then `build_video("scenes.html", out_dir = "out")` with the Edge voice).
Expected: an MP4 where the demand curve shifts at "demand shifts right" and the blocks start falling at "Draw a sample". Watch it and note the timings in the ledger.

- [ ] **Step 5: Commit** (with Logan's approval)

```bash
git add inst/examples/manim vignettes/manim.Rmd
git commit -m "Phase 4c: example scenes, data from R, Manim vignette"
```

---

### Task 8: Review, plan and ledger

**Files:**
- Modify: `project/plans/2026-10-13-lecturecast-plan.md` (Phases list: add "4c. Manim scenes" after 4b, one line linking this plan)
- Modify: `project/plans/2026-10-13-ledger.md` (task log line for Phase 4c, rulings 1 to 8 above, Task 0 research)

- [ ] **Step 1: Whole-branch review.** A fresh reviewer reads this plan, the proposal, and `git diff main` for Phase 4c, and checks the Review Focus list against the tests.
- [ ] **Step 2: Fix what the review finds,** each with its test.
- [ ] **Step 3: Update the plan and ledger** as listed above. Ledger rulings are internal; em-dashes are fine there.
- [ ] **Step 4: `R CMD check --as-cran`** locally. Expected 0/0/0 (or the one known NOTE for the private repo URL).
- [ ] **Step 5: Commit** (with Logan's approval)

```bash
git add project/plans
git commit -m "Phase 4c: plan and ledger"
```

## Known limits (not in this phase)

- One scene per slide; no Manim and Plotly on the same slide.
- The live HTML deck shows an empty box where the scene goes; only the video has the animation.
- Frames are written as PNGs before assembly, which uses disk space for long full-frame scenes (about one PNG per frame). Fine for scenes of a minute or so; revisit if it bites.
- Scenes needing Python packages beyond Manim's own (pandas, scipy) are not supported yet; the examples use the standard `csv` module. A later `manim: packages:` setting could pass `--with` to uvx.
- Starter scenes (supply and demand, Keynesian cross, central limit theorem, least squares) are the next plan.
