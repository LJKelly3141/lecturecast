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
