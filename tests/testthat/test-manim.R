test_that("manim on PATH is used first, then uvx with the pinned version", {
  local_mocked_bindings(lc_find_tool = function(tool) if (tool == "manim") "/fake/manim" else "/fake/uvx")
  expect_equal(lc_manim_command(), "/fake/manim")
  local_mocked_bindings(lc_find_tool = function(tool) if (tool == "uvx") "/fake/uvx" else "")
  expect_equal(lc_manim_command(), c("/fake/uvx", "--from", paste0("manim==", lc_manim_version), "manim"))
  withr::local_options(lecturecast.manim_version = "0.1.0")
  expect_equal(lc_manim_command()[3], "manim==0.1.0")
})

test_that("no manim and no uv stops with a fix", {
  local_mocked_bindings(lc_find_tool = function(tool) "")
  expect_error(lc_manim_command(), "Manim was not found")
  expect_equal(lc_find_manim(), "")
})

test_that("the engine label under uvx is the pinned version, without running anything", {
  local_mocked_bindings(lc_find_tool = function(tool) if (tool == "uvx") "/fake/uvx" else "",
                        lc_run = function(...) stop("not called"))
  expect_equal(lc_manim_engine(), paste0("manim==", lc_manim_version))
})

div <- function(...) list(modifyList(list(file = "scenes/a.py", scene = "A", inputs = "", fill = "", fragment = FALSE), list(...)))

test_that("a slide's manim div becomes a spec", {
  expect_null(lc_manim_spec(list(), 1, "d.html"))
  s <- lc_manim_spec(div(inputs = "data/x.csv, data/y.csv"), 2, "d.html")
  expect_equal(s$file, "scenes/a.py")
  expect_equal(s$scene, "A")
  expect_equal(s$fill, "box")
  expect_equal(s$inputs, c("data/x.csv", "data/y.csv"))
  expect_equal(lc_manim_spec(div(fill = "frame"), 2, "d.html")$fill, "frame")
})

test_that("bad manim divs stop the build", {
  expect_error(lc_manim_spec(c(div(), div()), 3, "d.html"), "Slide 3 has 2 Manim divs")
  expect_error(lc_manim_spec(div(scene = ""), 3, "d.html"), "no scene= attribute")
  expect_error(lc_manim_spec(div(file = ""), 3, "d.html"), "no file= attribute")
  expect_error(lc_manim_spec(div(fill = "page"), 3, "d.html"), "fill= must be box or frame")
  expect_error(lc_manim_spec(div(scene = "A; rm"), 3, "d.html"), "not a Python class name")
  expect_error(lc_manim_spec(div(fragment = TRUE), 3, "d.html"), "inside a fragment")
})

test_that("scene paths are relative to the settings file, inputs to the scene", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "scenes", "data"), recursive = TRUE)
  writeLines(c("from manim import *", "", "class A(Scene):", "    pass"), file.path(dir, "scenes", "a.py"))
  writeLines("x", file.path(dir, "scenes", "data", "x.csv"))
  cfg <- list(path = file.path(dir, "lecturecast.yml"))
  p <- lc_manim_paths(lc_manim_spec(div(inputs = "data/x.csv"), 1, "d.html"), cfg)
  expect_equal(p$scene, normalizePath(file.path(dir, "scenes", "a.py")))
  expect_equal(unname(p$inputs), file.path(dir, "scenes", "data", "x.csv"))
  expect_error(lc_manim_paths(lc_manim_spec(div(file = "nope.py"), 1, "d.html"), cfg), "scene file does not exist")
  expect_error(lc_manim_paths(lc_manim_spec(div(inputs = "data/none.csv"), 1, "d.html"), cfg), "input file does not exist")
})

test_that("a scene name the file does not define stops, listing the classes", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "scenes"))
  writeLines(c("class A(Scene):", "    pass", "class Helper:", "    pass"), file.path(dir, "scenes", "a.py"))
  cfg <- list(path = file.path(dir, "lecturecast.yml"))
  err <- expect_error(lc_manim_paths(lc_manim_spec(div(scene = "B"), 1, "d.html"), cfg), "no class named B")
  expect_match(conditionMessage(err), "A, Helper", fixed = TRUE)
})

