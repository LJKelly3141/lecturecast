# Video chapters, in the form YouTube reads from a description: one line
# per chapter, "m:ss Title", the first at 0:00, each at least 10 seconds.
# A section divider (a level-one heading) starts the chapter of the slide
# after it. Slides with the same title in a row are one chapter. A chapter
# too short is folded into the next (the last into the one before).
lc_video_chapters <- function(slides, segs, total, min_seconds = 10) {
  first <- !duplicated(segs$slide)
  ch <- data.frame(slide = segs$slide[first], start = segs$start[first], stringsAsFactors = FALSE)
  s <- slides[match(ch$slide, slides$index), ]
  ch$title <- ifelse(nzchar(s$title), s$title, paste("Slide", ch$slide))
  ch$title[lc_flag(s$title_slide)] <- "Introduction"
  ch$section <- lc_flag(s$section)
  # A divider gives its start to the slide after it.
  for (i in seq_len(nrow(ch) - 1)) {
    if (ch$section[i]) {
      ch$start[i + 1] <- ch$start[i]
      ch$section[i] <- NA
    }
  }
  ch <- ch[!is.na(ch$section), c("start", "title")]
  ch$start <- floor(ch$start)
  ch$start[1] <- 0
  keep <- c(TRUE, ch$title[-1] != ch$title[-nrow(ch)])
  ch <- ch[keep, ]
  repeat {
    n <- nrow(ch)
    if (n < 2) break
    len <- c(ch$start[-1], floor(total)) - ch$start
    short <- which(len < min_seconds)
    if (length(short) == 0) break
    k <- short[1]
    if (k == n) {
      ch <- ch[-n, ]
    } else {
      ch$start[k + 1] <- ch$start[k]
      ch <- ch[-k, ]
    }
  }
  rownames(ch) <- NULL
  ch
}

lc_flag <- function(x) if (is.null(x)) FALSE else !is.na(x) & x

lc_chapter_time <- function(s) {
  s <- floor(s)
  if (s >= 3600) sprintf("%d:%02d:%02d", s %/% 3600, (s %% 3600) %/% 60, s %% 60) else sprintf("%d:%02d", s %/% 60, s %% 60)
}

lc_chapter_lines <- function(ch) paste(vapply(ch$start, lc_chapter_time, ""), ch$title)

lc_write_video_chapters <- function(ch, file) {
  writeLines(enc2utf8(lc_chapter_lines(ch)), file, useBytes = TRUE)
  invisible(file)
}

# The thumbnail: the chosen slide as it is when finished (after its
# fragments and animations), as a 1280x720 JPEG under YouTube's 2 MB limit.
lc_write_thumbnail <- function(segs, slide, file) {
  step <- "thumbnail"
  rows <- which(segs$slide == slide)
  if (length(rows) == 0) rows <- which(segs$slide == segs$slide[1])
  png <- (segs$png_out %||% segs$png)[max(rows)]
  lc_run(lc_tool("ffmpeg", step), c("-y", "-hide_banner", "-loglevel", "error", "-i", png,
                                     "-vf", "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:white",
                                     "-q:v", "2", "-f", "image2", file), step = step, file = file)
  if (!identical(lc_dimensions(file, step), c(1280L, 720L))) lc_abort(step, "The thumbnail is not 1280x720.", file = file)
  if (file.size(file) > 2e6) lc_abort(step, "The thumbnail is over YouTube's 2 MB limit.", file = file)
  invisible(file)
}
