write_script <- function(lines, dir = withr::local_tempdir(.local_envir = parent.frame())) {
  f <- file.path(dir, "episode.txt")
  writeLines(lines, f)
  f
}

tone <- function(file, seconds = 1) {
  processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i",
                            paste0("sine=duration=", seconds), file))
  file
}

test_that("dialogue scripts are read into turns with chapters", {
  f <- write_script(c("# Sticky wages", "", "## Why wages stick",
                      "HOST_A: [curious] Why don't wages fall?", "HOST_B: Several reasons.",
                      "This line continues the turn.", "## Policy", "HOST_A: And policy?"))
  t <- read_dialogue(f)
  expect_equal(attr(t, "title"), "Sticky wages")
  expect_equal(t$host, c("host_a", "host_b", "host_a"))
  expect_equal(t$text[2], "Several reasons. This line continues the turn.")
  expect_equal(t$chapter, c("Why wages stick", "Why wages stick", "Policy"))
  expect_equal(t$id, c("t001", "t002", "t003"))
})

test_that("bad scripts stop with the line named", {
  expect_error(read_dialogue(write_script(c("Hello there", "HOST_A: Hi"))), "Line 1")
  expect_error(read_dialogue(write_script(c("# Only a title"))), "no HOST_A")
  expect_error(read_dialogue(write_script(c("HOST_A: [laughs]"))), "no words, on lines: 1")
  expect_error(read_dialogue(write_script(c("HOST_A: Hi.", "Host_B: lower case label"))), "Line 2 is not a turn")
  expect_error(read_dialogue(write_script(c("HOST_A: Hi.", "### Aside"))), "Line 2 is not a turn")
  expect_error(read_dialogue(write_script(c("HOST_A: Hi.", "<!-- note -->"))), "Line 2 is not a turn")
  expect_error(read_dialogue(write_script(c("## A", "## B", "HOST_A: Hi."))), "heading on line 1 has no turns")
  expect_error(read_dialogue(write_script(c("HOST_A: Hi.", "## Empty"))), "heading on line 2 has no turns")
})

test_that("an ordinary continuation with a colon is kept", {
  t <- read_dialogue(write_script(c("HOST_A: Two reasons", "Reason one: wages are contracts.")))
  expect_equal(t$text, "Two reasons Reason one: wages are contracts.")
})

test_that("cues are removed for voices that would read them, and nothing else", {
  expect_equal(lc_strip_cues("[curious] Why  [short pause] not?"), "Why not?")
  expect_equal(lc_strip_cues("CI is [2, 5]."), "CI is [2, 5].")
})

test_that("dialogue chunks stay under the limit without splitting turns", {
  turns <- data.frame(id = sprintf("t%03d", 1:5), text = strrep("a", c(900, 900, 900, 100, 1500)))
  expect_equal(lc_dialogue_chunks(turns, 2000), c(1L, 1L, 2L, 2L, 3L))
  turns$chapter_n <- c(1L, 1L, 1L, 2L, 2L)
  expect_equal(lc_dialogue_chunks(turns, 2000), c(1L, 1L, 2L, 3L, 3L))
  turns$text[3] <- strrep("a", 2100)
  expect_error(lc_dialogue_chunks(turns, 2000), "Turn t003 is 2100 characters")
})

test_that("chapters start at the first turn of each heading", {
  turns <- data.frame(chapter = c(NA, "A", "A", "B"), chapter_n = c(0L, 1L, 1L, 2L), stringsAsFactors = FALSE)
  ch <- lc_chapters(turns, c(0, 5, 9, 20))
  expect_equal(ch$title, c("A", "B"))
  expect_equal(ch$start, c(5, 20))
  turns$chapter <- c(NA, "A", "A", "A")
  turns$chapter_n <- c(0L, 1L, 1L, 2L)
  expect_equal(nrow(lc_chapters(turns, c(0, 5, 9, 20))), 2)
  expect_error(lc_check_chapters(data.frame(title = c("A", "B"), start = c(5, 3)), 30, "x"), "out of order")
  expect_equal(nrow(lc_chapters(data.frame(chapter = NA_character_), 0)), 0)
})

test_that("the dialogue mode needs ElevenLabs", {
  cfg <- lecturecast_config(config = write_config(c("voice:", "  provider: edge", "podcast:", "  mode: dialogue")))
  expect_error(lc_podcast_mode(cfg), "needs the elevenlabs provider")
  cfg <- lecturecast_config(config = write_config(c("voice:", "  provider: edge")))
  expect_equal(lc_podcast_mode(cfg), "lines")
})