test_that("a background setting and a manim.cfg beside the scene stop the build", {
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "scenes"))
  writeLines(c("class A(Scene):", "    pass"), file.path(dir, "scenes", "a.py"))
  writeLines(c("[CLI]", "frame_rate = 15"), file.path(dir, "scenes", "manim.cfg"))
  cfg <- list(path = file.path(dir, "lecturecast.yml"), manim = list(background = "#1e1e1e"))
  err <- expect_error(lc_manim_paths(lc_manim_spec(div(), 1, "d.html"), cfg), "Manim would ignore the manim.cfg")
  expect_match(conditionMessage(err), "background_color", fixed = TRUE)
  cfg$manim$background <- NULL
  expect_silent(lc_manim_paths(lc_manim_spec(div(), 1, "d.html"), cfg))
})

test_that("the box is rounded to even pixels and kept on screen", {
  b <- lc_manim_box(list(x = 101.4, y = 50.6, w = 801.2, h = 451), c(1920L, 1080L), 1, "d.html")
  # Edges are rounded, not the width: right edge 902.6 -> 902, so 800 wide.
  expect_equal(unname(b), c(102L, 50L, 800L, 452L))
  expect_equal(names(b), c("x", "y", "w", "h"))
  edge <- lc_manim_box(list(x = 1800, y = 0, w = 400, h = 200), c(1920L, 1080L), 1, "d.html")
  expect_equal(unname(edge[["w"]]), 120L)
})

test_that("a box starting off the left or top keeps only its visible part", {
  b <- lc_manim_box(list(x = -100, y = -50, w = 800, h = 400), c(1920L, 1080L), 1, "d.html")
  expect_equal(unname(b), c(0L, 0L, 700L, 350L))
})

test_that("a box with no size stops with a fix", {
  err <- expect_error(lc_manim_box(list(x = 10, y = 10, w = 900, h = 0), c(1920L, 1080L), 4, "d.html"),
                      "slide 4 is 900x0 pixels")
  expect_match(conditionMessage(err), "style=\"width", fixed = TRUE)
  expect_error(lc_manim_box(NULL, c(1920L, 1080L), 4, "d.html"), "not found on slide 4")
})

test_that("fill frame covers the whole video without asking Chrome", {
  r <- lc_manim_rect(NULL, list(fill = "frame"), c(1280L, 720L), "d.html", 1)
  expect_equal(unname(r), c(0L, 0L, 1280L, 720L))
})

test_that("a scene with no cues plays whole from the start of the slide", {
  r <- lc_manim_runs("No quotes here.", c("a", "b", "c"), 1)
  expect_equal(r$seg, 1L)
  expect_equal(r$pos, 0)
  expect_equal(c(r$from, r$to), c(1L, 3L))
  expect_false(r$cued)
})

test_that("each quoted section starts at its quote; the opening plays first", {
  text <- "First the square. Now “grow” it. Then \"spin\" it."
  r <- lc_manim_runs(text, c("autocreated", "grow", "spin"), 1)
  expect_equal(r$from, 1:3)
  expect_equal(r$to, 1:3)
  expect_equal(r$pos, c(0, lc_nows("First the square. Now "), lc_nows("First the square. Now “grow” it. Then ")))
  expect_equal(r$cued, c(FALSE, TRUE, TRUE))
})

test_that("unquoted sections play straight on after the one before", {
  r <- lc_manim_runs("Then \"c\".", c("a", "b", "c", "d"), 1)
  expect_equal(r$from, c(1L, 3L))
  expect_equal(r$to, c(2L, 4L))
})

test_that("cues can come from later segments of the same slide", {
  r <- lc_manim_runs(c("Here is \"b\".", "And then \"c\"."), c("a", "b", "c"), 1)
  expect_equal(r$seg, c(1L, 1L, 2L))
  expect_equal(r$from, 1:3)
})

test_that("a quoted first section has no separate opening", {
  r <- lc_manim_runs("\"a\" then \"b\".", c("a", "b"), 1)
  expect_equal(r$from, 1:2)
  expect_equal(r$cued, c(TRUE, TRUE))
})

test_that("a back-reference is ignored, but out-of-order cues stop the build", {
  r <- lc_manim_runs("\"b\" then \"c\", as after \"b\".", c("a", "b", "c"), 1)
  expect_equal(r$from, 1:3)
  expect_error(lc_manim_runs("\"c\" before \"b\".", c("a", "b", "c"), 5, "d.html"),
               "Slide 5 cues its scene's sections out of order")
})

