# Two-host podcast episodes from a plain-text dialogue script.
#
# Script format:
#   # Episode title            (optional, first heading)
#   ## Chapter name            (starts a chapter)
#   HOST_A: A line, with optional ElevenLabs cues like [curious].
#   HOST_B: A reply. Lines without a prefix continue the previous turn.

#' Read a podcast dialogue script
#'
#' @param script Path to the script file.
#' @return A data frame with one row per turn: `id`, `host` (`"host_a"` or
#'   `"host_b"`), `text` (with cues), `chapter`; the episode title is the
#'   `"title"` attribute.
#' @export
read_dialogue <- function(script) {
  step <- "script"
  if (!file.exists(script)) lc_abort(step, "Script file not found.", file = script)
  lines <- readLines(script, encoding = "UTF-8", warn = FALSE)
  title <- NULL
  chapter <- NA_character_
  chapter_n <- 0L
  chapter_used <- TRUE
  chapter_line <- 0L
  turns <- list()
  for (n in seq_along(lines)) {
    ln <- trimws(lines[n])
    if (!nzchar(ln)) next
    if (grepl("^## ", ln)) {
      if (!chapter_used) {
        lc_abort(step, sprintf("The heading on line %d has no turns under it.", chapter_line), file = script)
      }
      chapter <- trimws(sub("^## ", "", ln))
      chapter_n <- chapter_n + 1L
      chapter_used <- FALSE
      chapter_line <- n
      next
    }
    if (grepl("^# ", ln) && is.null(title) && length(turns) == 0 && chapter_n == 0) {
      title <- trimws(sub("^# ", "", ln))
      next
    }
    m <- regmatches(ln, regexec("^(HOST_A|HOST_B)\\s*:\\s*(.*)$", ln))[[1]]
    if (length(m)) {
      turns[[length(turns) + 1]] <- list(host = tolower(m[2]), text = m[3], chapter = chapter,
                                         chapter_n = chapter_n, line = n)
      chapter_used <- TRUE
      next
    }
    # Anything that looks like a label, heading or comment but is not one of
    # the forms above would otherwise be read aloud as part of a turn.
    if (grepl("^#", ln) || grepl("^<!--", ln) || grepl("^[A-Za-z_ ]{1,20}:", ln) && grepl("(?i)^\\s*host", ln, perl = TRUE)) {
      lc_abort(step, sprintf("Line %d is not a turn, a heading (# title, ## chapter) or a continuation: %s", n, ln),
               file = script, fix = "Labels are exactly HOST_A: or HOST_B:. Use # only for the title and ## for chapters.")
    }
    if (length(turns)) {
      k <- length(turns)
      turns[[k]]$text <- paste(turns[[k]]$text, ln)
    } else {
      lc_abort(step, sprintf("Line %d is not a HOST_A: or HOST_B: line and no turn has started.", n),
               file = script, fix = "Start each turn with HOST_A: or HOST_B:.")
    }
  }
  if (!chapter_used) lc_abort(step, sprintf("The heading on line %d has no turns under it.", chapter_line), file = script)
  if (length(turns) == 0) lc_abort(step, "The script has no HOST_A: or HOST_B: lines.", file = script)
  empty <- vapply(turns, function(t) !nzchar(trimws(lc_strip_cues(t$text))), logical(1))
  if (any(empty)) {
    lc_abort(step, paste0("Turns with no words, on lines: ", paste(vapply(turns[empty], `[[`, 0, "line"), collapse = ", "), "."),
             file = script)
  }
  out <- data.frame(
    id = sprintf("t%03d", seq_along(turns)),
    host = vapply(turns, `[[`, "", "host"),
    text = vapply(turns, function(t) trimws(t$text), ""),
    chapter = vapply(turns, `[[`, "", "chapter"),
    chapter_n = vapply(turns, `[[`, 0L, "chapter_n"),
    stringsAsFactors = FALSE
  )
  attr(out, "title") <- title %||% tools::file_path_sans_ext(basename(script))
  out
}

# Remove ElevenLabs cues such as [curious] or [short pause] for voices that
# would read them. Only bracketed words count as cues, so "[2, 5]" stays.
lc_strip_cues <- function(x) trimws(gsub("\\s{2,}", " ", gsub("\\[[A-Za-z][A-Za-z '-]*\\]", "", x)))

