test_that("each slide with notes is one segment", {
  segs <- lc_segments(fake_slides(c("One.", "Two.")))
  expect_equal(segs$id, c("s01", "s02"))
  expect_equal(segs$text, c("One.", "Two."))
  expect_true(all(is.na(segs$silent)))
  expect_equal(segs$fragment, c(-1L, -1L))
})

test_that("a slide without notes stops the build and is named", {
  err <- expect_error(lc_segments(fake_slides(c("One.", "", ""), titles = c("A", "B", "C"))),
                      class = "lecturecast_error")
  expect_match(conditionMessage(err), "2 \\(B\\), 3 \\(C\\)")
})

test_that("silent slides need a duration, by number, title or attribute", {
  sl <- fake_slides(c("", "Two.", ""), titles = c("Title", "Body", "End"))
  segs <- lc_segments(sl, silent = list("1" = 4, End = 2))
  expect_equal(segs$silent, c(4, NA, 2))
  sl$silent[1] <- 3
  segs <- lc_segments(sl, silent = list(End = 2))
  expect_equal(segs$silent[1], 3)
})

test_that("a silent mark on a slide with notes is an error", {
  expect_error(lc_segments(fake_slides(c("One.")), silent = list("1" = 3)), "also marked silent")
})

test_that("a silent key that matches nothing is an error", {
  expect_error(lc_segments(fake_slides(c("One.")), silent = list(Nope = 3)), "matches no slide")
  expect_error(lc_segments(fake_slides(c("")), silent = list("1" = "soon")), "number of seconds")
})

test_that("notes split into fragment parts on --- lines", {
  sl <- fake_slides("Intro.\n\n---\n\nFirst point.\n\n---\n\nSecond point.", n_fragments = 2L)
  segs <- lc_segments(sl, split_fragments = TRUE)
  expect_equal(segs$id, c("s01-1", "s01-2", "s01-3"))
  expect_equal(segs$fragment, c(-1L, 0L, 1L))
  expect_equal(segs$text, c("Intro.", "First point.", "Second point."))
})

test_that("a wrong number of fragment parts is an error", {
  sl <- fake_slides("Intro.\n\n---\n\nFirst point.", n_fragments = 2L)
  expect_error(lc_segments(sl, split_fragments = TRUE), "need 3 parts, but they have 2")
})

test_that("unsplit notes play with every fragment shown", {
  segs <- lc_segments(fake_slides("All at once.", n_fragments = 3L), split_fragments = TRUE)
  expect_equal(segs$fragment, 2L)
})

test_that("fragment steps count shared indices once", {
  expect_equal(lc_fragment_steps(list()), 0L)
  expect_equal(lc_fragment_steps(list(NULL, NULL)), 2L)
  expect_equal(lc_fragment_steps(list(1, 1, 2)), 2L)
})

test_that("notes are tidied into paragraphs", {
  expect_equal(lc_clean_notes("  First   line\n\n\nSecond line  "), "First line\n\nSecond line")
  expect_equal(lc_clean_notes(""), "")
})

test_that("a deck must be a .qmd or a rendered .html", {
  f <- withr::local_tempfile(fileext = ".md")
  file.create(f)
  expect_error(lc_check_deck(f), "needs a deck's .qmd or its rendered .html")
  expect_error(lc_check_deck("no/such/file.html"), "not found")
})

make_project <- function(quarto = c("project:", "  type: default", "  output-dir: docs"),
                         env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  if (length(quarto)) writeLines(quarto, file.path(root, "_quarto.yml"))
  dir.create(file.path(root, "slides", "week1"), recursive = TRUE)
  qmd <- file.path(root, "slides", "week1", "deck.qmd")
  writeLines("---\ntitle: x\n---", qmd)
  list(root = normalizePath(root), qmd = qmd)
}

test_that("a .qmd maps to its render under the project's output-dir", {
  p <- make_project()
  html <- file.path(p$root, "docs", "slides", "week1", "deck.html")
  dir.create(dirname(html), recursive = TRUE)
  file.create(html)
  Sys.setFileTime(p$qmd, Sys.time() - 60)
  expect_equal(lc_check_deck(p$qmd), normalizePath(html))
})

test_that("with no output-dir the render sits beside the .qmd", {
  p <- make_project(c("project:", "  type: default"))
  html <- sub("qmd$", "html", p$qmd)
  file.create(html)
  Sys.setFileTime(p$qmd, Sys.time() - 60)
  expect_equal(lc_check_deck(p$qmd), normalizePath(html))
  q <- make_project(character(0))
  file.create(sub("qmd$", "html", q$qmd))
  Sys.setFileTime(q$qmd, Sys.time() - 60)
  expect_match(lc_check_deck(q$qmd), "deck\\.html$")
})

test_that("a missing or stale render stops with the fix", {
  p <- make_project(c("project:", "  output-dir: docs", "  render:", "    - index.qmd"))
  expect_error(lc_check_deck(p$qmd), "has not been rendered")
  expect_error(lc_check_deck(p$qmd), "slides/\\*\\*/\\*.qmd")
  html <- file.path(p$root, "docs", "slides", "week1", "deck.html")
  dir.create(dirname(html), recursive = TRUE)
  file.create(html)
  Sys.setFileTime(html, Sys.time() - 60)
  expect_error(lc_check_deck(p$qmd), "older than its .qmd")
})

test_that("a deck with nothing to voice stops at the script step", {
  expect_error(lc_segments(fake_slides(c("", "")), silent = list("1" = 2, "2" = 2)), "nothing to voice")
})
