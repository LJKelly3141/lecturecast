test_that("a starter settings file is written at the project root and is valid", {
  proj <- withr::local_tempdir()
  file.create(file.path(proj, "_quarto.yml"))
  writeLines(c(".quarto/", "build/"), file.path(proj, ".gitignore"))
  path <- use_lecturecast(proj, quiet = TRUE)
  expect_equal(basename(path), "lecturecast.yml")
  cfg <- lecturecast_config(config = path)
  expect_equal(cfg$voice$provider, "edge")
  expect_equal(cfg$voice$narrator, "en-US-AndrewNeural")
  expect_equal(cfg$video$out_dir, "build/video")
  expect_false(file.exists(paste0(path, ".partial")))
})

test_that("an existing settings file is never overwritten", {
  proj <- withr::local_tempdir()
  writeLines("voice:\n  provider: recorded\n  recorded_dir: mine", file.path(proj, "lecturecast.yml"))
  before <- readLines(file.path(proj, "lecturecast.yml"))
  expect_error(use_lecturecast(proj, quiet = TRUE), "already exists")
  expect_equal(readLines(file.path(proj, "lecturecast.yml")), before)
})

test_that("bad arguments stop before anything is written", {
  proj <- withr::local_tempdir()
  expect_error(use_lecturecast(file.path(proj, "nope")), "not found")
  expect_error(use_lecturecast(proj, provider = "robot", quiet = TRUE), "would not be valid")
  expect_false(file.exists(file.path(proj, "lecturecast.yml")))
  expect_error(use_lecturecast(proj, narrator = "", quiet = TRUE), "narrator")
})

test_that("the gitignore check finds the output folder", {
  proj <- withr::local_tempdir()
  expect_false(lc_ignored(proj, "build/video"))
  writeLines(c("docs", "/build/"), file.path(proj, ".gitignore"))
  expect_true(lc_ignored(proj, "build/video"))
  expect_false(lc_ignored(proj, "out/video"))
})
