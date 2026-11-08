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
