el_config <- function() {
  path <- write_config(c("voice:", "  provider: elevenlabs", "  narrator: abc"), dir = tempdir())
  lecturecast_config(config = path)
}

test_that("ElevenLabs needs the key from the environment", {
  withr::local_envvar(ELEVENLABS_API_KEY = "")
  expect_error(lc_voice_elevenlabs("Hi.", "abc", el_config(), tempfile()), "ELEVENLABS_API_KEY is not set")
})

test_that("ElevenLabs failures say why and never fall back", {
  withr::local_envvar(ELEVENLABS_API_KEY = "test-key")
  cases <- list(
    list(status = 401L, body = '{"detail":{"status":"invalid_api_key","message":"bad"}}', msg = "refused"),
    list(status = 402L, body = '{"detail":"x"}', msg = "credits"),
    list(status = 401L, body = '{"detail":{"status":"quota_exceeded","message":"none left"}}', msg = "out of credits")
  )
  for (cs in cases) {
    httr2::local_mocked_responses(function(req) {
      httr2::response(status_code = cs$status, headers = list(`Content-Type` = "application/json"),
                      body = charToRaw(cs$body))
    })
    err <- expect_error(lc_voice_elevenlabs("Hi.", "abc", el_config(), tempfile(fileext = ".mp3")),
                        class = "lecturecast_error")
    expect_match(conditionMessage(err), cs$msg)
  }
})

test_that("ElevenLabs request carries the key header, model and format", {
  withr::local_envvar(ELEVENLABS_API_KEY = "test-key")
  seen <- NULL
  httr2::local_mocked_responses(function(req) {
    seen <<- req
    httr2::response(status_code = 500L, body = charToRaw("{}"))
  })
  expect_error(lc_voice_elevenlabs("Hi.", "abc", el_config(), tempfile(fileext = ".mp3")), "HTTP 500")
  expect_match(seen$url, "/v1/text-to-speech/abc/with-timestamps\\?output_format=mp3_44100_128")
  expect_equal(seen$body$data$model_id, "eleven_multilingual_v2")
  expect_false(grepl("test-key", paste(capture.output(print(seen)), collapse = "")))
})

test_that("ElevenLabs alignment becomes character timing", {
  al <- list(characters = c("H", "i"), character_start_times_seconds = c(0, 0.1),
             character_end_times_seconds = c(0.1, 0.2))
  x <- lc_alignment_chars(al)
  expect_equal(x$char, c("H", "i"))
  expect_null(lc_alignment_chars(NULL))
})

test_that("recorded mode lists every missing file before building", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "audio", "deck"), recursive = TRUE)
  file.create(file.path(dir, "audio", "deck", "s01.wav"))
  path <- write_config(c("voice:", "  provider: recorded", "  recorded_dir: audio"), dir = dir)
  cfg <- lecturecast_config(config = path)
  expect_error(lc_recorded_files(c("s01", "s02", "s03"), cfg, "deck"), "Missing recordings: s02, s03")
  found <- lc_recorded_files("s01", cfg, "deck")
  expect_match(found[["s01"]], "s01.wav$")
})

test_that("edge-tts is run through uvx, pinned, when not installed", {
  local_mocked_bindings(lc_find_tool = function(tool) if (tool == "uvx") "/x/uvx" else "")
  expect_equal(lc_edge_command(), c("/x/uvx", paste0("edge-tts@", lc_edge_version)))
  local_mocked_bindings(lc_find_tool = function(tool) "")
  expect_error(lc_edge_command(), "uv is not installed")
})
