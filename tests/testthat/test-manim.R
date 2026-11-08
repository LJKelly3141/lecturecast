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