test_that("silent segments (empty text) cue nothing", {
  r <- lc_manim_runs("", c("a", "b"), 1)
  expect_equal(c(r$from, r$to), c(1L, 2L))
})

test_that("a mistyped cue cues nothing and its section plays straight on", {
  r <- lc_manim_runs("Now \"grwo\" it. Then \"spin\" it.", c("opening", "grow", "spin"), 1)
  expect_equal(sum(r$cued), 1)
  expect_equal(r$from, c(1L, 3L))
  expect_equal(r$to, c(2L, 3L))
})

tagged <- function(text) lc_parse_tags(text)

test_that("play tags cue sections exactly, with over", {
  p <- tagged("First the square. [play: grow] Now it grows. [play: Spin, over] And it turns.")
  r <- lc_manim_runs(p$text, c("opening", "grow", "spin"), 1, tags = list(p$tags))
  expect_equal(r$from, 1:3)
  expect_equal(r$tag, c(FALSE, TRUE, TRUE))
  expect_equal(r$over, c(FALSE, FALSE, TRUE))
  expect_equal(r$pos[2:3], p$tags$pos)
})

test_that("a segment with tags ignores its quotes; one without uses them", {
  a <- tagged("Here \"spin\" is only a word. [play: grow] Done.")
  b <- tagged("Then \"spin\" it.")
  r <- lc_manim_runs(c(a$text, b$text), c("opening", "grow", "spin"), 1, tags = list(a$tags, b$tags))
  expect_equal(r$seg, c(1L, 1L, 2L))
  expect_equal(r$tag, c(FALSE, TRUE, FALSE))
  expect_equal(r$cued, c(FALSE, TRUE, TRUE))
})

test_that("an unknown tag or a section tagged twice stops the build", {
  p <- tagged("[play: grwo] Now.")
  expect_error(lc_manim_runs(p$text, c("opening", "grow"), 4, "d.html", tags = list(p$tags)),
               "Slide 4 has \\[play: grwo\\], but scene has no section of that name")
  q <- tagged("[play: grow] Now. [play: grow] Again.")
  expect_error(lc_manim_runs(q$text, c("opening", "grow"), 4, "d.html", tags = list(q$tags)),
               "plays section \"grow\" twice")
})

test_that("the render key ignores notes but follows every input to the pictures", {
  local_mocked_bindings(lc_manim_engine = function() "manim==test")
  f <- manim_fixture()
  rect <- c(x = 0L, y = 0L, w = 640L, h = 360L)
  k <- lc_manim_key(f$paths, f$spec, rect, f$cfg)
  expect_equal(k, lc_manim_key(f$paths, f$spec, rect, f$cfg))
  expect_false(k == lc_manim_key(f$paths, f$spec, c(x = 0L, y = 0L, w = 1280L, h = 720L), f$cfg))
  expect_false(k == lc_manim_key(f$paths, modifyList(f$spec, list(scene = "Other")), rect, f$cfg))
  cfg2 <- f$cfg; cfg2$video$fps <- 60
  expect_false(k == lc_manim_key(f$paths, f$spec, rect, cfg2))
  cfg3 <- f$cfg; cfg3$manim$background <- "#000000"
  expect_false(k == lc_manim_key(f$paths, f$spec, rect, cfg3))
  writeLines("def helper(): return 1", file.path(f$dir, "scenes", "util.py"))
  k2 <- lc_manim_key(f$paths, f$spec, rect, f$cfg)
  expect_false(k == k2)
  writeLines("x,y\n1,3", file.path(f$dir, "scenes", "data", "d.csv"))
  k3 <- lc_manim_key(f$paths, f$spec, rect, f$cfg)
  expect_false(k2 == k3)
  writeLines(c("[CLI]", "frame_rate = 15"), file.path(f$dir, "scenes", "manim.cfg"))
  expect_false(k3 == lc_manim_key(f$paths, f$spec, rect, f$cfg))
})