#' Build a podcast episode from a dialogue script
#'
#' With the ElevenLabs provider, the script is voiced through ElevenLabs'
#' dialogue endpoint in chunks of at most 2,000 characters, keeping the cues.
#' With Edge, or with `podcast: mode: lines` in the settings, each turn is
#' voiced separately with its host's voice and the turns are joined; cues are
#' removed because those voices would read them aloud. Recorded mode reads
#' `<recorded_dir>/<episode>/<turn id>-<hash>.wav` (or .mp3, .m4a); the hash
#' changes when a turn's words change, and a missing file stops the build
#' with every expected name listed.
#'
#' @param script Path to the dialogue script.
#' @param config Path to a settings file. By default `lecturecast.yml` is
#'   looked for next to the script and in parent folders.
#' @param out_dir Folder for the finished files.
#' @param cache_dir Folder holding voiced audio for reuse.
#' @param quiet If `TRUE`, print only errors.
#' @return Invisibly, a list with the paths of the episode, transcript and
#'   chapter list, and the episode's duration in seconds.
#' @export
build_podcast <- function(script, config = NULL, out_dir = dirname(script), cache_dir = NULL,
                          quiet = FALSE) {
  script <- normalizePath(script, mustWork = FALSE)
  turns <- read_dialogue(script)
  cfg <- lecturecast_config(script, config)
  name <- tools::file_path_sans_ext(basename(script))
  title <- attr(turns, "title")
  out_dir <- lc_dir_create(out_dir)
  cache <- lc_cache_dir(cache_dir)
  work <- lc_dir_create(tempfile(paste0("lecturecast-", name, "-")))
  on.exit(unlink(work, recursive = TRUE), add = TRUE)
  lc_say(quiet, sprintf("Script: %d turns, %d characters. Voice: %s.", nrow(turns),
                        sum(nchar(turns$text)), cfg$voice$provider))

  mode <- lc_podcast_mode(cfg)
  pieces <- switch(mode,
    dialogue = lc_podcast_dialogue(turns, cfg, cache, work, quiet),
    lines = lc_podcast_lines(turns, cfg, cache, work, quiet),
    recorded = lc_podcast_recorded(turns, cfg, name)
  )

  final <- file.path(out_dir, paste0(name, c(".mp3", "-transcript.md", "-chapters.txt")))
  part <- file.path(out_dir, paste0(name, c(".partial.mp3", "-transcript.partial.md", "-chapters.partial.txt")))
  on.exit(unlink(part), add = TRUE)
  gap <- cfg$podcast$gap
  wav <- lc_to_wavs(pieces$files, c(rep(gap, length(pieces$files) - 1), 0), work)
  turns$start <- wav$piece_start[pieces$piece] + pieces$offset
  chapters <- lc_chapters(turns, turns$start)
  lc_check_chapters(chapters, wav$total, script)
  joined <- lc_encode_episode(wav, part[1], work, title, chapters)
  lc_write_podcast_transcript(turns, title, cfg, part[2])
  lc_write_chapters(turns, part[3])
  lc_publish(part, final)
  lc_done(quiet, sprintf("Completed: %s (%s), transcript and chapters checked.", final[1], lc_hms(joined)))
  invisible(list(audio = final[1], transcript = final[2], chapters = final[3], seconds = joined,
                 turns = turns))
}

lc_podcast_mode <- function(cfg) {
  p <- cfg$voice$provider
  if (p == "recorded") return("recorded")
  mode <- cfg$podcast$mode %||% (if (p == "elevenlabs") "dialogue" else "lines")
  if (!mode %in% c("dialogue", "lines")) {
    lc_abort("settings", "podcast: mode: must be dialogue or lines.", file = cfg$path)
  }
  if (mode == "dialogue" && p != "elevenlabs") {
    lc_abort("settings", "podcast: mode: dialogue needs the elevenlabs provider.", file = cfg$path,
             fix = "Use mode: lines with this provider, or set provider: elevenlabs.")
  }
  mode
}

