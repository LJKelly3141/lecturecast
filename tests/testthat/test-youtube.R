# Everything before the first request to YouTube. No test here touches the
# network: dry runs and the plan stop before any login.
yt_files <- function(dir, chapters = c("0:00 Introduction", "0:40 One", "1:30 Two")) {
  video <- file.path(dir, "deck.mp4")
  writeBin(as.raw(1:50), video)
  writeLines(c("WEBVTT", "", "00:00.000 --> 00:01.000", "Hello."), file.path(dir, "deck.vtt"))
  writeLines(chapters, file.path(dir, "deck-chapters.txt"))
  writeBin(as.raw(1:20), file.path(dir, "deck-thumbnail.jpg"))
  video
}

test_that("a first upload adds the chapters to the description", {
  dir <- withr::local_tempdir()
  video <- yt_files(dir)
  p <- lc_yt_plan(video, " The Keynesian view ", "Chapter 12.", "macro", "unlisted", NULL, TRUE, TRUE, FALSE,
                  file.path(dir, "state.json"))
  expect_equal(p$action, "upload")
  expect_equal(p$title, "The Keynesian view")
  expect_equal(p$description, "Chapter 12.\n\n0:00 Introduction\n0:40 One\n1:30 Two")
  expect_equal(p$key, "deck")
  expect_match(p$captions, "deck\\.vtt$")
})

test_that("fewer than three chapters are left out of the description", {
  dir <- withr::local_tempdir()
  video <- yt_files(dir, c("0:00 Introduction", "0:40 One"))
  p <- lc_yt_plan(video, "T", "Desc.", character(0), "unlisted", NULL, TRUE, TRUE, FALSE, file.path(dir, "s.json"))
  expect_equal(p$description, "Desc.")
  expect_equal(p$chapters, 2)
})

test_that("bad titles, descriptions and missing files stop before anything is sent", {
  dir <- withr::local_tempdir()
  video <- yt_files(dir)
  st <- file.path(dir, "s.json")
  expect_error(lc_yt_plan(video, "", "", character(0), "unlisted", NULL, TRUE, TRUE, FALSE, st), "needs a title")
  expect_error(lc_yt_plan(video, strrep("x", 101), "", character(0), "unlisted", NULL, TRUE, TRUE, FALSE, st), "allows 100")
  expect_error(lc_yt_plan(video, "T", "a <b>", character(0), "unlisted", NULL, TRUE, TRUE, FALSE, st), "< or >")
  expect_error(lc_yt_plan(video, "T", strrep("x", 5000), character(0), "unlisted", NULL, TRUE, TRUE, FALSE, st), "allows 5000")
  unlink(file.path(dir, "deck.vtt"))
  expect_error(lc_yt_plan(video, "T", "", character(0), "unlisted", NULL, TRUE, TRUE, FALSE, st), "captions file is missing")
  expect_equal(lc_yt_plan(video, "T", "", character(0), "unlisted", NULL, FALSE, TRUE, FALSE, st)$captions, NULL)
  unlink(file.path(dir, "deck-chapters.txt"))
  expect_error(lc_yt_plan(video, "T", "", character(0), "unlisted", NULL, FALSE, TRUE, FALSE, st), "chapter list is missing")
  expect_error(lc_yt_plan(file.path(dir, "none.mp4"), "T", "", character(0), "unlisted", NULL, FALSE, FALSE, FALSE, st),
               "does not exist")
})

test_that("the state file decides between update and replace", {
  dir <- withr::local_tempdir()
  video <- yt_files(dir)
  st <- file.path(dir, "s.json")
  p <- lc_yt_plan(video, "T", "D", c("a", "b"), "unlisted", NULL, TRUE, TRUE, FALSE, st)
  lc_yt_write_state(st, "deck", list(video_id = "abc123", video_hash = p$video_hash, title = "T",
                                     description = p$description, tags = list("a", "b"), privacy = "unlisted",
                                     playlist = "PLx", playlist_item_id = "item1"))
  same <- lc_yt_plan(video, "T", "D", c("a", "b"), "unlisted", NULL, TRUE, TRUE, FALSE, st)
  expect_equal(same$action, "update")
  expect_equal(same$changes, character(0))
  moved <- lc_yt_plan(video, "New title", "D", "a", "public", NULL, TRUE, TRUE, FALSE, st)
  expect_equal(moved$changes, c("title", "tags", "privacy"))

  writeBin(as.raw(50:1), video)
  expect_error(lc_yt_plan(video, "T", "D", character(0), "unlisted", NULL, TRUE, TRUE, FALSE, st),
               "cannot swap a video's file")
  r <- lc_yt_plan(video, "T", "D", character(0), "unlisted", NULL, TRUE, TRUE, TRUE, st)
  expect_equal(r$action, "replace")
  expect_equal(r$playlist, "PLx")
})