test_that("a background colour goes to Manim through a config file", {
  f <- manim_fixture()
  f$cfg$manim$background <- "#1e1e1e"
  media <- withr::local_tempdir()
  seen <- NULL
  local_mocked_bindings(lc_manim_command = function() "/fake/manim",
                        lc_run = function(cmd, args, ...) { seen <<- args; list(stdout = "", stderr = "") })
  expect_error(lc_manim_run(f$paths, f$spec, c(x = 0L, y = 0L, w = 320L, h = 180L), f$cfg, media), "no section list")
  expect_false("--background_color" %in% seen)
  cf <- seen[which(seen == "--config_file") + 1]
  expect_equal(readLines(cf), c("[CLI]", "background_color = #1e1e1e"))
})

test_that("the section list keeps sections with video, in scene order", {
  dir <- withr::local_tempdir()
  json <- file.path(dir, "Tiny.json")
  writeLines('[{"name": "autocreated", "video": null}, {"name": "grow", "video": "Tiny_0001.mp4"}]', json)
  s <- lc_manim_sections(json, list(scene = "Tiny"), "tiny.py")
  expect_equal(s$name, "grow")
  expect_equal(s$file, file.path(dir, "Tiny_0001.mp4"))
})

test_that("a scene with no animations or duplicate names stops", {
  dir <- withr::local_tempdir()
  json <- file.path(dir, "Tiny.json")
  writeLines('[{"name": "autocreated", "video": null}]', json)
  expect_error(lc_manim_sections(json, list(scene = "Tiny"), "tiny.py"), "has no animations")
  writeLines('[{"name": "Grow", "video": "a.mp4"}, {"name": "grow.", "video": "b.mp4"}]', json)
  expect_error(lc_manim_sections(json, list(scene = "Tiny"), "tiny.py"), "two sections named")
  writeLines('{"unexpected": true}', json)
  expect_error(lc_manim_sections(json, list(scene = "Tiny"), "tiny.py"), "not in the form")
})

test_that("a render is stored once and reused", {
  skip_if_no_ffmpeg()
  local_mocked_bindings(lc_manim_engine = function() "manim==test")
  f <- manim_fixture()
  cache <- withr::local_tempdir()
  calls <- 0
  local_mocked_bindings(lc_manim_run = function(...) { calls <<- calls + 1; fake_manim_run(...) })
  rect <- c(x = 0L, y = 0L, w = 320L, h = 180L)
  a <- lc_manim_render(f$paths, f$spec, rect, f$cfg, cache)
  b <- lc_manim_render(f$paths, f$spec, rect, f$cfg, cache)
  expect_equal(calls, 1)
  expect_false(attr(a, "cached"))
  expect_true(attr(b, "cached"))
  expect_equal(b$name, c("autocreated", "grow", "spin"))
  expect_equal(b$seconds, c(0.5, 0.5, 0.5), tolerance = 0.05)
  expect_true(all(startsWith(b$file, file.path(cache, "manim"))))
})

test_that("a render of the wrong size stops the build", {
  skip_if_no_ffmpeg()
  local_mocked_bindings(lc_manim_engine = function() "manim==test")
  f <- manim_fixture()
  local_mocked_bindings(lc_manim_run = function(paths, spec, rect, cfg, media) {
    fake_manim_run(paths, spec, c(x = 0L, y = 0L, w = 200L, h = 100L), cfg, media)
  })
  expect_error(lc_manim_render(f$paths, f$spec, c(x = 0L, y = 0L, w = 320L, h = 180L), f$cfg, withr::local_tempdir()),
               "Manim rendered 200x100, expected 320x180")
})

test_that("a damaged cached render stops with the folder to delete", {
  skip_if_no_ffmpeg()
  local_mocked_bindings(lc_manim_engine = function() "manim==test")
  f <- manim_fixture()
  cache <- withr::local_tempdir()
  local_mocked_bindings(lc_manim_run = fake_manim_run)
  rect <- c(x = 0L, y = 0L, w = 320L, h = 180L)
  r <- lc_manim_render(f$paths, f$spec, rect, f$cfg, cache)
  file.remove(r$file[2])
  expect_error(lc_manim_render(f$paths, f$spec, rect, f$cfg, cache), "cached section video is missing")
})

