fake_slides <- function(notes, titles = paste("Slide", seq_along(notes)),
                        n_fragments = 0L, silent = NA_real_) {
  n <- length(notes)
  data.frame(
    index = seq_len(n), h = seq_len(n) - 1L, v = 0L, title = titles,
    notes = notes, notes_html = "", n_fragments = rep_len(as.integer(n_fragments), n),
    silent = rep_len(silent, n), stringsAsFactors = FALSE
  )
}

write_config <- function(text, dir = withr::local_tempdir(.local_envir = parent.frame())) {
  path <- file.path(dir, "lecturecast.yml")
  writeLines(text, path)
  path
}

skip_if_no_ffmpeg <- function() {
  skip_if(!nzchar(Sys.which("ffmpeg")) || !nzchar(Sys.which("ffprobe")), "FFmpeg not installed")
}
