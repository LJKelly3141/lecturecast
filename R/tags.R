# Play tags. A tag such as [play: AD falls] in the notes marks exactly where
# a chart button plays. The voice never reads it. The narration is voiced in
# pieces split at the tags, so each animation starts at its tag, and the
# narration waits for it to finish before going on. [play: AD falls, over]
# lets the narration carry on while the chart plays.

# A label may hold commas ("7,000 pounds"); only a final ", over" is the
# modifier.
lc_tag_regex <- "(?i)\\[\\s*play\\s*:\\s*([^\\]\\n]+?)\\s*(,\\s*over\\s*)?\\]"

# Split a segment's text at its tags. Returns the spoken text (tags
# removed), the pieces between tags (one more than the tags, possibly
# empty), and a data frame of tags: label, over, and pos (non-space
# characters of spoken text before the tag).
lc_parse_tags <- function(text) {
  text <- enc2utf8(text)
  m <- gregexpr(lc_tag_regex, text, perl = TRUE)[[1]]
  none <- data.frame(label = character(0), over = logical(0), pos = numeric(0), stringsAsFactors = FALSE)
  if (m[1] == -1) return(list(text = text, pieces = text, tags = none))
  raw <- regmatches(text, list(m))[[1]]
  label <- trimws(sub(lc_tag_regex, "\\1", raw, perl = TRUE))
  over <- grepl(",\\s*over\\s*\\]$", raw, ignore.case = TRUE, perl = TRUE)
  marked <- text
  regmatches(marked, list(m)) <- list(rep("\001", length(m)))
  pieces <- strsplit(marked, "\001", fixed = TRUE)[[1]]
  if (length(pieces) < length(m) + 1) pieces <- c(pieces, rep("", length(m) + 1 - length(pieces)))
  pieces <- lc_tidy_spaces(pieces)
  spoken <- lc_tidy_spaces(gsub("\001", " ", marked, fixed = TRUE))
  pos <- cumsum(lc_nows(pieces))[seq_along(m)]
  list(text = spoken, pieces = pieces,
       tags = data.frame(label = label, over = over, pos = pos, stringsAsFactors = FALSE))
}

# Collapse runs of spaces left where a tag was, keeping paragraph breaks.
lc_tidy_spaces <- function(x) {
  x <- gsub("[ \t]+", " ", x)
  x <- gsub(" *\n *", "\n", x)
  trimws(x)
}

# Tag events for one segment, in the shape lc_segment_events() returns,
# plus `over`. An unknown label stops the build with the slide's labels.
lc_tag_events <- function(tags, buttons, slide, title, deck) {
  key <- if (is.null(buttons) || nrow(buttons) == 0) character(0) else lc_label_key(buttons$label)
  hit <- match(lc_label_key(tags$label), key)
  if (anyNA(hit)) {
    have <- if (length(key)) paste(sprintf("\"%s\"", buttons$label), collapse = ", ") else "none"
    lc_abort("script", sprintf("Slide %d (%s) has [play: %s], but no chart button on the slide has that label.",
                               slide, title, tags$label[is.na(hit)][1]),
             file = deck, fix = paste0("Use one of the slide's button labels: ", have, "."))
  }
  data.frame(label = buttons$label[hit], plot = buttons$plot[hit], menu = buttons$menu[hit],
             button = buttons$button[hit], pos = tags$pos, over = tags$over, stringsAsFactors = FALSE)
}

