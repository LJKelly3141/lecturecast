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