# Single-voice path: each turn voiced on its own, joined with a short gap.
lc_podcast_lines <- function(turns, cfg, cache, work, quiet) {
  ids <- c(host_a = lc_voice_id(cfg, "host_a"), host_b = lc_voice_id(cfg, "host_b"))
  if (cfg$voice$provider == "edge") lc_edge_command()
  if (cfg$voice$provider == "elevenlabs") lc_elevenlabs_key("voice (elevenlabs)")
  keep_cues <- cfg$voice$provider == "elevenlabs" && identical(cfg$voice$model, "eleven_v3")
  files <- character(nrow(turns))
  reused <- 0L
  for (i in seq_len(nrow(turns))) {
    text <- if (keep_cues) turns$text[i] else lc_strip_cues(turns$text[i])
    vid <- ids[[turns$host[i]]]
    v <- lc_cached_voice(lc_cache_key(cfg, vid, text), cache,
                         function(f) lc_voice(text, vid, cfg, f),
                         file.path(work, paste0(turns$id[i], ".mp3")))
    files[i] <- v$file
    reused <- reused + isTRUE(v$cached)
  }
  lc_done(quiet, sprintf("Voice: %d turns voiced, %d reused from the cache.", nrow(turns) - reused, reused))
  list(files = files, piece = seq_along(files), offset = numeric(length(files)))
}

# Recording names carry a short hash of the host and words, so an edited or
# moved turn asks for a new recording instead of reusing the wrong one.
lc_recorded_ids <- function(turns) {
  h <- vapply(paste(turns$host, turns$text), cli::hash_sha256, "")
  paste0(turns$id, "-", substr(h, 1, 6))
}

lc_podcast_recorded <- function(turns, cfg, name) {
  files <- unname(lc_recorded_files(lc_recorded_ids(turns), cfg, name))
  list(files = files, piece = seq_along(files), offset = numeric(length(files)))
}

# Group turns into chunks of at most `limit` characters without splitting a
# turn. A single turn over the limit stops the build.
lc_dialogue_chunks <- function(turns, limit = 2000) {
  n <- nchar(turns$text)
  ch <- turns$chapter_n %||% rep(0L, length(n))
  if (any(n > limit)) {
    big <- which(n > limit)[1]
    lc_abort("script", sprintf("Turn %s is %d characters; ElevenLabs dialogue takes at most %d per request.",
                               turns$id[big], n[big], limit),
             fix = "Split that turn into two turns for the same host.")
  }
  chunk <- integer(length(n))
  k <- 1L
  used <- 0
  # A new chunk starts at each chapter, so an edit in one chapter never
  # re-voices another.
  for (i in seq_along(n)) {
    if (used + n[i] > limit || (i > 1 && ch[i] != ch[i - 1])) {
      k <- k + 1L
      used <- 0
    }
    chunk[i] <- k
    used <- used + n[i]
  }
  chunk
}

# ElevenLabs dialogue path: chunks voiced through text-to-dialogue, each
# cached by its inputs and the neighbouring text sent for continuity.
lc_podcast_dialogue <- function(turns, cfg, cache, work, quiet) {
  ids <- c(host_a = lc_voice_id(cfg, "host_a"), host_b = lc_voice_id(cfg, "host_b"))
  lc_elevenlabs_key("voice (elevenlabs dialogue)")
  chunk <- lc_dialogue_chunks(turns)
  files <- character(max(chunk))
  offset <- numeric(nrow(turns))
  reused <- 0L
  for (k in seq_len(max(chunk))) {
    rows <- which(chunk == k)
    inputs <- lapply(rows, function(i) list(text = turns$text[i], voice_id = ids[[turns$host[i]]]))
    cont <- isTRUE(cfg$podcast$continuity)
    prev <- if (cont && k > 1) lc_tail_chars(turns$text[max(which(chunk == k - 1))], 100) else NULL
    nxt <- if (cont && k < max(chunk)) lc_head_chars(turns$text[min(which(chunk == k + 1))], 100) else NULL
    key <- cli::hash_sha256(as.character(jsonlite::toJSON(
      list(provider = "elevenlabs-dialogue", model = cfg$voice$dialogue_model, inputs = inputs,
           settings = cfg$podcast$dialogue_settings, previous = prev, future = nxt),
      auto_unbox = TRUE, null = "null")))
    v <- lc_cached_voice(key, cache, function(f) {
      lc_voice_dialogue(inputs, cfg, f, previous_text = prev, future_text = nxt)
    }, file.path(work, sprintf("chunk-%02d.mp3", k)))
    files[k] <- v$file
    reused <- reused + isTRUE(v$cached)
    offset[rows] <- lc_dialogue_turn_starts(v$timing, length(rows), v$file)
  }
  lc_done(quiet, sprintf("Voice: %d dialogue chunks voiced, %d reused from the cache.", max(chunk) - reused, reused))
  list(files = files, piece = chunk, offset = offset)
}

