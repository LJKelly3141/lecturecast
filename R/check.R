#' Check which tools and keys lecturecast can find
#'
#' Reports whether Quarto, Chrome, FFmpeg, ffprobe, the `edge-tts` command
#' and the `ELEVENLABS_API_KEY` environment variable are available. The key's
#' value is never printed, only whether it is set.
#'
#' @param quiet If `TRUE`, print nothing.
#' @return Invisibly, a data frame with columns `item`, `found`, `detail` and
#'   `needed_for`.
#' @export
#' @examples
#' lecturecast_check()
lecturecast_check <- function(quiet = FALSE) {
  key_set <- nzchar(Sys.getenv("ELEVENLABS_API_KEY"))
  edge <- lc_find_edge_tts()
  rows <- list(
    lc_row("quarto", lc_find_tool("quarto"), "rendering decks"),
    lc_row("chrome", lc_find_chrome(), "capturing slides"),
    lc_row("ffmpeg", lc_find_tool("ffmpeg"), "assembling video and audio"),
    lc_row("ffprobe", lc_find_tool("ffprobe"), "checking every output"),
    lc_row("edge-tts", edge, "voice provider: edge"),
    data.frame(
      item = "ELEVENLABS_API_KEY",
      found = key_set,
      detail = if (key_set) "set" else "not set",
      needed_for = "voice provider: elevenlabs"
    )
  )
  out <- do.call(rbind, rows)
  if (!quiet) lc_print_check(out)
  invisible(out)
}

lc_row <- function(item, path, needed_for) {
  found <- !is.null(path) && nzchar(path)
  data.frame(
    item = item,
    found = found,
    detail = if (found) path else "not found",
    needed_for = needed_for
  )
}

lc_print_check <- function(out) {
  cli::cli_h2("lecturecast check")
  for (i in seq_len(nrow(out))) {
    msg <- paste0(out$item[i], ": ", out$detail[i], " (", out$needed_for[i], ")")
    if (out$found[i]) cli::cli_alert_success(msg) else cli::cli_alert_danger(msg)
  }
}

# Path to a command-line tool, or "" if absent. An option
# `lecturecast.<tool>` overrides the PATH lookup.
lc_find_tool <- function(tool) {
  opt <- getOption(paste0("lecturecast.", tool))
  if (!is.null(opt)) return(if (file.exists(opt)) opt else "")
  unname(Sys.which(tool))
}

lc_find_chrome <- function() {
  opt <- getOption("lecturecast.chrome", Sys.getenv("CHROMOTE_CHROME"))
  if (nzchar(opt)) return(if (file.exists(opt)) opt else "")
  if (requireNamespace("chromote", quietly = TRUE)) {
    path <- tryCatch(chromote::find_chrome(), error = function(e) NULL)
    if (!is.null(path) && file.exists(path)) return(path)
  }
  ""
}

# edge-tts on PATH, else run through `uvx` when uv is installed.
lc_find_edge_tts <- function() {
  path <- lc_find_tool("edge-tts")
  if (nzchar(path)) return(path)
  uvx <- lc_find_tool("uvx")
  if (nzchar(uvx)) return(paste(uvx, "edge-tts"))
  ""
}
