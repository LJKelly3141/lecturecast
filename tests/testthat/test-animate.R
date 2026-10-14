buttons <- function(labels) {
  data.frame(plot = 0L, menu = 0L, button = seq_along(labels) - 1L, label = labels,
             method = "animate", stringsAsFactors = FALSE)
}

test_that("quoted phrases are found with their positions", {
  q <- lc_quotes("Press “AD falls.” Then \"AD rises\" here.")
  expect_equal(q$phrase, c("AD falls", "AD rises"))
  expect_equal(q$pos, c(lc_nows("Press "), lc_nows("Press “AD falls.” Then ")))
  expect_equal(nrow(lc_quotes("No quotes.")), 0)
})

test_that("quotes matching a button label become events, first mention only", {
  b <- buttons(c("At potential", "AD falls", "AD rises"))
  ev <- lc_segment_events("“ad falls”: output falls. “AD rises” next. As after “AD falls”, a gap. “No gap”.", b)
  expect_equal(ev$label, c("AD falls", "AD rises"))
  expect_equal(ev$button, c(1L, 2L))
  ev2 <- lc_segment_events("Again “AD falls”.", b, used = "ad falls")
  expect_equal(nrow(ev2), 0)
  expect_equal(nrow(lc_segment_events("Text.", NULL)), 0)
})

test_that("animations start on cue and never overlap", {
  path <- write_config(c("voice:", "  provider: edge", "video:", "  lead_in: 0", "  tail: 0.5"), dir = withr::local_tempdir())
  cfg <- lecturecast_config(config = path)
  text <- "aaaa bbbb cccc dddd"
  events <- data.frame(label = c("A", "B"), pos = c(4, 8))
  captured <- list(list(files = c("a1", "a2"), seconds = 3), list(files = c("b1"), seconds = 1))
  s <- lc_animation_schedule("still", events, captured, text, NULL, 16, cfg)
  # A at 4 s plays 6 s; B is cued at 8 s but waits until 10 s.
  # The last frame is then held to the end of the narration plus the tail.
  expect_equal(s$files, c("still", "a1", "a2", "b1", "b1"))
  expect_equal(s$seconds, c(4, 3, 3, 1, 5.5))
  expect_equal(s$total, 16.5)
})

test_that("an animation that outruns the narration lengthens the clip", {
  path <- write_config(c("voice:", "  provider: edge", "video:", "  lead_in: 0", "  tail: 0.5"), dir = withr::local_tempdir())
  cfg <- lecturecast_config(config = path)
  s <- lc_animation_schedule("still", data.frame(label = "A", pos = 0), list(list(files = c("a1", "a2"), seconds = 5)),
                             "aaaa", NULL, 4, cfg)
  expect_equal(s$total, 10.5)
  expect_equal(sum(s$seconds), 10.5)
})

test_that("sentence pacing stretches an animation over its sentence", {
  path <- write_config(c("voice:", "  provider: edge", "video:", "  lead_in: 0", "  animation_pace: sentence"),
                       dir = withr::local_tempdir())
  cfg <- lecturecast_config(config = path)
  s <- lc_animation_schedule("still", data.frame(label = "A", pos = 0), list(list(files = c("a1", "a2"), seconds = 0.1)),
                             "First sentence here. Second one.", NULL, 10, cfg)
  expect_gt(s$seconds[2], 2)
})

test_that("labels and quotes match without trailing punctuation", {
  ev <- lc_segment_events("Press “Go” now.", buttons(c("Go!")))
  expect_equal(ev$label, "Go!")
})

test_that("captions follow the narration when an animation lengthens the clip", {
  path <- write_config(c("voice:", "  provider: edge", "video:", "  lead_in: 0.3", "  tail: 0.5"), dir = withr::local_tempdir())
  cfg <- lecturecast_config(config = path)
  segs <- data.frame(id = "s01", silent = NA_real_, text = "One. Two.", clip_seconds = 20, audio_seconds = 5, start = 0)
  cues <- lc_video_cues(segs, list(NULL), cfg)
  expect_equal(max(cues$end), 5.3, tolerance = 1e-6)
})
