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

# Manim test helpers, shared by test-manim.R and test-manim-integration.R.
manim_fixture <- function(dir = withr::local_tempdir(.local_envir = parent.frame())) {
  dir.create(file.path(dir, "scenes", "data"), recursive = TRUE)
  writeLines("class Tiny: pass", file.path(dir, "scenes", "tiny.py"))
  writeLines("def helper(): pass", file.path(dir, "scenes", "util.py"))
  writeLines("x,y\n1,2", file.path(dir, "scenes", "data", "d.csv"))
  cfg <- lecturecast_config(config = write_config(c("voice:", "  provider: edge"), dir = dir))
  spec <- list(file = "scenes/tiny.py", scene = "Tiny", inputs = "data/d.csv", fill = "box")
  list(dir = dir, cfg = cfg, spec = spec, paths = lc_manim_paths(spec, cfg))
}

# A fake manim run: writes three coloured section videos and a section list in
# the form Task 0 recorded.
fake_manim_run <- function(paths, spec, rect, cfg, media) {
  out <- file.path(media, "videos", "tiny", "fake", "sections")
  dir.create(out, recursive = TRUE)
  # Real Manim saves the Create before the first next_section() as a section
  # with its own video, named "autocreated" (Task 0).
  for (k in 0:2) {
    processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi",
                              "-i", sprintf("color=c=%s:s=%dx%d:r=%s:d=0.5", c("green", "red", "blue")[k + 1], rect[["w"]], rect[["h"]], cfg$video$fps),
                              "-pix_fmt", "yuv420p", file.path(out, sprintf("Tiny_%04d.mp4", k))))
  }
  json <- file.path(out, "Tiny.json")
  writeLines('[{"name": "autocreated", "video": "Tiny_0000.mp4"},
               {"name": "grow", "video": "Tiny_0001.mp4"},
               {"name": "spin", "video": "Tiny_0002.mp4"}]', json)
  json
}
