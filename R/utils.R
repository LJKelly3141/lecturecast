# Stop the build with a message naming the step, the file and the fix.
lc_abort <- function(step, problem, file = NULL, fix = NULL, call = NULL, class = NULL) {
  msg <- c(paste0("lecturecast stopped at step: ", step), "x" = problem)
  if (!is.null(file)) msg <- c(msg, "i" = paste0("File: ", file))
  if (!is.null(fix)) msg <- c(msg, "i" = paste0("Fix: ", fix))
  cli::cli_abort(lc_esc(msg), class = c(class, "lecturecast_error"), call = call,
                 step = step, file = file)
}

# Run an external command with a timeout. Any non-zero exit, timeout or
# missing binary stops the build with the tail of stderr.
lc_run <- function(cmd, args, step, file = NULL, fix = NULL, timeout = 300,
                   wd = NULL, env = NULL) {
  res <- tryCatch(
    processx::run(cmd, args, error_on_status = FALSE, timeout = timeout,
                  wd = wd, env = env, stderr_to_stdout = FALSE),
    error = function(e) {
      lc_abort(step, paste0("Could not run ", cmd, ": ", conditionMessage(e)),
               file = file, fix = fix %||% "Run lecturecast_check() to see which tools are missing.")
    }
  )
  if (isTRUE(res$timeout)) {
    lc_abort(step, paste0(basename(cmd), " did not finish within ", timeout, " seconds."),
             file = file, fix = fix)
  }
  if (!identical(res$status, 0L)) {
    tail_err <- utils::tail(strsplit(res$stderr, "\n")[[1]], 8)
    lc_abort(step, paste0(basename(cmd), " exited with status ", res$status, ": ",
                          paste(tail_err, collapse = " | ")),
             file = file, fix = fix)
  }
  res
}

lc_tool <- function(tool, step) {
  path <- lc_find_tool(tool)
  if (!nzchar(path)) {
    lc_abort(step, paste0(tool, " was not found."),
             fix = paste0("Install ", tool, " and run lecturecast_check()."))
  }
  path
}

# Duration in seconds of a media file, via ffprobe. Stops if the file is
# missing or has no usable duration.
lc_duration <- function(file, step) {
  if (!file.exists(file) || file.size(file) == 0) {
    lc_abort(step, "Expected output file is missing or empty.", file = file)
  }
  res <- lc_run(lc_tool("ffprobe", step),
                c("-v", "error", "-show_entries", "format=duration",
                  "-of", "default=noprint_wrappers=1:nokey=1", file),
                step = step, file = file, timeout = 60)
  d <- suppressWarnings(as.numeric(trimws(res$stdout)))
  if (length(d) != 1 || is.na(d) || d <= 0) {
    lc_abort(step, "ffprobe found no usable duration.", file = file)
  }
  d
}

# Width and height of an image or video, via ffprobe.
lc_dimensions <- function(file, step) {
  if (!file.exists(file) || file.size(file) == 0) {
    lc_abort(step, "Expected output file is missing or empty.", file = file)
  }
  res <- lc_run(lc_tool("ffprobe", step),
                c("-v", "error", "-select_streams", "v:0",
                  "-show_entries", "stream=width,height", "-of", "csv=p=0", file),
                step = step, file = file, timeout = 60)
  wh <- suppressWarnings(as.integer(strsplit(trimws(res$stdout), ",")[[1]]))
  if (length(wh) != 2 || anyNA(wh)) {
    lc_abort(step, "ffprobe could not read the image size.", file = file)
  }
  wh
}

lc_say <- function(quiet, ...) {
  if (!quiet) cli::cli_alert_info(lc_esc(paste0(...)))
}

lc_done <- function(quiet, ...) {
  if (!quiet) cli::cli_alert_success(lc_esc(paste0(...)))
}

# Escape braces so cli does not treat file names or stderr as glue.
lc_esc <- function(x) {
  out <- gsub("}", "}}", gsub("{", "{{", x, fixed = TRUE), fixed = TRUE)
  names(out) <- names(x)
  out
}

`%||%` <- function(x, y) if (is.null(x)) y else x

lc_dir_create <- function(path) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(path, mustWork = TRUE)
}
