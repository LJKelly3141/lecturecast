# End to end. Needs Quarto, Chrome and FFmpeg, so it runs locally and is
# skipped on CRAN and in CI. The first test fakes Manim; the second runs it.
manim_deck <- function(dir, notes = NULL) {
  file.copy(test_path("fixtures", "manim", c("manim.qmd", "scene.py")), dir)
  if (!is.null(notes)) {
    qmd <- file.path(dir, "manim.qmd")
    writeLines(sub("First the square. Now \"grow\" it. Then \"spin\" it.", notes, readLines(qmd), fixed = TRUE), qmd)
  }
  processx::run("quarto", c("render", "manim.qmd"), wd = dir)
  rec <- file.path(dir, "audio", "manim")
  dir.create(rec, recursive = TRUE)
  processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=duration=2", file.path(rec, "s02.wav")))
  # Quarto's title slide has no notes; slide 1 is silent for 1 s.
  write_config(c("voice:", "  provider: recorded", "  recorded_dir: audio",
                 "video:", "  resolution: 720p", "  crossfade: 0",
                 "  silent:", "    \"1\": 1"), dir = dir)
  file.path(dir, "manim.html")
}

skip_if_no_deck_tools <- function() {
  skip_on_cran()
  skip_on_ci()
  skip_if_no_ffmpeg()
  skip_if(!nzchar(Sys.which("quarto")), "Quarto not installed")
  skip_if(!nzchar(lc_find_chrome()), "Chrome not found")
}

test_that("a deck with boxed and full-frame scenes builds (Manim faked)", {
  skip_if_no_deck_tools()
  dir <- withr::local_tempdir()
  deck <- manim_deck(dir)
  local_mocked_bindings(lc_manim_engine = function() "manim==test", lc_manim_run = fake_manim_run)
  msgs <- testthat::capture_messages(
    r <- build_video(deck, config = file.path(dir, "lecturecast.yml"), out_dir = file.path(dir, "out"),
                     cache_dir = file.path(dir, "cache"))
  )
  expect_true(all(file.exists(c(r$video, r$captions, r$transcript))))
  expect_equal(lc_dimensions(r$video, "t"), c(1280L, 720L))
  # Slide 2: 0.3 lead-in + 2 s narration + 0.5 tail; the three 0.5 s sections fit inside.
  # Slide 3: silent 1 s, but its scene runs 0.3 + 1.5 + 0.5 = 2.3 s.
  expect_equal(r$seconds, 1 + 2.8 + 2.3, tolerance = 0.3)
  expect_true(any(grepl("Slide 2: scene Tiny, 3 sections, 2 cued", msgs, fixed = TRUE)))
  expect_true(any(grepl("Slide 3: scene Tiny, 3 sections, 0 cued", msgs, fixed = TRUE)))
  # The boxed scene renders at the box's size, the full-frame one at 1280x720.
  sizes <- vapply(list.files(file.path(dir, "cache", "manim"), full.names = TRUE), function(d) {
    paste(lc_dimensions(file.path(d, "001.mp4"), "t"), collapse = "x")
  }, "")
  expect_true("1280x720" %in% sizes)
  expect_length(sizes, 2)
})

test_that("a second build reuses the renders", {
  skip_if_no_deck_tools()
  dir <- withr::local_tempdir()
  deck <- manim_deck(dir)
  calls <- 0
  local_mocked_bindings(lc_manim_engine = function() "manim==test",
                        lc_manim_run = function(...) { calls <<- calls + 1; fake_manim_run(...) })
  for (k in 1:2) build_video(deck, config = file.path(dir, "lecturecast.yml"), out_dir = file.path(dir, "out"),
                             cache_dir = file.path(dir, "cache"), quiet = TRUE)
  expect_equal(calls, 2)
})

test_that("the fixture deck builds with real Manim", {
  skip_if_no_deck_tools()
  skip_if(!nzchar(lc_find_manim()), "Manim not available")
  dir <- withr::local_tempdir()
  deck <- manim_deck(dir)
  r <- build_video(deck, config = file.path(dir, "lecturecast.yml"), out_dir = file.path(dir, "out"),
                   cache_dir = file.path(dir, "cache"), quiet = TRUE)
  expect_true(file.exists(r$video))
  # As in the faked build, the silent slide's scene runs 0.3 + 1.5 + 0.5 = 2.3 s.
  expect_equal(r$seconds, 1 + 2.8 + 2.3, tolerance = 0.3)
})

test_that("with video: manim: false, scenes show a placeholder, then their last rendered frame", {
  skip_if_no_deck_tools()
  dir <- withr::local_tempdir()
  deck <- manim_deck(dir)
  build <- function(conf) build_video(deck, config = conf, out_dir = file.path(dir, "out"),
                                      cache_dir = file.path(dir, "cache"))
  off <- file.path(dir, "off.yml")
  writeLines(c(readLines(file.path(dir, "lecturecast.yml")), "  manim: false"), off)
  # No Manim at all: the off build must not need it.
  local_mocked_bindings(lc_manim_command = function() lc_abort("manim", "Manim was not found."))
  msgs <- testthat::capture_messages(r <- build(off))
  expect_true(file.exists(r$video))
  expect_true(any(grepl("Slide 2: Manim is off and scene Tiny has no render yet", msgs, fixed = TRUE)))
  # Render once with Manim on, then off again: the last frame shows, Manim is not run.
  local_mocked_bindings(lc_manim_command = function() "/fake/manim", lc_manim_engine = function() "manim==test",
                        lc_manim_run = fake_manim_run)
  build(file.path(dir, "lecturecast.yml"))
  local_mocked_bindings(lc_manim_run = function(...) stop("not called"))
  msgs <- testthat::capture_messages(r <- build(off))
  expect_true(any(grepl("Slide 2: Manim is off; scene Tiny shows its last rendered frame", msgs, fixed = TRUE)))
  # 0.3 + 2 + 0.5 for slide 2, still; slide 3 silent 1 s, still.
  expect_equal(r$seconds, 1 + 2.8 + 1, tolerance = 0.3)
})

