# Manim scenes played on cue. A slide holds a div with class manim naming a
# scene file and class. Manim renders the scene once per size, one video per
# section (self.next_section("name")), and each section plays when the notes
# quote its name or a [play: name] tag reaches it. The scene is laid over the
# slide capture at the div's box, or over the whole frame with fill="frame".

lc_manim_version <- "0.22.0"

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
  if (isTRUE(m$fragment)) {
    lc_abort(step, sprintf("The Manim div on slide %d is inside a fragment; the scene would show before the fragment does.", slide),
             file = deck, fix = "Move the div out of the fragment. Use the scene's sections to reveal things in step with the notes.")
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
  # Manim's own message for a missing class goes to stdout, which lc_run
  # does not show, so check the name here and list what the file has.
  src <- readLines(scene, warn = FALSE)
  classes <- sub("^\\s*class\\s+([A-Za-z_][A-Za-z0-9_]*).*$", "\\1", grep("^\\s*class\\s+[A-Za-z_]", src, value = TRUE))
  if (!spec$scene %in% classes) {
    lc_abort(step, sprintf("The scene file has no class named %s.", spec$scene), file = scene,
             fix = if (length(classes)) paste0("scene= must name one of: ", paste(classes, collapse = ", "), ".")
                   else "scene= must name a Scene class defined in the file.")
  }
  # Passing lecturecast's background config makes Manim ignore a manim.cfg
  # beside the scene (Task 0), so the two cannot be used together.
  if (!is.null(cfg$manim$background) && file.exists(file.path(dirname(scene), "manim.cfg"))) {
    lc_abort(step, "lecturecast.yml sets manim: background:, and the scene's folder has a manim.cfg. Manim would ignore the manim.cfg.",
             file = file.path(dirname(scene), "manim.cfg"),
             fix = "Remove manim: background: from lecturecast.yml and put background_color = <colour> under [CLI] in manim.cfg.")
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

# Which sections play when, for one slide. `texts` holds the narration of
# the slide's segments in order ("" for silent ones), tags already removed.
# A segment with [play: name] tags is cued by its tags only, exactly; one
# without is cued by the first quote of each section's name. Sections
# nobody cues play straight on after the one before; sections before the
# first cue open the slide. Returns one row per run: its segment, cue
# position, first and last section, and how it was cued.
lc_manim_runs <- function(texts, names, slide, deck = NULL, tags = NULL) {
  key <- lc_label_key(names)
  cued <- data.frame(seg = integer(0), pos = numeric(0), sec = integer(0), tag = logical(0), over = logical(0))
  for (s in seq_along(texts)) {
    tg <- if (is.null(tags)) NULL else tags[[s]]
    if (!is.null(tg) && nrow(tg)) {
      for (k in seq_len(nrow(tg))) {
        hit <- match(lc_label_key(tg$label[k]), key)
        if (is.na(hit)) {
          lc_abort("script", sprintf("Slide %d has [play: %s], but scene has no section of that name.", slide, tg$label[k]),
                   file = deck, fix = paste0("Use one of the scene's sections: ", paste(sprintf("\"%s\"", names), collapse = ", "), "."))
        }
        if (hit %in% cued$sec) {
          lc_abort("script", sprintf("Slide %d plays section \"%s\" twice; a section plays once.", slide, names[hit]), file = deck)
        }
        cued <- rbind(cued, data.frame(seg = s, pos = tg$pos[k], sec = hit, tag = TRUE, over = isTRUE(tg$over[k])))
      }
      next
    }
    q <- lc_quotes(texts[s])
    for (k in seq_len(nrow(q))) {
      hit <- match(lc_label_key(q$phrase[k]), key)
      # A section already cued is a back-reference, not a second cue.
      if (is.na(hit) || hit %in% cued$sec) next
      cued <- rbind(cued, data.frame(seg = s, pos = q$pos[k], sec = hit, tag = FALSE, over = FALSE))
    }
  }
  if (is.unsorted(cued$sec, strictly = TRUE)) {
    lc_abort("manim", sprintf("Slide %d cues its scene's sections out of order (%s). They play in the order the scene defines them.",
                              slide, paste0("\"", names[cued$sec], "\"", collapse = ", ")), file = deck,
             fix = "Reorder the cues in the notes, or the next_section() calls in the scene.")
  }
  from <- sort(unique(c(1L, cued$sec)))
  to <- c(from[-1] - 1L, length(names))
  hit <- match(from, cued$sec)
  data.frame(seg = ifelse(is.na(hit), 1L, cued$seg[hit]),
             pos = ifelse(is.na(hit), 0, cued$pos[hit]),
             from = from, to = to, cued = !is.na(hit),
             tag = !is.na(hit) & cued$tag[hit] %in% TRUE,
             over = !is.na(hit) & cued$over[hit] %in% TRUE)
}

# The render cache key: everything that changes the pictures. Every .py file
# beside the scene counts, so a change to a helper module re-renders, and so
# does a manim.cfg there, which Manim reads from its working directory.
lc_manim_key <- function(paths, spec, rect, cfg) {
  py <- sort(list.files(dirname(paths$scene), pattern = "(\\.py|^manim\\.cfg)$", full.names = TRUE))
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
  # Manim 0.22 has no background flag; the colour goes in a config file.
  bg <- NULL
  if (!is.null(cfg$manim$background)) {
    bg <- file.path(media, "lecturecast.cfg")
    writeLines(c("[CLI]", paste0("background_color = ", cfg$manim$background)), bg)
  }
  args <- c(cmd[-1], "render", "--save_sections", "--format", "mp4", "--disable_caching",
            "--progress_bar", "none",
            "--resolution", sprintf("%d,%d", rect[["w"]], rect[["h"]]),
            "--frame_rate", as.character(cfg$video$fps), "--media_dir", media,
            if (!is.null(bg)) c("--config_file", bg),
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
  # A folder of its own per render, so two builds never share one.
  tmp <- tempfile("render-", tmpdir = lc_dir_create(dirname(dir)))
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
  if (!file.rename(out, dir)) {
    # Another build may have stored the same render meanwhile; use it.
    if (file.exists(index)) return(structure(lc_manim_cached(dir, index), cached = TRUE))
    lc_abort(step, "Could not store the render in the cache.", file = dir)
  }
  secs$file <- file.path(dir, stored)
  structure(secs, cached = FALSE)
}

lc_manim_cached <- function(dir, index) {
  step <- "manim (cache)"
  fix <- paste0("Delete the folder ", dir, " and build again; the scene will be rendered afresh.")
  m <- tryCatch(jsonlite::fromJSON(index), error = function(e) lc_abort(step, "The cached render is damaged.", file = index, fix = fix))
  secs <- m$sections
  ok <- is.data.frame(secs) && nrow(secs) > 0 && all(c("name", "file", "seconds") %in% names(secs)) &&
    is.character(secs$name) && all(!is.na(secs$name) & nzchar(secs$name)) &&
    is.character(secs$file) && all(!is.na(secs$file) & nzchar(secs$file)) &&
    is.numeric(secs$seconds) && all(is.finite(secs$seconds) & secs$seconds > 0)
  if (!ok) lc_abort(step, "The cached render is damaged.", file = index, fix = fix)
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

# For video: manim: false. The scene's cached render, or NULL when there is
# none. Never runs or requires Manim: with no manim and no uv, there is no
# engine to key on, so there is no render to find.
lc_manim_lookup <- function(paths, spec, rect, cfg, cache) {
  key <- tryCatch(lc_manim_key(paths, spec, rect, cfg), lecturecast_error = function(e) NULL)
  if (is.null(key)) return(NULL)
  dir <- file.path(cache, "manim", key)
  index <- file.path(dir, "sections.json")
  if (!file.exists(index)) return(NULL)
  lc_manim_cached(dir, index)
}
