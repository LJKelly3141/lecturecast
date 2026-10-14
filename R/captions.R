# Captions from the script text. The words always come from the script;
# provider timing data, when present, only places them in time.

lc_sentences <- function(text) {
  paras <- strsplit(text, "\n\n", fixed = TRUE)[[1]]
  paras <- trimws(paras[nzchar(trimws(paras))])
  out <- unlist(lapply(paras, function(p) {
    strsplit(enc2utf8(p), "(*UTF8)(?:(?<=[.!?\\x{2026}])|(?<=[.!?\\x{2026}][\"\\x{201d}\\x{2019})]))\\s+(?=[\"\\x{201c}\\x{2018}(A-Z0-9])",
             perl = TRUE)[[1]]
  }))
  trimws(out[nzchar(trimws(out))])
}

# Break sentences longer than max_chars into roughly even pieces at word
# boundaries, preferring a break after a comma or semicolon.
lc_cue_chunks <- function(sentences, max_chars = 84) {
  unlist(lapply(sentences, function(s) {
    if (nchar(s) <= max_chars) return(s)
    words <- strsplit(s, " ", fixed = TRUE)[[1]]
    n_pieces <- ceiling(nchar(s) / max_chars)
    target <- nchar(s) / n_pieces
    pieces <- character(0)
    cur <- character(0)
    for (w in words) {
      cand <- paste(c(cur, w), collapse = " ")
      if (length(cur) && nchar(cand) > max_chars) {
        pieces <- c(pieces, paste(cur, collapse = " "))
        cur <- w
      } else {
        cur <- c(cur, w)
        if (nchar(cand) >= target * 0.8 && grepl("[,;:]$", w) && length(pieces) < n_pieces - 1) {
          pieces <- c(pieces, cand)
          cur <- character(0)
        }
      }
    }
    if (length(cur)) pieces <- c(pieces, paste(cur, collapse = " "))
    pieces
  }))
}

lc_nows <- function(x) nchar(gsub("\\s", "", x))

# Two functions from position in the script (count of non-space characters)
# to seconds within the segment's audio: `start` for where a cue begins and
# `end` for where one finishes, so a pause between provider cues is not
# counted inside either neighbour.
lc_time_map <- function(script_text, timing, duration) {
  total <- lc_nows(script_text)
  linear <- function(pos) pmin(duration, pmax(0, pos / max(total, 1) * duration))
  if (total == 0 || is.null(timing) || nrow(timing) == 0) {
    return(list(start = linear, end = linear))
  }
  if ("char" %in% names(timing)) {
    timing <- timing[!grepl("^\\s*$", timing$char), , drop = FALSE]
    lens <- rep(1, nrow(timing))
  } else {
    lens <- lc_nows(timing$text)
  }
  if (length(lens) == 0 || sum(lens) == 0) return(list(start = linear, end = linear))
  cum <- cumsum(lens)
  x <- as.vector(rbind(cum - lens, cum)) / sum(lens) * total
  y <- cummax(as.vector(rbind(timing$start, timing$end)))
  mk <- function(tie) function(pos) pmin(duration, stats::approx(x, y, xout = pos, rule = 2, ties = tie)$y)
  list(start = mk(max), end = mk(min))
}

# Cues for one segment, in segment-local seconds.
lc_segment_cues <- function(text, timing, duration, max_chars = 84) {
  if (!nzchar(trimws(text))) return(NULL)
  chunks <- lc_cue_chunks(lc_sentences(text), max_chars)
  f <- lc_time_map(text, timing, duration)
  lens <- lc_nows(chunks)
  ends <- cumsum(lens)
  starts <- ends - lens
  data.frame(text = chunks, start = f$start(starts), end = f$end(ends), stringsAsFactors = FALSE)
}

lc_wrap <- function(text, width = 42) {
  if (nchar(text) <= width) return(text)
  words <- strsplit(text, " ", fixed = TRUE)[[1]]
  best <- NULL
  best_score <- Inf
  for (k in seq_len(length(words) - 1)) {
    a <- paste(words[1:k], collapse = " ")
    b <- paste(words[(k + 1):length(words)], collapse = " ")
    score <- abs(nchar(a) - nchar(b))
    if (score < best_score) {
      best <- paste(a, b, sep = "\n")
      best_score <- score
    }
  }
  best
}

lc_vtt_time <- function(s) {
  ms <- round(max(0, s) * 1000)
  sprintf("%02d:%02d:%02d.%03d", as.integer(ms %/% 3600000), as.integer(ms %/% 60000 %% 60),
          as.integer(ms %/% 1000 %% 60), as.integer(ms %% 1000))
}

# cues: data frame of text, start, end in seconds from the start of the file.
lc_write_vtt <- function(cues, file) {
  cues <- cues[order(cues$start), , drop = FALSE]
  # No overlaps, and every cue on screen for at least half a second.
  if (nrow(cues) > 1) {
    for (i in seq_len(nrow(cues) - 1)) cues$end[i] <- min(cues$end[i], cues$start[i + 1])
  }
  cues$end <- pmax(cues$end, cues$start + 0.5)
  lines <- "WEBVTT"
  for (i in seq_len(nrow(cues))) {
    lines <- c(lines, "", as.character(i),
               paste(lc_vtt_time(cues$start[i]), "-->", lc_vtt_time(cues$end[i])),
               lc_wrap(cues$text[i]))
  }
  writeLines(enc2utf8(lines), file, useBytes = TRUE)
  invisible(file)
}