lc_tail_chars <- function(x, n) if (nchar(x) <= n) x else substr(x, nchar(x) - n + 1, nchar(x))
lc_head_chars <- function(x, n) substr(x, 1, n)

# Start of each input within a chunk, from ElevenLabs' voice segments
# (dialogue_input_index is 0-based). Missing or out-of-order timing stops
# the build rather than misplacing turns and chapters.
lc_dialogue_turn_starts <- function(timing, n, file = NULL) {
  step <- "voice (elevenlabs dialogue)"
  if (is.null(timing) || !is.data.frame(timing) || !all(c("dialogue_input_index", "start_time_seconds") %in% names(timing))) {
    lc_abort(step, "ElevenLabs returned no voice segment timing, so turns cannot be placed.", file = file,
             fix = "Delete this chunk from the cache and build again.")
  }
  idx <- timing$dialogue_input_index
  if (any(idx < 0 | idx >= n)) {
    lc_abort(step, "ElevenLabs returned timing for a turn that was not sent.", file = file)
  }
  out <- vapply(seq_len(n) - 1L, function(j) {
    hit <- timing$start_time_seconds[idx == j]
    if (length(hit)) min(hit) else NA_real_
  }, numeric(1))
  if (anyNA(out) || is.unsorted(out)) {
    lc_abort(step, "ElevenLabs timing is missing a turn or out of order.", file = file,
             fix = "Delete this chunk from the cache and build again.")
  }
  out
}

lc_voice_dialogue <- function(inputs, cfg, out, previous_text = NULL, future_text = NULL) {
  step <- "voice (elevenlabs dialogue)"
  key <- lc_elevenlabs_key(step)
  body <- list(inputs = inputs, model_id = cfg$voice$dialogue_model)
  if (!is.null(cfg$podcast$dialogue_settings)) body$settings <- cfg$podcast$dialogue_settings
  if (!is.null(previous_text)) body$previous_text <- previous_text
  if (!is.null(future_text)) body$future_text <- future_text
  req <- httr2::request(lc_elevenlabs_base())
  req <- httr2::req_url_path_append(req, "v1", "text-to-dialogue", "with-timestamps")
  req <- httr2::req_url_query(req, output_format = "mp3_44100_128")
  req <- httr2::req_headers(req, `xi-api-key` = key, .redact = "xi-api-key")
  req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
  resp <- lc_elevenlabs_perform(req, step, out)
  res <- httr2::resp_body_json(resp, simplifyVector = TRUE)
  if (is.null(res$audio_base64)) lc_abort(step, "ElevenLabs returned no audio.", file = out)
  writeBin(jsonlite::base64_dec(res$audio_base64), out)
  lc_duration(out, step)
  segs <- res$voice_segments
  timing <- if (is.data.frame(segs) && nrow(segs)) {
    segs[, intersect(c("voice_id", "start_time_seconds", "end_time_seconds", "dialogue_input_index"), names(segs))]
  } else NULL
  list(file = out, timing = timing)
}

# Convert each piece to WAV with a silent gap after it. Returns the WAV
# files, where each piece starts, and the total length.
lc_to_wavs <- function(files, gaps, work) {
  step <- "assemble"
  ff <- lc_tool("ffmpeg", step)
  wavs <- character(0)
  piece_start <- numeric(length(files))
  t <- 0
  for (i in seq_along(files)) {
    w <- file.path(work, sprintf("piece-%03d.wav", i))
    lc_run(ff, c("-y", "-hide_banner", "-loglevel", "error", "-i", files[i],
                 "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", w), step = step, file = w, timeout = 120)
    piece_start[i] <- t
    t <- t + lc_duration(w, step)
    wavs <- c(wavs, w)
    if (gaps[i] > 0) {
      g <- file.path(work, sprintf("gap-%03d.wav", i))
      lc_run(ff, c("-y", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                   "-t", sprintf("%.3f", gaps[i]), "-c:a", "pcm_s16le", g), step = step, file = g, timeout = 60)
      t <- t + lc_duration(g, step)
      wavs <- c(wavs, g)
    }
  }
  list(wavs = wavs, piece_start = piece_start, total = t)
}

