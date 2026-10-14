make_png <- function(dir, name = "a.png", size = "320x180") {
  f <- file.path(dir, name)
  processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i", paste0("color=c=red:s=", size),
                            "-frames:v", "1", f))
  f
}

make_tone <- function(dir, seconds = 1.5) {
  f <- file.path(dir, "tone.mp3")
  processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i",
                            paste0("sine=frequency=440:duration=", seconds), f))
  f
}

test_cfg <- function() {
  path <- write_config(c("voice:", "  provider: edge", "video:", "  resolution: 720p", "  fps: 10"),
                       dir = tempdir())
  lecturecast_config(config = path)
}

test_that("a voiced clip is lead-in + audio + tail long, at the set size", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  cfg <- test_cfg()
  d <- lc_still_clip(make_png(dir), file.path(dir, "c.mp4"), cfg, audio = make_tone(dir))
  a <- lc_duration(file.path(dir, "tone.mp3"), "t")
  expect_equal(d, cfg$video$lead_in + a + cfg$video$tail, tolerance = 0.15)
  expect_equal(lc_dimensions(file.path(dir, "c.mp4"), "t"), c(1280L, 720L))
})

test_that("silent clips and joins have the right length", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  cfg <- test_cfg()
  png <- make_png(dir)
  c1 <- file.path(dir, "c1.mp4")
  c2 <- file.path(dir, "c2.mp4")
  lc_still_clip(png, c1, cfg, seconds = 2)
  lc_still_clip(png, c2, cfg, audio = make_tone(dir, 1))
  total <- lc_concat(c(c1, c2), file.path(dir, "all.mp4"))
  expect_equal(total, lc_duration(c1, "t") + lc_duration(c2, "t"), tolerance = 0.15)
})

test_that("a missing or empty file stops with the file named", {
  skip_if_no_ffmpeg()
  f <- withr::local_tempfile(fileext = ".mp3")
  file.create(f)
  err <- expect_error(lc_duration(f, "voice"), class = "lecturecast_error")
  expect_match(conditionMessage(err), basename(f), fixed = TRUE)
})

test_that("a failing command stops with its status and the step", {
  skip_if_no_ffmpeg()
  err <- expect_error(lc_run("ffmpeg", c("-i", "/no/such/input.wav"), step = "assemble"),
                      class = "lecturecast_error")
  expect_match(conditionMessage(err), "assemble")
  expect_match(conditionMessage(err), "exited with status")
})

test_that("a command that runs too long is stopped", {
  skip_on_os("windows")
  expect_error(lc_run("sleep", "5", step = "voice", timeout = 0.5), "did not finish within")
})
