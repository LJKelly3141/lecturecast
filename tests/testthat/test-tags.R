test_that("tags come out of the spoken text and split it into pieces", {
  p <- lc_parse_tags("Watch this. [play: AD falls] Output drops. [Play: Recessionary gap, over] That is the gap.")
  expect_equal(p$text, "Watch this. Output drops. That is the gap.")
  expect_equal(p$pieces, c("Watch this.", "Output drops.", "That is the gap."))
  expect_equal(p$tags$label, c("AD falls", "Recessionary gap"))
  expect_equal(p$tags$over, c(FALSE, TRUE))
  expect_equal(p$tags$pos, c(lc_nows("Watch this."), lc_nows("Watch this.Output drops.")))
})

test_that("text without tags and tags at the edges are handled", {
  expect_equal(lc_parse_tags("Plain text.")$pieces, "Plain text.")
  expect_equal(nrow(lc_parse_tags("Plain [text] here.")$tags), 0)
  p <- lc_parse_tags("[play: Start] First.\n\nSecond. [play: End]")
  expect_equal(p$pieces, c("", "First.\n\nSecond.", ""))
  expect_equal(p$text, "First.\n\nSecond.")
})

test_that("a tag with no matching button stops the build with the labels", {
  buttons <- data.frame(plot = 0L, menu = 0L, button = 0:1, label = c("Start", "AD falls"), method = "animate")
  tags <- lc_parse_tags("Go. [play: AD rises]")$tags
  expect_error(lc_tag_events(tags, buttons, 8, "Model", "d"), "Use one of the slide's button labels: \"Start\", \"AD falls\"")
  ev <- lc_tag_events(lc_parse_tags("Go. [play: ad falls.]")$tags, buttons, 8, "Model", "d")
  expect_equal(ev$button, 1L)
  expect_false(ev$over)
})

test_that("piece timings are joined at their places in the narration", {
  tm <- list(data.frame(text = "One.", start = 0, end = 1), NULL)
  j <- lc_join_timing(c("One.", "Two."), tm, c(0, 3), c(1, 2))
  expect_equal(j$text, c("One.", "Two."))
  expect_equal(j$start, c(0, 3))
  expect_equal(j$end, c(1, 5))
  ch <- list(data.frame(char = c("a", "b"), start = c(0, 0.5), end = c(0.5, 1)), NULL)
  j <- lc_join_timing(c("ab", "cd"), ch, c(0, 2), c(1, 1))
  expect_equal(j$char, c("a", "b", "c", "d"))
  expect_equal(j$start, c(0, 0.5, 2, 2.5))
})

test_that("tagged animations start exactly at their times", {
  cfg <- lecturecast_config(config = write_config(c("voice:", "  provider: edge", "video:", "  lead_in: 0.2", "  tail: 0.3")))
  ev <- data.frame(label = c("A", "B"), pos = c(0, 0))
  cap <- list(list(files = c("a1", "a2"), seconds = 0.5), list(files = "b1", seconds = 0))
  s <- lc_animation_schedule("still", ev, cap, "x", NULL, 6, cfg, at = c(2, 4))
  # A starts at 0.2 + 2, runs 1 s, and holds its last frame until B at 0.2 + 4.
  expect_equal(s$files, c("still", "a1", "a2", "a2", "b1"))
  expect_equal(s$seconds, c(2.2, 0.5, 0.5, 1, 6 + 0.2 + 0.3 - 4.2), tolerance = 1e-6)
})

test_that("tagged narration waits for each animation, or runs over it", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  cfg <- lecturecast_config(config = write_config(c("voice:", "  provider: edge"), dir = dir))
  voice_piece <- function(txt, out) {
    processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=duration=1", out))
    list(file = out, timing = data.frame(text = txt, start = 0, end = 1), cached = FALSE)
  }
  cap <- list(list(files = c("f1", "f2", "f3"), seconds = 0.4))
  wait <- lc_voice_tagged(c("One.", "Two."), data.frame(over = FALSE), cap, voice_piece, cfg, file.path(dir, "w"))
  expect_equal(wait$at, 1, tolerance = 0.05)
  expect_equal(lc_duration(wait$file, "test"), 1 + 1.2 + 0.15 + 1, tolerance = 0.05)
  expect_equal(wait$timing$start, c(0, 2.35), tolerance = 0.05)
  over <- lc_voice_tagged(c("One.", "Two."), data.frame(over = TRUE), cap, voice_piece, cfg, file.path(dir, "o"))
  expect_equal(lc_duration(over$file, "test"), 2, tolerance = 0.05)
  expect_equal(over$at, 1, tolerance = 0.05)
})

test_that("lint_notes counts tags as changes and reports unknown labels", {
  half <- paste(rep("This sentence explains the idea at some length for listeners.", 6), collapse = " ")
  slides <- fake_slides(paste(half, "[play: Play]", half))
  slides$buttons <- list(data.frame(plot = 0L, menu = 0L, button = 0:1, label = c("Start", "Play"), method = "animate"))
  out <- lc_lint_slides(slides)
  expect_false(any(c("static slide", "animation not cued") %in% out$issue))
  expect_false(any(grepl("play", out$found, ignore.case = TRUE) & out$issue != "unknown tag"))
  slides$notes <- "Go. [play: Pause] Done."
  expect_equal(lc_lint_slides(slides)$issue, c("unknown tag", "animation not cued"))
})
