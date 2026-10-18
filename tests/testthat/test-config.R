test_that("settings are read and defaults filled", {
  path <- write_config(c("voice:", "  provider: edge", "  narrator: en-US-AndrewNeural"))
  cfg <- lecturecast_config(config = path)
  expect_equal(cfg$voice$provider, "edge")
  expect_equal(cfg$video$resolution, "1080p")
  expect_equal(cfg$voice$model, "eleven_multilingual_v2")
})

test_that("a missing or unknown provider stops the build", {
  path <- write_config(c("voice:", "  narrator: x"))
  expect_error(lecturecast_config(config = path), class = "lecturecast_error")
  path <- write_config(c("voice:", "  provider: robot"))
  expect_error(lecturecast_config(config = path), "must be one of")
})

test_that("no settings file means no voice, not a default", {
  dir <- withr::local_tempdir()
  file.create(file.path(dir, "_quarto.yml"))
  deck <- file.path(dir, "deck.html")
  file.create(deck)
  expect_error(lecturecast_config(deck), "no voice is set")
})

test_that("settings are found in a parent folder up to the course root", {
  root <- withr::local_tempdir()
  file.create(file.path(root, "_quarto.yml"))
  writeLines(c("voice:", "  provider: edge"), file.path(root, "lecturecast.yml"))
  dir.create(file.path(root, "docs", "slides"), recursive = TRUE)
  deck <- file.path(root, "docs", "slides", "deck.html")
  file.create(deck)
  expect_equal(normalizePath(lc_find_config(deck)), normalizePath(file.path(root, "lecturecast.yml")))
})

test_that("recorded mode needs a folder", {
  path <- write_config(c("voice:", "  provider: recorded"))
  expect_error(lecturecast_config(config = path), "recorded_dir")
})

test_that("an unset voice id stops the build", {
  path <- write_config(c("voice:", "  provider: edge"))
  cfg <- lecturecast_config(config = path)
  expect_error(lc_voice_id(cfg, "narrator"), "narrator")
})

test_that("card and fragment settings are checked", {
  bad <- function(...) lecturecast_config(config = write_config(c("voice:", "  provider: edge", "video:", ...)))
  expect_error(bad("  card_color: red"), "hex colour")
  expect_error(bad("  fragments: maybe"), "true or false")
  expect_error(bad("  title_card:", "    titel: Hi"), "Unknown card setting: titel")
  expect_error(bad("  crossfade: -1"), "crossfade")
  cfg <- bad("  title_card:", "    title: Week 7")
  expect_equal(cfg$video$title_card$title, "Week 7")
})

test_that("out_dir in the settings is relative to the settings file and the argument wins", {
  dir <- withr::local_tempdir()
  cfg <- lecturecast_config(config = write_config(c("voice:", "  provider: edge", "video:", "  out_dir: build/video",
                                                    "podcast:", "  out_dir: /tmp/pods"), dir = dir))
  deck <- file.path(dir, "slides", "deck.html")
  expect_equal(normalizePath(dirname(lc_out_dir(NULL, cfg, "video", deck)), mustWork = FALSE),
               file.path(normalizePath(dir), "build"))
  expect_equal(basename(lc_out_dir(NULL, cfg, "video", deck)), "video")
  expect_equal(lc_out_dir(NULL, cfg, "podcast", "x/ep.txt"), "/tmp/pods")
  expect_equal(lc_out_dir("mine", cfg, "video", deck), "mine")
  plain <- lecturecast_config(config = write_config(c("voice:", "  provider: edge")))
  expect_equal(lc_out_dir(NULL, plain, "video", deck), dirname(deck))
  expect_error(lecturecast_config(config = write_config(c("voice:", "  provider: edge", "video:", "  out_dir: 3"))),
               "out_dir")
})

test_that("the thumbnail slide defaults to 1 and must be a slide number", {
  expect_equal(lecturecast_config(config = write_config("voice:\n  provider: edge"))$video$thumbnail, 1)
  expect_equal(lecturecast_config(config = write_config("voice:\n  provider: edge\nvideo:\n  thumbnail: 4"))$video$thumbnail, 4)
  expect_error(lecturecast_config(config = write_config("voice:\n  provider: edge\nvideo:\n  thumbnail: 0")), "slide number")
})

test_that("slide numbers are off by default and take true, false or a reveal format", {
  sn <- function(x) lecturecast_config(config = write_config(c("voice:", "  provider: edge", "video:", x)))$video$slide_number
  expect_false(lecturecast_config(config = write_config("voice:\n  provider: edge"))$video$slide_number)
  expect_true(sn("  slide_number: true"))
  expect_equal(sn("  slide_number: c/t"), "c/t")
  expect_error(sn("  slide_number: page"), "slide_number")
  expect_error(sn("  slide_number: 3"), "slide_number")
})
