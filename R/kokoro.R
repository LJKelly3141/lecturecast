# Kokoro, a voice that runs on this computer. A Python runner shipped in
# inst/python loads the model once and answers one JSON request per line, so
# a build pays the model's load time (about 13 s) once, not per segment.

lc_kokoro_version <- "0.9.4"
lc_kokoro_python <- "3.12"
lc_kokoro_soundfile <- "0.14.0"

# The command that starts the runner, through uv at pinned versions.
lc_kokoro_command <- function() {
  uv <- lc_find_tool("uv")
  if (!nzchar(uv)) {
    lc_abort("voice (kokoro)", "uv is not installed, and Kokoro runs through it.",
             fix = "Install uv (https://docs.astral.sh/uv/), then run lecturecast_check().")
  }
  ver <- getOption("lecturecast.kokoro_version", lc_kokoro_version)
  c(uv, "run", "-q", "--no-project", "--python", lc_kokoro_python,
    "--with", paste0("kokoro==", ver), "--with", paste0("soundfile==", lc_kokoro_soundfile),
    "python", system.file("python", "lecturecast_kokoro.py", package = "lecturecast"))
}

lc_find_kokoro <- function() {
  cmd <- tryCatch(lc_kokoro_command(), lecturecast_error = function(e) "")
  paste(cmd, collapse = " ")
}

lc_kokoro_engine <- function() {
  paste0("kokoro ", getOption("lecturecast.kokoro_version", lc_kokoro_version))
}

lc_kokoro_fail <- function(p, problem, fix = NULL) {
  err <- attr(p, "stderr_file")
  tail_err <- if (!is.null(err) && file.exists(err)) utils::tail(readLines(err, warn = FALSE), 5) else character()
  if (length(tail_err)) problem <- paste0(problem, " Last output: ", paste(tail_err, collapse = " | "))
  lc_abort("voice (kokoro)", problem, fix = fix)
}

# Read one reply line from the runner, waiting at most `timeout` seconds.
lc_kokoro_line <- function(p, timeout, what) {
  deadline <- Sys.time() + timeout
  repeat {
    if (p$is_alive()) p$poll_io(500) else Sys.sleep(0.05)
    line <- p$read_output_lines(n = 1)
    if (length(line)) return(jsonlite::fromJSON(line, simplifyVector = FALSE))
    if (!p$is_alive()) {
      lc_kokoro_fail(p, paste0("Kokoro stopped while ", what, "."),
                     fix = "Run lecturecast_check(), then build again.")
    }
    if (Sys.time() > deadline) {
      p$kill()
      lc_kokoro_fail(p, paste0("Kokoro did not answer within ", timeout, " seconds while ", what, "."))
    }
  }
}

lc_kokoro_start <- function(timeout = 900, quiet = FALSE) {
  cmd <- lc_kokoro_command()
  if (!quiet) message("Starting Kokoro (the first run downloads the voice model).")
  err <- tempfile("kokoro-", fileext = ".log")
  p <- tryCatch(
    processx::process$new(cmd[1], cmd[-1], stdin = "|", stdout = "|", stderr = err,
                          env = c("current", PYTORCH_ENABLE_MPS_FALLBACK = "1"), cleanup = TRUE),
    error = function(e) lc_abort("voice (kokoro)", paste0("Could not start Kokoro: ", conditionMessage(e)),
                                 fix = "Run lecturecast_check() to see which tools are missing.")
  )
  attr(p, "stderr_file") <- err
  ready <- lc_kokoro_line(p, timeout, "starting")
  if (!isTRUE(ready$ready)) lc_kokoro_fail(p, "Kokoro started but did not say it was ready.")
  p
}

# The running Kokoro process, started if there is none or it has died.
lc_kokoro_get <- function(quiet = getOption("lecturecast.kokoro_quiet", FALSE)) {
  p <- lc_state$kokoro
  if (is.null(p) || !p$is_alive()) {
    p <- lc_kokoro_start(quiet = quiet)
    lc_state$kokoro <- p
  }
  p
}

lc_kokoro_stop <- function() {
  p <- lc_state$kokoro
  if (!is.null(p) && p$is_alive()) p$kill()
  lc_state$kokoro <- NULL
  invisible()
}

# Send one request to the running process and return its reply. A dead
# process stops the build; the next request starts a fresh one.
lc_kokoro_ask <- function(req, timeout = 180) {
  p <- lc_state$kokoro
  if (is.null(p)) p <- lc_kokoro_get()
  if (!p$is_alive()) lc_kokoro_fail(p, "Kokoro has stopped.", fix = "Build again; Kokoro will be started afresh.")
  line <- paste0(as.character(jsonlite::toJSON(req, auto_unbox = TRUE, digits = NA)), "\n")
  ok <- tryCatch({ p$write_input(line); TRUE }, error = function(e) FALSE)
  if (!ok) lc_kokoro_fail(p, "Could not send text to Kokoro.", fix = "Build again; Kokoro will be started afresh.")
  lc_kokoro_line(p, timeout, "voicing")
}

lc_voice_kokoro <- function(text, voice_id, cfg, out) {
  step <- "voice (kokoro)"
  wav <- paste0(tools::file_path_sans_ext(out), ".wav")
  on.exit(unlink(wav), add = TRUE)
  res <- lc_kokoro_ask(list(text = enc2utf8(text), voice = voice_id,
                            speed = cfg$voice$kokoro_speed %||% 1, out = wav))
  if (!isTRUE(res$ok)) {
    lc_abort(step, paste0("Kokoro could not voice the text: ", res$error %||% "no reason given"), file = out,
             fix = paste0("Check the voice id (", voice_id, ") against Kokoro's voice list; ",
                          "English ids look like af_heart or am_michael."))
  }
  lc_duration(wav, step)
  lc_run(lc_tool("ffmpeg", step), c("-y", "-loglevel", "error", "-i", wav, "-codec:a", "libmp3lame",
                                    "-q:a", "2", out), step = step, file = out, timeout = 120)
  lc_duration(out, step)
  w <- res$words
  timing <- if (length(w)) {
    data.frame(text = vapply(w, function(x) as.character(x$text), ""),
               start = vapply(w, function(x) as.numeric(x$start), 0),
               end = vapply(w, function(x) as.numeric(x$end), 0),
               stringsAsFactors = FALSE)
  } else NULL
  list(file = out, timing = timing)
}