test_that("a podcast builds from recorded turns with chapters and a transcript", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  f <- write_script(c("# Test episode", "## Part one", "HOST_A: Hello.", "HOST_B: Hi.",
                      "## Part two", "HOST_A: Bye."), dir = dir)
  rec <- file.path(dir, "audio", "episode")
  dir.create(rec, recursive = TRUE)
  for (id in lc_recorded_ids(read_dialogue(f))) tone(file.path(rec, paste0(id, ".wav")), 1)
  cfg <- write_config(c("voice:", "  provider: recorded", "  recorded_dir: audio",
                        "podcast:", "  gap: 0.5", "  host_a_name: Logan", "  host_b_name: Sam"), dir = dir)
  r <- build_podcast(f, config = cfg, out_dir = file.path(dir, "out"), cache_dir = file.path(dir, "cache"),
                     quiet = TRUE)
  expect_equal(r$seconds, 3 + 2 * 0.5, tolerance = 0.2)
  expect_equal(r$turns$start, c(0, 1.5, 3), tolerance = 0.1)
  expect_equal(readLines(r$chapters), c("0:00 Part one", "0:03 Part two"))
  writeLines(c("# Test episode", "## Part one", "HOST_A: Hello again.", "HOST_B: Hi.",
               "## Part two", "HOST_A: Bye."), f)
  expect_error(build_podcast(f, config = cfg, out_dir = file.path(dir, "out"), quiet = TRUE), "Missing recordings: t001-")
  tr <- readLines(r$transcript)
  expect_true("**Logan:** Hello." %in% tr)
  expect_true("## Part two (0:03)" %in% tr)
  meta <- processx::run("ffprobe", c("-v", "error", "-show_chapters", "-of", "csv=p=0", r$audio))$stdout
  expect_match(meta, "Part two")
})

test_that("the ElevenLabs dialogue path voices chunks once and places turns", {
  skip_if_no_ffmpeg()
  withr::local_envvar(ELEVENLABS_API_KEY = "test-key")
  dir <- withr::local_tempdir()
  audio_b64 <- jsonlite::base64_enc(readBin(tone(file.path(dir, "t.mp3"), 2), "raw", 1e6))
  bodies <- list()
  httr2::local_mocked_responses(function(req) {
    bodies[[length(bodies) + 1]] <<- req$body$data
    n <- length(req$body$data$inputs)
    segs <- lapply(seq_len(n), function(j) list(voice_id = "v", start_time_seconds = (j - 1) * 0.8,
                                                end_time_seconds = j * 0.8, dialogue_input_index = j - 1))
    httr2::response_json(body = list(audio_base64 = audio_b64, voice_segments = segs))
  })
  f <- write_script(c("HOST_A: [curious] One?", "HOST_B: Two."), dir = dir)
  cfg <- write_config(c("voice:", "  provider: elevenlabs", "  host_a: va", "  host_b: vb"), dir = dir)
  cache <- file.path(dir, "cache")
  r <- build_podcast(f, config = cfg, out_dir = file.path(dir, "out"), cache_dir = cache, quiet = TRUE)
  expect_length(bodies, 1)
  expect_equal(bodies[[1]]$model_id, "eleven_v3")
  expect_equal(bodies[[1]]$inputs[[1]]$text, "[curious] One?")
  expect_equal(bodies[[1]]$inputs[[2]]$voice_id, "vb")
  expect_equal(r$turns$start, c(0, 0.8), tolerance = 0.05)
  build_podcast(f, config = cfg, out_dir = file.path(dir, "out"), cache_dir = cache, quiet = TRUE)
  expect_length(bodies, 1)
})

test_that("the single-voice path voices each turn with its host and strips cues", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  seen <- list()
  local_mocked_bindings(lc_voice = function(text, voice_id, cfg, out, model = NULL) {
    seen[[length(seen) + 1]] <<- c(text, voice_id)
    tone(out, 0.5)
    list(file = out, timing = NULL)
  }, lc_edge_command = function() "edge-tts", lc_edge_engine = function() "edge-tts@test")
  f <- write_script(c("HOST_A: [curious] One?", "HOST_B: Two."), dir = dir)
  cfg <- write_config(c("voice:", "  provider: edge", "  host_a: va", "  host_b: vb"), dir = dir)
  r <- build_podcast(f, config = cfg, out_dir = file.path(dir, "out"), cache_dir = file.path(dir, "cache"),
                     quiet = TRUE)
  expect_equal(seen, list(c("One?", "va"), c("Two.", "vb")))
  expect_true(file.exists(r$audio))
})

test_that("dialogue timing that is missing or out of order stops the build", {
  ok <- data.frame(dialogue_input_index = c(0, 1, 1), start_time_seconds = c(0, 2, 3))
  expect_equal(lc_dialogue_turn_starts(ok, 2), c(0, 2))
  gap <- data.frame(dialogue_input_index = c(0, 2), start_time_seconds = c(0, 3))
  expect_error(lc_dialogue_turn_starts(gap, 3), "missing a turn")
  expect_error(lc_dialogue_turn_starts(gap, 2), "not sent")
  expect_error(lc_dialogue_turn_starts(NULL, 2), "no voice segment timing")
})