test_that("state entries round-trip and keep other videos", {
  dir <- withr::local_tempdir()
  st <- file.path(dir, "s.json")
  lc_yt_write_state(st, "b", list(video_id = "v2", tags = list("one")))
  lc_yt_write_state(st, "a", list(video_id = "v1", tags = list()))
  s <- lc_yt_read_state(st)
  expect_equal(names(s), c("a", "b"))
  expect_equal(s$b$tags, list("one"))
  expect_false(file.exists(paste0(st, ".tmp")))
  writeLines("{ not json", st)
  expect_error(lc_yt_read_state(st), "not valid JSON")
})

test_that("the default state file sits beside lecturecast.yml", {
  dir <- withr::local_tempdir()
  writeLines("voice:\n  provider: edge", file.path(dir, "lecturecast.yml"))
  out <- file.path(dir, "build", "video")
  dir.create(out, recursive = TRUE)
  video <- yt_files(out)
  p <- lc_yt_plan(video, "T", "", character(0), "unlisted", NULL, TRUE, TRUE, FALSE, NULL)
  expect_equal(normalizePath(dirname(p$state)), normalizePath(dir))
  expect_equal(basename(p$state), "lecturecast-youtube.json")
})

test_that("playlist links give their id", {
  expect_equal(lc_yt_playlist_id("https://www.youtube.com/playlist?list=PLabc_-9"), "PLabc_-9")
  expect_equal(lc_yt_playlist_id("PLabc"), "PLabc")
  expect_error(lc_yt_playlist_id("not a playlist!"), "not a playlist")
})

test_that("a dry run shows the plan and sends nothing", {
  dir <- withr::local_tempdir()
  video <- yt_files(dir)
  withr::local_envvar(YT_CLIENT_ID = "", YT_CLIENT_SECRET = "")
  out <- cli::cli_fmt(p <- youtube_upload(video, "My lecture", "About it.", playlist = "PLz", dry_run = TRUE,
                                          state = file.path(dir, "s.json")))
  expect_equal(p$action, "upload")
  txt <- paste(out, collapse = "\n")
  expect_match(txt, "Upload as a new video")
  expect_match(txt, "Privacy: unlisted")
  expect_match(txt, "Playlist: PLz")
  expect_match(txt, "0:40 One")
  expect_match(txt, "deck-thumbnail\\.jpg")
  expect_false(file.exists(file.path(dir, "s.json")))
})

test_that("uploading without the OAuth client stops with the fix", {
  withr::local_envvar(YT_CLIENT_ID = "", YT_CLIENT_SECRET = "")
  expect_error(lc_yt_client(), "YT_CLIENT_ID and YT_CLIENT_SECRET")
})

test_that("the thumbnail is the built one, a file of your own, or none", {
  dir <- withr::local_tempdir()
  video <- yt_files(dir)
  st <- file.path(dir, "s.json")
  plan <- function(th) lc_yt_plan(video, "T", "", character(0), "unlisted", NULL, TRUE, TRUE, FALSE, st, th)
  expect_match(plan(TRUE)$thumbnail, "deck-thumbnail\\.jpg$")
  expect_null(plan(FALSE)$thumbnail)
  own <- file.path(dir, "cover.png")
  writeBin(as.raw(1:10), own)
  expect_match(plan(own)$thumbnail, "cover\\.png$")
  gif <- file.path(dir, "cover.gif")
  writeBin(as.raw(1:10), gif)
  expect_error(plan(gif), "JPEG or PNG")
  big <- file.path(dir, "big.jpg")
  writeBin(raw(2e6 + 1), big)
  expect_error(plan(big), "2 MB")
  unlink(file.path(dir, "deck-thumbnail.jpg"))
  expect_error(plan(TRUE), "thumbnail is missing")
})
