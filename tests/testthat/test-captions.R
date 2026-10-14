test_that("sentences split at end punctuation, keeping closing quotes", {
  s <- lc_sentences("He said “AD falls.” Then it stops. Is it? Yes.\n\nNew para, 12.3 here.")
  expect_equal(s, c("He said “AD falls.”", "Then it stops.", "Is it?", "Yes.", "New para, 12.3 here."))
})

test_that("long sentences break into pieces of at most max_chars", {
  long <- paste(rep("word", 60), collapse = " ")
  pieces <- lc_cue_chunks(long, max_chars = 84)
  expect_true(all(nchar(pieces) <= 84))
  expect_equal(paste(pieces, collapse = " "), long)
})

test_that("captions without timing spread over the audio by length", {
  cues <- lc_segment_cues("Short. A much longer second sentence here.", NULL, 10)
  expect_equal(cues$start[1], 0)
  expect_equal(cues$end[2], 10)
  expect_true(cues$end[1] < 3)
})

test_that("provider cue timing places the script's words", {
  timing <- data.frame(text = c("First one.", "Second one."), start = c(0.1, 2.0), end = c(1.5, 3.5))
  cues <- lc_segment_cues("First one. Second one.", timing, 4)
  expect_equal(cues$text, c("First one.", "Second one."))
  expect_equal(cues$start, c(0.1, 2.0), tolerance = 1e-6)
  expect_equal(cues$end, c(1.5, 3.5), tolerance = 1e-6)
})

test_that("character timing places the script's words", {
  chars <- strsplit("Hi. Yo.", "")[[1]]
  timing <- data.frame(char = chars, start = seq(0, by = 0.5, length.out = 7), end = seq(0.5, by = 0.5, length.out = 7))
  cues <- lc_segment_cues("Hi. Yo.", timing, 4)
  expect_equal(cues$start, c(0, 2), tolerance = 1e-6)
  expect_equal(cues$end, c(1.5, 3.5), tolerance = 1e-6)
})

test_that("SRT from edge-tts is parsed", {
  srt <- c("1", "00:00:00,050 --> 00:00:01,100", "Hello class.", "",
           "2", "00:00:01,100 --> 00:01:03,025", "Today we look", "at the model.", "")
  x <- lc_parse_srt(srt)
  expect_equal(x$text, c("Hello class.", "Today we look at the model."))
  expect_equal(x$end, c(1.1, 63.025))
})

test_that("WebVTT is written with no overlaps and wrapped lines", {
  f <- withr::local_tempfile(fileext = ".vtt")
  cues <- data.frame(text = c("A first caption that is long enough to need wrapping onto two lines.", "B."),
                     start = c(0, 2), end = c(2.5, 2.2))
  lc_write_vtt(cues, f)
  v <- readLines(f)
  expect_equal(v[1], "WEBVTT")
  expect_true("00:00:00.000 --> 00:00:02.000" %in% v)
  expect_true("00:00:02.000 --> 00:00:02.500" %in% v)
  expect_true(all(nchar(v) <= 45))
})

test_that("VTT times are formatted", {
  expect_equal(lc_vtt_time(3725.5), "01:02:05.500")
  expect_equal(lc_vtt_time(59.9996), "00:01:00.000")
})