# Encode the joined WAVs as one MP3 with title and chapters embedded.
lc_encode_episode <- function(wav, out, work, title, chapters) {
  step <- "assemble"
  list_file <- file.path(work, "pieces.txt")
  writeLines(paste0("file '", gsub("'", "'\\\\''", normalizePath(wav$wavs)), "'"), list_file)
  meta <- file.path(work, "meta.txt")
  writeLines(enc2utf8(lc_ffmetadata(title, chapters, wav$total)), meta, useBytes = TRUE)
  lc_run(lc_tool("ffmpeg", step),
         c("-y", "-hide_banner", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", list_file,
           "-i", meta, "-map", "0:a", "-map_metadata", "1", "-map_chapters", "1",
           "-c:a", "libmp3lame", "-b:a", "160k", "-id3v2_version", "3", out),
         step = step, file = out, timeout = 600)
  got <- lc_duration(out, step)
  if (abs(got - wav$total) > 0.5) {
    lc_abort(step, sprintf("Episode is %.2f s long, but its parts add up to %.2f s.", got, wav$total), file = out)
  }
  got
}

# Chapters: a data frame of title and start seconds, one per chapter heading.
lc_chapters <- function(turns, turn_start) {
  cn <- turns$chapter_n %||% match(turns$chapter, unique(turns$chapter))
  first <- which(!is.na(turns$chapter) & !duplicated(cn))
  data.frame(title = turns$chapter[first], start = turn_start[first], stringsAsFactors = FALSE)
}

lc_check_chapters <- function(chapters, total, file) {
  if (nrow(chapters) && (is.unsorted(chapters$start, strictly = TRUE) || max(chapters$start) >= total)) {
    lc_abort("chapters", "Chapter times are out of order or past the end of the episode.", file = file)
  }
  invisible(TRUE)
}

lc_ffmetadata <- function(title, chapters, total) {
  esc <- function(x) gsub("([=;#\\\\\n])", "\\\\\\1", x)
  out <- c(";FFMETADATA1", paste0("title=", esc(title)))
  if (nrow(chapters)) {
    ends <- c(chapters$start[-1], total)
    for (i in seq_len(nrow(chapters))) {
      out <- c(out, "[CHAPTER]", "TIMEBASE=1/1000",
               paste0("START=", round(chapters$start[i] * 1000)),
               paste0("END=", round(ends[i] * 1000)),
               paste0("title=", esc(chapters$title[i])))
    }
  }
  out
}

lc_write_podcast_transcript <- function(turns, title, cfg, file) {
  names <- c(host_a = cfg$podcast$host_a_name %||% "Host A", host_b = cfg$podcast$host_b_name %||% "Host B")
  lines <- c(paste0("# ", title), "")
  prev <- NA_integer_
  for (i in seq_len(nrow(turns))) {
    ch <- turns$chapter[i]
    if (!is.na(ch) && !identical(turns$chapter_n[i], prev)) lines <- c(lines, paste0("## ", ch, " (", lc_hms(turns$start[i]), ")"), "")
    prev <- turns$chapter_n[i]
    lines <- c(lines, paste0("**", names[[turns$host[i]]], ":** ", lc_strip_cues(turns$text[i])), "")
  }
  writeLines(enc2utf8(lines), file, useBytes = TRUE)
  invisible(file)
}

lc_write_chapters <- function(turns, file) {
  ch <- lc_chapters(turns, turns$start)
  lines <- if (nrow(ch)) paste(vapply(ch$start, lc_hms, ""), ch$title) else character(0)
  writeLines(enc2utf8(lines), file, useBytes = TRUE)
  invisible(file)
}
