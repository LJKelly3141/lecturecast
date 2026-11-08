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
  expect_equal(unname(b), c(102L, 50L, 802L, 452L))
  expect_equal(names(b), c("x", "y", "w", "h"))
  edge <- lc_manim_box(list(x = 1800, y = 0, w = 400, h = 200), c(1920L, 1080L), 1, "d.html")
  expect_equal(unname(edge[["w"]]), 120L)
})

test_that("a box with no size stops with a fix", {
  expect_error(lc_manim_box(list(x = 10, y = 10, w = 900, h = 0), c(1920L, 1080L), 4, "d.html"),
               "slide 4 is 900x0 pixels")
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