# Voice a tagged segment in pieces and lay them out around its animations.
# Returns the joined narration (a .wav), its timing, the time each
# animation starts (seconds into the narration), and whether every piece
# came from the cache.
lc_voice_tagged <- function(pieces, events, captured, voice_piece, cfg, work_base) {
  step <- "voice (tags)"
  v <- cfg$video
  n <- length(pieces)
  files <- character(n)
  durs <- numeric(n)
  timings <- vector("list", n)
  cached <- TRUE
  for (k in seq_len(n)) {
    if (!nzchar(pieces[k])) next
    got <- voice_piece(pieces[k], sprintf("%s-p%d.mp3", work_base, k))
    cached <- cached && isTRUE(got$cached)
    files[k] <- sprintf("%s-p%d.wav", work_base, k)
    lc_run(lc_tool("ffmpeg", step), c("-y", "-hide_banner", "-loglevel", "error", "-i", got$file,
                                       "-ar", "48000", "-ac", "2", files[k]), step = step, file = files[k])
    durs[k] <- lc_duration(files[k], step)
    timings[k] <- list(got$timing)
  }
  # Lay out: each piece follows the last; an animation starts as the piece
  # before its tag ends; a waiting tag holds the next piece until the
  # animation is over. Animations never overlap.
  piece_start <- numeric(n)
  at <- numeric(n - 1)
  t <- 0
  anim_end <- 0
  for (k in seq_len(n)) {
    piece_start[k] <- t
    t <- t + durs[k]
    if (k < n) {
      run <- length(captured[[k]]$files) * captured[[k]]$seconds / v$animation_speed
      at[k] <- max(t, anim_end)
      anim_end <- at[k] + run
      if (!isTRUE(events$over[k])) t <- anim_end + 0.15
    }
  }
  # Join the pieces with silence between them.
  out <- paste0(work_base, ".wav")
  inputs <- character(0)
  filters <- character(0)
  order <- character(0)
  cursor <- 0
  for (k in seq_len(n)) {
    gap <- piece_start[k] - cursor
    if (gap > 0.0005) {
      filters <- c(filters, sprintf("aevalsrc=0|0:s=48000:d=%.4f[g%d]", gap, k))
      order <- c(order, sprintf("[g%d]", k))
    }
    if (nzchar(files[k])) {
      filters <- c(filters, sprintf("[%d:a]aformat=sample_fmts=fltp:channel_layouts=stereo[p%d]",
                                    length(inputs) / 2, k))
      inputs <- c(inputs, "-i", files[k])
      order <- c(order, sprintf("[p%d]", k))
    }
    cursor <- piece_start[k] + durs[k]
  }
  if (length(inputs) == 0) lc_abort(step, "A tagged segment has no narration.", file = out)
  graph <- paste(c(filters, paste0(paste(order, collapse = ""), sprintf("concat=n=%d:v=0:a=1[a]", length(order)))),
                 collapse = ";")
  lc_run(lc_tool("ffmpeg", step), c("-y", "-hide_banner", "-loglevel", "error", inputs, "-filter_complex", graph,
                                     "-map", "[a]", "-ar", "48000", "-ac", "2", out), step = step, file = out)
  want <- piece_start[n] + durs[n]
  got <- lc_duration(out, step)
  if (abs(got - want) > 0.1) {
    lc_abort(step, sprintf("The joined narration is %.2f s long, expected %.2f s.", got, want), file = out)
  }
  list(file = out, timing = lc_join_timing(pieces, timings, piece_start, durs), at = at, cached = cached)
}

# One timing table for the joined narration: each piece's timing moved to
# where the piece starts. A piece without timing gets one row spanning it.
lc_join_timing <- function(pieces, timings, starts, durs) {
  chars <- any(vapply(timings, function(tm) !is.null(tm) && "char" %in% names(tm), TRUE))
  rows <- list()
  for (k in seq_along(pieces)) {
    if (!nzchar(pieces[k])) next
    tm <- timings[[k]]
    if (is.null(tm) || nrow(tm) == 0 || chars != ("char" %in% names(tm))) {
      tm <- if (chars) {
        ch <- strsplit(gsub("\\s", "", pieces[k]), "")[[1]]
        edges <- seq(0, durs[k], length.out = length(ch) + 1)
        data.frame(char = ch, start = edges[-length(edges)], end = edges[-1], stringsAsFactors = FALSE)
      } else {
        data.frame(text = pieces[k], start = 0, end = durs[k], stringsAsFactors = FALSE)
      }
    }
    tm$start <- tm$start + starts[k]
    tm$end <- tm$end + starts[k]
    rows[[length(rows) + 1]] <- tm[, if (chars) c("char", "start", "end") else c("text", "start", "end")]
  }
  if (length(rows) == 0) return(NULL)
  do.call(rbind, rows)
}