test_that("play tags cue sections on a scene slide", {
  skip_if_no_deck_tools()
  dir <- withr::local_tempdir()
  deck <- manim_deck(dir, notes = "First the square. [play: grow] Now it grows. [play: spin, over] And it turns.")
  local_mocked_bindings(lc_manim_engine = function() "manim==test", lc_manim_run = fake_manim_run)
  msgs <- testthat::capture_messages(
    r <- build_video(deck, config = file.path(dir, "lecturecast.yml"), out_dir = file.path(dir, "out"),
                     cache_dir = file.path(dir, "cache"))
  )
  expect_true(file.exists(r$video))
  expect_true(any(grepl("Slide 2: scene Tiny, 3 sections, 2 cued", msgs, fixed = TRUE)))
})

test_that("tagged narration waits for the scene's opening and each section (voice mocked)", {
  skip_if_no_deck_tools()
  dir <- withr::local_tempdir()
  deck <- manim_deck(dir, notes = "First the square. [play: grow] Now it grows. [play: spin, over] And it turns.")
  # A voice that is not recorded, so tags are voiced in pieces: each piece is 1 s.
  write_config(c("voice:", "  provider: edge", "  narrator: en-US-AndrewNeural",
                 "video:", "  resolution: 720p", "  crossfade: 0", "  silent:", "    \"1\": 1"), dir = dir)
  real <- lc_voice_tagged
  seen <- list()
  local_mocked_bindings(
    lc_manim_engine = function() "manim==test", lc_manim_run = fake_manim_run,
    lc_edge_command = function() "/fake/edge-tts", lc_edge_engine = function() "edge-tts test",
    lc_voice_edge = function(text, voice_id, cfg, out) {
      processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=duration=1", out))
      list(file = out, timing = NULL)
    },
    lc_voice_tagged = function(pieces, events, captured, voice_piece, cfg, work_base, busy = 0) {
      v <- real(pieces, events, captured, voice_piece, cfg, work_base, busy = busy)
      seen <<- list(busy = busy, at = v$at)
      v
    }
  )
  r <- build_video(deck, config = file.path(dir, "lecturecast.yml"), out_dir = file.path(dir, "out"),
                   cache_dir = file.path(dir, "cache"), quiet = TRUE)
  # The 0.5 s opening plays first; "grow" starts as piece 1 ends (1 s) and the
  # narration waits 0.5 + 0.15 s; "spin, over" starts at 2.65 s.
  expect_equal(seen$busy, 0.5, tolerance = 0.01)
  expect_equal(seen$at, c(1, 2.65), tolerance = 0.05)
  # 0.3 lead-in + 3.65 s narration + 0.5 tail.
  expect_equal(r$segments$clip_seconds[r$segments$slide == 2], 4.45, tolerance = 0.1)
})

test_that("a mistyped cue is reported as fewer sections cued", {
  skip_if_no_deck_tools()
  dir <- withr::local_tempdir()
  deck <- manim_deck(dir, notes = "First the square. Now \"grwo\" it. Then \"spin\" it.")
  local_mocked_bindings(lc_manim_engine = function() "manim==test", lc_manim_run = fake_manim_run)
  msgs <- testthat::capture_messages(
    build_video(deck, config = file.path(dir, "lecturecast.yml"), out_dir = file.path(dir, "out"),
                cache_dir = file.path(dir, "cache"))
  )
  expect_true(any(grepl("Slide 2: scene Tiny, 3 sections, 1 cued", msgs, fixed = TRUE)))
})

test_that("a scene and a chart with buttons on one slide stop the build, even with Manim off", {
  skip_if_no_deck_tools()
  dir <- withr::local_tempdir()
  deck <- manim_deck(dir)
  off <- file.path(dir, "off.yml")
  writeLines(c(readLines(file.path(dir, "lecturecast.yml")), "  manim: false"), off)
  real <- lc_read_slides
  local_mocked_bindings(lc_read_slides = function(b, deck) {
    s <- real(b, deck)
    # Give slide 2 a chart button, as a Plotly chart with an updatemenu would.
    s$buttons[[2]] <- data.frame(plot = 0L, menu = 0L, button = 0L, label = "Go", method = "animate",
                                 stringsAsFactors = FALSE)
    s
  })
  expect_error(build_video(deck, config = off, out_dir = file.path(dir, "out"), cache_dir = file.path(dir, "cache"),
                           quiet = TRUE),
               "Slide 2 holds a Manim scene and a Plotly chart with buttons")
})
