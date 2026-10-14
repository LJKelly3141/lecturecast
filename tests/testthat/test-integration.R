# End to end on a small rendered deck. Needs Quarto, Chrome and FFmpeg, so it
# runs locally and is skipped on CRAN and in CI. Recorded tones stand in for
# a voice, so no network is used.
test_that("a deck with fragments, cards and fades builds and checks out", {
  skip_on_cran()
  skip_on_ci()
  skip_if_no_ffmpeg()
  skip_if(!nzchar(Sys.which("quarto")), "Quarto not installed")
  skip_if(!nzchar(lc_find_chrome()), "Chrome not found")

  dir <- withr::local_tempdir()
  file.copy(test_path("fixtures", "fragments.qmd"), dir)
  processx::run("quarto", c("render", "fragments.qmd"), wd = dir)
  deck <- file.path(dir, "fragments.html")

  rec <- file.path(dir, "audio", "fragments")
  dir.create(rec, recursive = TRUE)
  for (id in c("s03-1", "s03-2", "s03-3", "s04")) {
    processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=duration=1",
                              file.path(rec, paste0(id, ".wav"))))
  }
  cfg <- write_config(c("voice:", "  provider: recorded", "  recorded_dir: audio",
                        "video:", "  resolution: 720p", "  title_card: true", "  end_card: true",
                        "  silent:", "    \"1\": 1"), dir = dir)
  out <- file.path(dir, "out")
  r <- build_video(deck, config = cfg, out_dir = out, quiet = TRUE)

  expect_true(all(file.exists(c(r$video, r$captions, r$transcript))))
  expect_equal(r$segments$id, c("s01", "s02", "s03-1", "s03-2", "s03-3", "s04"))
  expect_equal(r$segments$fragment, c(-1L, -1L, -1L, 0L, 1L, -1L))
  expect_equal(lc_dimensions(r$video, "t"), c(1280L, 720L))
  # 2 cards of 4 s, the title slide (1 s) and the data-silent slide (2 s),
  # 4 voiced clips of 0.3 + 1 + 0.5 s, and 7 fades of 0.5 s.
  expect_equal(r$seconds, 8 + 1 + 2 + 4 * 1.8 + 7 * 0.5, tolerance = 0.5)
  expect_false(any(grepl("partial", list.files(out))))
  vtt <- readLines(r$captions)
  expect_true("Here are the points." %in% vtt)
})

test_that("a deck with an unmarked slide without notes stops before voicing", {
  skip_on_cran()
  skip_on_ci()
  skip_if(!nzchar(Sys.which("quarto")), "Quarto not installed")
  skip_if(!nzchar(lc_find_chrome()), "Chrome not found")
  dir <- withr::local_tempdir()
  file.copy(test_path("fixtures", "fragments.qmd"), dir)
  processx::run("quarto", c("render", "fragments.qmd"), wd = dir)
  cfg <- write_config(c("voice:", "  provider: edge", "  narrator: x"), dir = dir)
  expect_error(build_video(file.path(dir, "fragments.html"), config = cfg, out_dir = dir, quiet = TRUE),
               "1 \\(Fixture deck\\)")
})

test_that("a Plotly button quoted in the notes plays in the video", {
  skip_on_cran()
  skip_on_ci()
  skip_if_no_ffmpeg()
  skip_if(!nzchar(Sys.which("quarto")), "Quarto not installed")
  skip_if(!nzchar(lc_find_chrome()), "Chrome not found")
  skip_if_not_installed("plotly")

  dir <- withr::local_tempdir()
  file.copy(test_path("fixtures", "animation.qmd"), dir)
  processx::run("quarto", c("render", "animation.qmd"), wd = dir)
  rec <- file.path(dir, "audio", "animation")
  dir.create(rec, recursive = TRUE)
  processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=duration=3",
                            file.path(rec, "s03.wav")))
  cfg <- write_config(c("voice:", "  provider: recorded", "  recorded_dir: audio",
                        "video:", "  resolution: 720p", "  silent:", "    \"1\": 1"), dir = dir)
  work <- file.path(dir, "work")
  r <- build_video(file.path(dir, "animation.html"), config = cfg, out_dir = file.path(dir, "out"),
                   work_dir = work, quiet = TRUE)
  frames <- list.files(file.path(work, "png"), pattern = "^s03-anim")
  # "Move up" is quoted twice but plays once, with its three frames.
  expect_equal(length(frames), 3)
  first <- file.path(work, "png", "s03.png")
  last <- file.path(work, "png", frames[3])
  expect_false(identical(unname(tools::md5sum(first)), unname(tools::md5sum(last))))
  expect_true(file.exists(r$video))
})