test_that("a cached index with bad values stops with the folder to delete", {
  skip_if_no_ffmpeg()
  local_mocked_bindings(lc_manim_engine = function() "manim==test", lc_manim_run = fake_manim_run)
  f <- manim_fixture()
  cache <- withr::local_tempdir()
  rect <- c(x = 0L, y = 0L, w = 320L, h = 180L)
  r <- lc_manim_render(f$paths, f$spec, rect, f$cfg, cache)
  index <- file.path(dirname(r$file[1]), "sections.json")
  m <- jsonlite::fromJSON(index)
  m$sections$seconds[1] <- NA
  writeLines(jsonlite::toJSON(m, dataframe = "rows", auto_unbox = TRUE, na = "null"), index)
  err <- expect_error(lc_manim_render(f$paths, f$spec, rect, f$cfg, cache), "damaged")
  expect_match(conditionMessage(err), "Delete the folder", fixed = TRUE)
})

test_that("a failed manim run shows its error and the fix", {
  skip_on_os("windows")
  f <- manim_fixture()
  local_mocked_bindings(lc_manim_command = function() c("/bin/sh", "-c", "echo 'LaTeX error: latex not found' >&2; exit 1", "manim"))
  err <- expect_error(lc_manim_run(f$paths, f$spec, c(x = 0L, y = 0L, w = 320L, h = 180L), f$cfg, withr::local_tempdir()),
                      "latex not found")
  expect_match(conditionMessage(err), "lecturecast_check", fixed = TRUE)
})

test_that("a run that writes no section list names the class", {
  skip_on_os("windows")
  f <- manim_fixture()
  local_mocked_bindings(lc_manim_command = function() c("/bin/sh", "-c", "exit 0", "manim"))
  expect_error(lc_manim_run(f$paths, f$spec, c(x = 0L, y = 0L, w = 320L, h = 180L), f$cfg, withr::local_tempdir()),
               "wrote no section list for scene Tiny")
})

test_that("with Manim off, a cached render is found without running Manim", {
  skip_if_no_ffmpeg()
  local_mocked_bindings(lc_manim_engine = function() "manim==test", lc_manim_run = fake_manim_run)
  f <- manim_fixture()
  cache <- withr::local_tempdir()
  rect <- c(x = 0L, y = 0L, w = 320L, h = 180L)
  expect_null(lc_manim_lookup(f$paths, f$spec, rect, f$cfg, cache))
  lc_manim_render(f$paths, f$spec, rect, f$cfg, cache)
  local_mocked_bindings(lc_manim_run = function(...) stop("not called"))
  expect_equal(lc_manim_lookup(f$paths, f$spec, rect, f$cfg, cache)$name, c("autocreated", "grow", "spin"))
})

test_that("with Manim off and no Manim installed, the lookup finds nothing and does not stop", {
  f <- manim_fixture()
  local_mocked_bindings(lc_find_tool = function(tool) "")
  expect_null(lc_manim_lookup(f$paths, f$spec, c(x = 0L, y = 0L, w = 320L, h = 180L), f$cfg, withr::local_tempdir()))
})

ff <- function(...) processx::run("ffmpeg", c("-y", "-loglevel", "error", ...))

# RGB of one pixel of an image or the first frame of a video. A 2x2 crop
# scaled to one pixel, because a 1x1 crop of yuv420 video has no chroma.
pixel <- function(file, x, y) {
  raw <- tempfile(fileext = ".rgb")
  ff("-i", file, "-frames:v", "1", "-vf", sprintf("crop=2:2:%d:%d,scale=1:1,format=rgb24", x, y), "-f", "rawvideo", raw)
  as.integer(readBin(raw, "raw", 3))
}

test_that("every frame of a section becomes a picture", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  v <- file.path(dir, "s.mp4")
  ff("-f", "lavfi", "-i", "testsrc=s=160x90:r=10:d=1", "-pix_fmt", "yuv420p", v)
  fr <- lc_frames(v, file.path(dir, "frames"), "s01-001", 10)
  expect_length(fr$files, 10)
  expect_equal(fr$seconds, 0.1)
})

test_that("frames left from an earlier, longer render are removed", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  v <- file.path(dir, "s.mp4")
  ff("-f", "lavfi", "-i", "testsrc=s=160x90:r=10:d=1", "-pix_fmt", "yuv420p", v)
  dir.create(file.path(dir, "frames"))
  file.create(file.path(dir, "frames", sprintf("s01-001-%05d.png", 1:30)))
  expect_length(lc_frames(v, file.path(dir, "frames"), "s01-001", 10)$files, 10)
})

