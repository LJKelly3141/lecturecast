kokoro_cfg <- function(speed = 1) list(voice = list(provider = "kokoro", kokoro_speed = speed))

sine_wav <- function(path, seconds = 1) {
  processx::run("ffmpeg", c("-y", "-loglevel", "error", "-f", "lavfi", "-i",
                            paste0("sine=duration=", seconds), path))
}

test_that("Kokoro is run through uv at pinned versions", {
  local_mocked_bindings(lc_find_tool = function(tool) if (tool == "uv") "/x/uv" else "")
  cmd <- lc_kokoro_command()
  expect_equal(cmd[1], "/x/uv")
  expect_true(all(c("kokoro==0.9.4", "soundfile==0.14.0", "--python", "3.12") %in% cmd))
  expect_match(cmd[length(cmd)], "lecturecast_kokoro\\.py$")
  expect_true(file.exists(cmd[length(cmd)]))
  expect_equal(lc_kokoro_engine(), "kokoro 0.9.4")
  local_mocked_bindings(lc_find_tool = function(tool) "")
  expect_error(lc_kokoro_command(), "uv is not installed")
  expect_equal(lc_find_kokoro(), "")
})

test_that("Kokoro word times become caption timing", {
  skip_if_no_ffmpeg()
  sent <- NULL
  local_mocked_bindings(lc_kokoro_ask = function(req, timeout = 180) {
    sent <<- req
    sine_wav(req$out)
    list(ok = TRUE, seconds = 1,
         words = list(list(text = "Tea", start = 0.28, end = 0.55), list(text = "is", start = 0.55, end = 0.66)))
  })
  out <- tempfile(fileext = ".mp3")
  v <- lc_voice_kokoro("Tea is.", "am_michael", kokoro_cfg(1.1), out)
  expect_equal(v$file, out)
  expect_equal(lc_duration(out, "t"), 1, tolerance = 0.1)
  expect_false(file.exists(sent$out))
  expect_equal(sent$voice, "am_michael")
  expect_equal(sent$speed, 1.1)
  expect_equal(v$timing, data.frame(text = c("Tea", "is"), start = c(0.28, 0.55), end = c(0.55, 0.66)))
})

test_that("a Kokoro error reply stops the build with the voice id", {
  local_mocked_bindings(lc_kokoro_ask = function(req, timeout = 180) {
    list(ok = FALSE, error = "voice af_hart not found")
  })
  err <- expect_error(lc_voice_kokoro("Hi.", "af_hart", kokoro_cfg(), tempfile(fileext = ".mp3")),
                      class = "lecturecast_error")
  expect_match(conditionMessage(err), "af_hart")
  expect_match(conditionMessage(err), "Check the voice id")
})

# Live: needs uv and, on first run, the internet to fetch the model.
skip_if_no_kokoro <- function() {
  skip_on_cran()
  skip_on_ci()
  skip_if_no_ffmpeg()
  skip_if(!nzchar(lc_find_kokoro()), "uv not installed")
}

test_that("Kokoro voices a sentence with numbers", {
  skip_if_no_kokoro()
  withr::defer(lc_kokoro_stop())
  out <- tempfile(fileext = ".mp3")
  v <- lc_voice_kokoro("Prices rose 3.5% to $20.", "af_heart", kokoro_cfg(), out)
  expect_gt(lc_duration(out, "t"), 1)
  expect_gte(nrow(v$timing), 3)
})

test_that("long text keeps word times rising across chunks", {
  skip_if_no_kokoro()
  withr::defer(lc_kokoro_stop())
  text <- paste(rep("Tea is a substitute, so the demand curve for tea shifts to the right.", 70), collapse = " ")
  out <- tempfile(fileext = ".mp3")
  v <- lc_voice_kokoro(text, "am_michael", kokoro_cfg(), out)
  expect_false(is.unsorted(v$timing$start))
  expect_lt(abs(lc_duration(out, "t") - max(v$timing$end)), 2)
})

test_that("a dead Kokoro process is noticed and replaced", {
  skip_if_no_kokoro()
  withr::defer(lc_kokoro_stop())
  p <- lc_kokoro_get()
  p$kill()
  expect_error(lc_kokoro_ask(list(text = "Hi.", voice = "af_heart", speed = 1, out = tempfile(fileext = ".wav"))),
               class = "lecturecast_error")
  expect_true(lc_kokoro_get()$is_alive())
})

test_that("a mistyped voice stops with its id", {
  skip_if_no_kokoro()
  withr::defer(lc_kokoro_stop())
  expect_error(lc_voice_kokoro("Hi.", "af_hart", kokoro_cfg(), tempfile(fileext = ".mp3")), "af_hart")
})
