test_that("each kind of issue is found and named", {
  slides <- fake_slides(c(
    "Output falls 5% when AD₁ shifts left.",
    "Prices are sticky, e.g. wages and menus, etc.",
    "See www.bea.gov for the data.",
    "So the room can see it, I'll click \"AD falls\".",
    paste(rep("word", 31), collapse = " ")
  ))
  out <- lc_lint_slides(slides)
  expect_equal(out$slide[out$issue == "acronym"], c(1L, 4L))
  out <- out[out$issue != "acronym", ]
  expect_equal(out$issue, c("symbol", "abbreviation", "link", "room", "long sentence"))
  expect_equal(out$slide, 1:5)
  expect_equal(out$found[1], "% ₁")
  expect_equal(out$found[2], "e.g. etc.")
  expect_equal(out$found[4], "the room click")
  expect_equal(out$found[5], "31 words")
  expect_true(all(nzchar(out$advice)))
})

test_that("clean notes, silent slides and ordinary words pass", {
  slides <- fake_slides(c("When spending falls, output falls with it.", "",
                          "Real GDP and the price level move together. The classroom example still works."))
  expect_equal(nrow(lc_lint_slides(slides)), 0)
})

test_that("fragment separators are not read as symbols and sentences split per step", {
  slides <- fake_slides("First point.\n\n---\n\nSecond point.", n_fragments = 1L)
  expect_equal(nrow(lc_lint_slides(slides)), 0)
})

test_that("the sentence limit is a setting", {
  slides <- fake_slides("One two three four five six.")
  expect_equal(nrow(lc_lint_slides(slides, max_words = 30)), 0)
  expect_equal(lc_lint_slides(slides, max_words = 5)$issue, "long sentence")
})

test_that("a slash between words is a symbol", {
  expect_equal(lc_lint_slides(fake_slides("Use and/or here."))$found, "/")
  expect_equal(nrow(lc_lint_slides(fake_slides("Use one or the other."))), 0)
})

test_that("lint_notes checks its arguments before opening Chrome", {
  expect_error(lint_notes("missing.html"), "Deck file not found")
  f <- withr::local_tempfile(fileext = ".html")
  file.create(f)
  expect_error(lint_notes(f, max_words = 0), "max_words")
})

test_that("lint_notes reads a real deck", {
  skip_on_cran()
  skip_on_ci()
  skip_if(!nzchar(Sys.which("quarto")), "Quarto not installed")
  skip_if(!nzchar(lc_find_chrome()), "Chrome not found")
  dir <- withr::local_tempdir()
  file.copy(test_path("fixtures", "fragments.qmd"), dir)
  processx::run("quarto", c("render", "fragments.qmd"), wd = dir)
  out <- lint_notes(file.path(dir, "fragments.html"), quiet = TRUE)
  expect_s3_class(out, "data.frame")
  expect_named(out, c("slide", "title", "issue", "found", "sentence", "advice"))
  expect_equal(lint_notes(file.path(dir, "fragments.qmd"), quiet = TRUE), out)
})

test_that("economics and statistics abbreviations come with the words to say", {
  out <- lc_lint_slides(fake_slides("When AD falls, SRAS stays put and MPCs differ."))
  expect_equal(out$issue, "acronym")
  expect_equal(out$found, "AD SRAS MPC")
  expect_match(out$advice, "SRAS as \"short-run aggregate supply\"")
  expect_match(out$advice, "AD as \"aggregate demand\"")
  out <- lc_lint_slides(fake_slides("The SE and the 95 CI come from OLS with 3 df."))
  expect_equal(out$found, "SE CI OLS df")
})

test_that("ordinary words and letter-spoken abbreviations are not flagged as acronyms", {
  ok <- c("As GDP rose, the CPI and the Fed held.", "Advertising has a bad name, as does Ha.",
"The SDK and MCAT are unrelated.")
  out <- lc_lint_slides(fake_slides(ok))
  expect_false("acronym" %in% out$issue)
})

test_that("an abbreviation next to a subscript is still found", {
  out <- lc_lint_slides(fake_slides("Then AD₁ shifts left."))
  expect_true("acronym" %in% out$issue)
})

test_that("the lecture-video skill's spoken forms match the lint list", {
  skill <- system.file("skills", "lecture-video", "SKILL.md", package = "lecturecast")
  skip_if(!nzchar(skill), "skill not installed")
  rows <- grep("^\\| [A-Za-z0-9]+ \\| [^|]+ \\|$", readLines(skill), value = TRUE)
  parts <- strsplit(sub("^\\| ", "", sub(" \\|$", "", rows)), " | ", fixed = TRUE)
  table <- setNames(vapply(parts, `[`, "", 2), vapply(parts, `[`, "", 1))[-1]
  expect_equal(table, lc_spoken_forms)
})
