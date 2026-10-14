#' Start a lecturecast settings file for a project
#'
#' Writes a starter `lecturecast.yml` at the project root, beside
#' `_quarto.yml`, so every deck in the project uses one voice. Videos go to
#' `build/video/` under the project, outside the rendered site. An existing
#' settings file is never overwritten.
#'
#' @param proj The project folder. Defaults to the working directory.
#' @param provider The voice provider: `"edge"`, `"elevenlabs"` or
#'   `"recorded"`.
#' @param narrator The voice id for lecture videos. The default is an Edge
#'   voice; for ElevenLabs use a voice id from the ElevenLabs voice list.
#' @param out_dir Folder for finished videos, relative to the project.
#' @param quiet If `TRUE`, print nothing.
#' @return Invisibly, the path of the settings file.
#' @export
use_lecturecast <- function(proj = ".", provider = "edge", narrator = "en-US-AndrewNeural",
                            out_dir = "build/video", quiet = FALSE) {
  step <- "settings"
  if (!is.character(proj) || length(proj) != 1 || !dir.exists(proj)) {
    lc_abort(step, "Project folder not found.", file = as.character(proj)[1])
  }
  for (arg in list(list("provider", provider), list("narrator", narrator), list("out_dir", out_dir))) {
    if (!is.character(arg[[2]]) || length(arg[[2]]) != 1 || !nzchar(arg[[2]])) {
      lc_abort(step, paste0(arg[[1]], " must be a single piece of text."))
    }
  }
  proj <- normalizePath(proj)
  path <- file.path(proj, "lecturecast.yml")
  if (file.exists(path)) {
    lc_abort(step, "lecturecast.yml already exists, so it was left as it is.", file = path,
             fix = "Edit that file, or delete it first to start again.")
  }
  if (!quiet && !file.exists(file.path(proj, "_quarto.yml"))) {
    cli::cli_alert_warning(lc_esc(paste0("No _quarto.yml in ", proj, ". lecturecast.yml is usually kept beside it, at the project root.")))
  }
  lines <- c(
    "# lecturecast settings for every deck in this project.",
    "# The ElevenLabs key is never kept here; it comes from ELEVENLABS_API_KEY.",
    "voice:",
    paste0("  provider: ", provider),
    paste0("  narrator: ", narrator),
    if (provider == "recorded") "  recorded_dir: audio",
    "  # host_a: and host_b: set the two podcast voices.",
    "video:",
    paste0("  out_dir: ", out_dir),
    "  title_card: true",
    "  # silent: slides without notes, by number or title, in seconds",
    "  #   \"1\": 4"
  )
  tmp <- paste0(path, ".partial")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(lines, tmp)
  tryCatch(lecturecast_config(config = tmp), lecturecast_error = function(e) {
    lc_abort(step, paste0("The starter settings would not be valid: ", conditionMessage(e)))
  })
  file.rename(tmp, path)
  if (!quiet) {
    lc_done(quiet, paste0("Wrote ", path, "."))
    if (!lc_ignored(proj, out_dir)) {
      cli::cli_alert_info(lc_esc(paste0("Add ", sub("/.*$", "", out_dir), "/ to .gitignore so videos stay out of git.")))
    }
  }
  invisible(path)
}

# Whether the first folder of `out_dir` is listed in the project's .gitignore.
lc_ignored <- function(proj, out_dir) {
  gi <- file.path(proj, ".gitignore")
  if (!file.exists(gi)) return(FALSE)
  top <- sub("/.*$", "", out_dir)
  lines <- trimws(readLines(gi, warn = FALSE))
  any(sub("^/", "", sub("/$", "", lines)) == top)
}
