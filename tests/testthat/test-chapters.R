chapter_slides <- function(titles, section = FALSE, title_slide = FALSE) {
  s <- fake_slides(rep("x", length(titles)), titles = titles)
  s$section <- rep_len(section, length(titles))
  s$title_slide <- rep_len(title_slide, length(titles))
  s
}

test_that("chapters start at 0:00 and fold section dividers into the next slide", {
  slides <- chapter_slides(c("Deck", "Part one", "Opening", "Next", "Part two", "Last"),
                           section = c(FALSE, TRUE, FALSE, FALSE, TRUE, FALSE),
                           title_slide = c(TRUE, rep(FALSE, 5)))
  segs <- data.frame(slide = 1:6, start = c(4, 30, 36, 80, 140, 146))
  ch <- lc_video_chapters(slides, segs, total = 200)
  expect_equal(ch$title, c("Introduction", "Opening", "Next", "Last"))
  expect_equal(ch$start, c(0, 30, 80, 140))
  expect_equal(lc_chapter_lines(ch), c("0:00 Introduction", "0:30 Opening", "1:20 Next", "2:20 Last"))
})

test_that("consecutive dividers chain to the slide after them", {
  slides <- chapter_slides(c("A", "S1", "S2", "B"), section = c(FALSE, TRUE, TRUE, FALSE))
  segs <- data.frame(slide = 1:4, start = c(0, 20, 25, 30))
  expect_equal(lc_video_chapters(slides, segs, 100)$start, c(0, 20))
})

test_that("short chapters fold into the next, and the last into the one before", {
  slides <- chapter_slides(c("A", "B", "C", "D"))
  segs <- data.frame(slide = 1:4, start = c(0, 30, 35, 95))
  ch <- lc_video_chapters(slides, segs, total = 100)
  # B is 5 s, so C starts at 0:30; D is 5 s, so it joins C.
  expect_equal(ch$title, c("A", "C"))
  expect_equal(ch$start, c(0, 30))
})

test_that("repeated titles and several segments per slide make one chapter", {
  slides <- chapter_slides(c("A", "A", "B"))
  segs <- data.frame(slide = c(1, 1, 2, 3), start = c(0, 15, 30, 60))
  ch <- lc_video_chapters(slides, segs, 90)
  expect_equal(ch$title, c("A", "B"))
  expect_equal(ch$start, c(0, 60))
})

test_that("untitled slides and long videos are written plainly", {
  slides <- chapter_slides(c("", "B"))
  segs <- data.frame(slide = 1:2, start = c(0, 3725))
  expect_equal(lc_chapter_lines(lc_video_chapters(slides, segs, 4000)), c("0:00 Slide 1", "1:02:05 B"))
})

test_that("slides without the section columns still give chapters", {
  slides <- fake_slides(c("x", "y"), titles = c("A", "B"))
  segs <- data.frame(slide = 1:2, start = c(2, 40))
  expect_equal(lc_video_chapters(slides, segs, 90)$start, c(0, 40))
})
