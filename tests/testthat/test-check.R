test_that("check reports every item without external tools", {
  local_mocked_bindings(
    lc_find_tool = function(tool) "",
    lc_find_chrome = function() ""
  )
  withr::local_envvar(ELEVENLABS_API_KEY = "")
  out <- lecturecast_check(quiet = TRUE)
  expect_s3_class(out, "data.frame")
  expect_equal(
    out$item,
    c("quarto", "chrome", "ffmpeg", "ffprobe", "edge-tts", "ELEVENLABS_API_KEY")
  )
  expect_false(any(out$found))
})

test_that("check finds tools that are present", {
  local_mocked_bindings(
    lc_find_tool = function(tool) paste0("/fake/bin/", tool),
    lc_find_chrome = function() "/fake/chrome"
  )
  withr::local_envvar(ELEVENLABS_API_KEY = "sk_secret_value")
  out <- lecturecast_check(quiet = TRUE)
  expect_true(all(out$found))
  expect_equal(out$detail[out$item == "edge-tts"], "/fake/bin/edge-tts")
})

test_that("the API key value is never shown", {
  withr::local_envvar(ELEVENLABS_API_KEY = "sk_secret_value")
  out <- lecturecast_check(quiet = TRUE)
  expect_false(any(grepl("sk_secret_value", unlist(out))))
  printed <- capture.output(lecturecast_check(), type = "message")
  expect_false(any(grepl("sk_secret_value", printed)))
})

test_that("edge-tts falls back to uvx", {
  local_mocked_bindings(
    lc_find_tool = function(tool) if (tool == "uvx") "/fake/uvx" else ""
  )
  expect_equal(lc_find_edge_tts(), "/fake/uvx edge-tts")
})

test_that("an option overrides the PATH lookup", {
  withr::local_options(lecturecast.ffmpeg = "/no/such/ffmpeg")
  expect_equal(lc_find_tool("ffmpeg"), "")
})
