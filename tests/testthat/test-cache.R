cache_cfg <- function(provider = "edge", extra = character()) {
  path <- write_config(c("voice:", paste0("  provider: ", provider), "  narrator: v1", extra), dir = withr::local_tempdir(.local_envir = parent.frame()))
  lecturecast_config(config = path)
}

test_that("the cache key changes with text, voice and settings only", {
  local_mocked_bindings(lc_edge_engine = function() "edge-tts@test")
  cfg <- cache_cfg()
  k <- lc_cache_key(cfg, "v1", "Hello.")
  expect_equal(k, lc_cache_key(cfg, "v1", "Hello."))
  expect_false(k == lc_cache_key(cfg, "v1", "Hello!"))
  expect_false(k == lc_cache_key(cfg, "v2", "Hello."))
  cfg2 <- cache_cfg(extra = "  edge_rate: '+10%'")
  expect_false(k == lc_cache_key(cfg2, "v1", "Hello."))
  el <- cache_cfg("elevenlabs")
  expect_false(lc_cache_key(el, "v1", "Hi.") == lc_cache_key(el, "v1", "Hi.", model = "eleven_v3"))
})

test_that("a cached segment is reused and the voice is not called again", {
  skip_if_no_ffmpeg()
  cache <- withr::local_tempdir()
  work <- withr::local_tempdir()
  calls <- 0
  fake_voice <- function(out) {
    calls <<- calls + 1
    processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=duration=0.5", out))
    list(file = out, timing = data.frame(text = "Hi.", start = 0, end = 0.5))
  }
  a <- lc_cached_voice("k1", cache, fake_voice, file.path(work, "a.mp3"))
  b <- lc_cached_voice("k1", cache, fake_voice, file.path(work, "b.mp3"))
  expect_equal(calls, 1)
  expect_false(a$cached)
  expect_true(b$cached)
  expect_equal(b$timing$text, "Hi.")
  expect_equal(b$timing$end, 0.5)
})

test_that("a segment with no timing round-trips through the cache", {
  skip_if_no_ffmpeg()
  cache <- withr::local_tempdir()
  work <- withr::local_tempdir()
  fake_voice <- function(out) {
    processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=duration=0.5", out))
    list(file = out, timing = NULL)
  }
  lc_cached_voice("k2", cache, fake_voice, file.path(work, "a.mp3"))
  expect_null(lc_cached_voice("k2", cache, fake_voice, file.path(work, "b.mp3"))$timing)
})

test_that("a damaged cache file stops the build", {
  skip_if_no_ffmpeg()
  cache <- withr::local_tempdir()
  file.create(file.path(cache, "k3.mp3"))
  writeLines("{}", file.path(cache, "k3.json"))
  err <- expect_error(lc_cached_voice("k3", cache, function(out) stop("not called"), tempfile()),
                      "cached audio is missing")
  expect_match(conditionMessage(err), "k3.* and build again", fixed = TRUE)
  file.remove(file.path(cache, "k3.mp3"))
  writeLines("{\"seconds\": 1, \"tim", file.path(cache, "k3.json"))
  expect_error(lc_cached_voice("k3", cache, function(out) stop("not called"), tempfile()), "damaged")
})

test_that("cached audio of the wrong length stops the build", {
  skip_if_no_ffmpeg()
  cache <- withr::local_tempdir()
  processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i", "sine=duration=0.5",
                            file.path(cache, "k4.mp3")))
  writeLines('{"seconds": 3, "timing": {}}', file.path(cache, "k4.json"))
  expect_error(lc_cached_voice("k4", cache, function(out) stop("not called"), tempfile()), "not the length")
})

test_that("an interrupted write leaves no entry that looks finished", {
  skip_if_no_ffmpeg()
  cache <- withr::local_tempdir()
  expect_error(lc_cached_voice("k5", cache, function(out) stop("voice failed"), tempfile()), "voice failed")
  expect_length(list.files(cache), 0)
})