test_that("a section cued while the one before is still playing waits for it", {
  cfg <- lecturecast_config(config = write_config(c("voice:", "  provider: edge", "video:", "  lead_in: 0", "  fps: 10"),
                                                  dir = withr::local_tempdir()))
  ev <- data.frame(label = c("a", "b"), pos = c(0, 4))
  cap <- list(list(files = sprintf("a%02d", 1:30), seconds = 0.1), list(files = "b01", seconds = 0.1))
  s <- lc_animation_schedule("still", ev, cap, "aaaa bbbb", NULL, 2, cfg)
  # "b" is cued at 1 s, but "a" runs 3 s, so "b" shows at 3 s.
  expect_equal(sum(s$seconds[seq_len(which(s$files == "b01")[1] - 1)]), 3, tolerance = 1e-6)
})

test_that("the last frame of a section video becomes a picture", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  v <- file.path(dir, "s.mp4")
  ff("-f", "lavfi", "-i", "color=c=red:s=160x90:r=10:d=0.5", "-f", "lavfi", "-i", "color=c=blue:s=160x90:r=10:d=0.5",
     "-filter_complex", "[0:v][1:v]concat=n=2:v=1[v]", "-map", "[v]", "-pix_fmt", "yuv420p", v)
  out <- lc_last_frame(v, file.path(dir, "last.png"))
  expect_gt(pixel(out, 80, 45)[3], 180)
})

test_that("timing notes flag a long still picture and a scene that outruns the narration", {
  cfg <- lecturecast_config(config = write_config(c("voice:", "  provider: edge", "video:", "  lead_in: 0.3", "  tail: 0.5"),
                                                  dir = withr::local_tempdir()))
  fine <- list(files = c("a", "b"), seconds = c(5, 5.8), total = 10.8)
  expect_length(lc_manim_timing_notes(fine, 10, cfg), 0)
  frozen <- list(files = c("a", "b"), seconds = c(2, 40.8), total = 42.8)
  expect_match(lc_manim_timing_notes(frozen, 42, cfg), "still for about 41 s")
  long <- list(files = c("a", "b"), seconds = c(1, 13.8), total = 14.8)
  expect_match(lc_manim_timing_notes(long, 10, cfg), "runs about 4 s past the narration")
})

test_that("a still lays the scene frame over the slide at the box", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  base <- file.path(dir, "base.png"); top <- file.path(dir, "top.png")
  ff("-f", "lavfi", "-i", "color=c=white:s=320x180", "-frames:v", "1", base)
  ff("-f", "lavfi", "-i", "color=c=red:s=80x60", "-frames:v", "1", top)
  out <- lc_overlay_png(base, top, c(x = 100L, y = 40L, w = 80L, h = 60L), file.path(dir, "out.png"))
  inside <- pixel(out, 140, 70); outside <- pixel(out, 10, 10)
  expect_gt(inside[1], 200); expect_lt(inside[2], 60)
  expect_true(all(outside > 200))
})

test_that("a Manim clip has the scene in its box, the narration and the planned length", {
  skip_if_no_ffmpeg()
  dir <- withr::local_tempdir()
  cfg <- lecturecast_config(config = write_config(c("voice:", "  provider: edge", "video:", "  resolution: 720p", "  lead_in: 0.3"), dir = dir))
  base <- file.path(dir, "base.png"); top <- file.path(dir, "top.png"); audio <- file.path(dir, "a.mp3")
  ff("-f", "lavfi", "-i", "color=c=white:s=1280x720", "-frames:v", "1", base)
  ff("-f", "lavfi", "-i", "color=c=blue:s=400x200", "-frames:v", "1", top)
  ff("-f", "lavfi", "-i", "sine=duration=1", audio)
  sched <- list(files = top, seconds = 2, total = 2)
  rect <- c(x = 100L, y = 100L, w = 400L, h = 200L)
  d <- lc_manim_clip(sched, base, rect, file.path(dir, "clip.mp4"), cfg, audio = audio)
  expect_equal(d, 2, tolerance = 0.1)
  expect_equal(lc_dimensions(file.path(dir, "clip.mp4"), "t"), c(1280L, 720L))
  expect_gt(pixel(file.path(dir, "clip.mp4"), 300, 200)[3], 180)
  expect_true(all(pixel(file.path(dir, "clip.mp4"), 50, 50) > 200))
  silent <- lc_manim_clip(sched, base, rect, file.path(dir, "silent.mp4"), cfg)
  expect_equal(silent, 2, tolerance = 0.1)
})
