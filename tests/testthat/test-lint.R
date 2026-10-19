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

test_that("clean notes and ordinary words pass", {
  slides <- fake_slides(c("When spending falls, output drops with it.",
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
  expect_error(lint_notes(f, max_still = -1), "max_still")
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


with_buttons <- function(slides, i, labels) {
  slides$buttons <- rep(list(NULL), nrow(slides))
  slides$buttons[[i]] <- data.frame(plot = 0L, menu = 0L, button = seq_along(labels) - 1L,
                                    label = labels, method = "animate", stringsAsFactors = FALSE)
  slides
}

test_that("a slide with nothing said is dead air, and the title slide gets its own fix", {
  out <- lc_lint_slides(fake_slides(c("", "Hello.", ""), silent = c(2, NA, 3)))
  expect_equal(out$issue, c("dead air", "dead air"))
  expect_equal(out$found, c("silent 2 s", "silent 3 s"))
  expect_match(out$advice[1], "title-slide-attributes")
  expect_match(out$advice[2], "one-sentence transition")
})

test_that("chart buttons the narration never quotes are reported", {
  slides <- with_buttons(fake_slides("Watch \u201cAD falls\u201d now."), 1, c("Start", "AD falls", "AD rises"))
  out <- lc_lint_slides(slides)
  expect_equal(out$found[out$issue == "animation not cued"], "\"AD rises\"")
})

# The pacing tests repeat one filler sentence, so they set repetition aside.
lint_pacing <- function(...) {
  out <- lc_lint_slides(...)
  out[out$issue != "repetition", ]
}

test_that("a long stretch of narration over an unchanging picture is reported", {
  long <- paste(rep("This sentence explains the idea at some length for listeners.", 12), collapse = " ")
  out <- lint_pacing(fake_slides(long))
  expect_equal(out$issue, "static slide")
  expect_match(out$found, "about 46 s unchanged")
  expect_match(out$advice, "Show, don't just tell")
  half <- paste(rep("This sentence explains the idea at some length for listeners.", 6), collapse = " ")
  cued <- with_buttons(fake_slides(paste(half, "Now \"Play\" it.", half)), 1, "Play")
  expect_false("static slide" %in% lint_pacing(cued)$issue)
  stepped <- fake_slides(paste0(half, "\n\n---\n\n", half), n_fragments = 1L)
  expect_false("static slide" %in% lint_pacing(stepped)$issue)
  unstepped <- fake_slides(paste0(half, "\n\n---\n\n", half))
  expect_true("static slide" %in% lint_pacing(unstepped)$issue)
  expect_false("static slide" %in% lint_pacing(fake_slides(long), max_still = 60)$issue)
})


test_that("walking through an animation after it plays asks for step buttons", {
  half <- paste(rep("This sentence explains the idea at some length for listeners.", 9), collapse = " ")
  slides <- with_buttons(fake_slides(paste("Now \"Tariff\" plays all three steps.", half)), 1, c("Start", "Tariff"))
  out <- lint_pacing(slides)
  expect_equal(out$issue, "static after animation")
  expect_match(out$advice, "a button for each step")
  before <- with_buttons(fake_slides(paste(half, "Now \"Tariff\" plays.")), 1, c("Start", "Tariff"))
  expect_equal(lint_pacing(before)$issue, "static slide")
})

test_that("a content word in back-to-back sentences is a repetition", {
  slides <- fake_slides(c(
    "This is what you will learn by the end of this course. In this course, you will work with real data.",
    "Sticky wages slow the recovery. Wages are sticky because of contracts.",
    "Demand falls. Falling demand cuts output. Output then recovers."
  ), titles = c("Welcome", "Sticky wages", "A shock"))
  out <- lc_lint_slides(slides)
  r <- out[out$issue == "repetition", ]
  expect_equal(r$slide, c(1L, 3L, 3L))
  expect_equal(r$found, c("course", "falling demand", "output"))
  expect_match(r$advice[1], "twice in a row")
})

test_that("function words and words far apart are not repetitions", {
  expect_equal(lc_repeated_words("They would rather wait.", "They would not."), character(0))
  slides <- fake_slides("Prices rise. Then output falls. Later, prices settle.")
  expect_false("repetition" %in% lc_lint_slides(slides)$issue)
  far <- fake_slides("Demand drives output in the short run, said Keynes. Over a decade, though, demand matters less.")
  expect_false("repetition" %in% lc_lint_slides(far)$issue)
  near <- fake_slides("By the end of this course. In this course, you will work.")
  expect_true("repetition" %in% lc_lint_slides(near)$issue)
  expect_false("repetition" %in% lc_lint_slides(near, repeat_gap = 0)$issue)
})

test_that("a content word said twice in one sentence is a repetition", {
  said <- c(
    "This one is about the shape of the data: what a single average hides, and the charts that show what it hides.",
    "A histogram sorts the values into bins of equal width, counts each bin, and draws the counts as bars.",
    "Every two weeks, the Census Bureau asks firms whether they used artificial intelligence in the last two weeks.",
    "Florida’s is narrow: the survey pins Florida down closely.",
    "Wilke explains that a proper comparison works with the difference itself, and the uncertainty of that difference."
  )
  expect_equal(lapply(said, lc_repeated_within), list("hides", "counts", "weeks", "florida", "difference"))
  out <- lc_lint_slides(fake_slides(said[1]))
  expect_equal(out$issue, "repetition")
  expect_match(out$advice, "twice in one sentence")
  expect_equal(nrow(lc_lint_slides(fake_slides(said[1]), repeat_gap = 0)), 0)
})

test_that("spoken numbers, quoted labels and short words are not repetitions in a sentence", {
  expect_equal(lc_repeated_within("It rose from twenty-two point three to thirty-six point four percent, then forty point one percent."),
               character(0))
  expect_equal(lc_repeated_within("Press \"Show values\" and the values appear."), character(0))
  expect_equal(lc_repeated_within("The data fit, and the data agree."), character(0))
})

test_that("a deck's title-slide notes are linted", {
  skip_on_cran()
  skip_on_ci()
  skip_if(!nzchar(Sys.which("quarto")), "Quarto not installed")
  skip_if(!nzchar(lc_find_chrome()), "Chrome not found")
  dir <- withr::local_tempdir()
  writeLines(c("---", "title: \"Shape\"", "format: revealjs", "title-slide-attributes:",
               "  data-notes: \"This is about what an average hides, and the charts that show what it hides.\"",
               "---", "", "## One", "", "::: notes", "Plain words here.", ":::"), file.path(dir, "ts.qmd"))
  processx::run("quarto", c("render", "ts.qmd"), wd = dir)
  out <- lint_notes(file.path(dir, "ts.html"), quiet = TRUE)
  expect_equal(out$slide, 1L)
  expect_equal(out$found, "hides")
})
