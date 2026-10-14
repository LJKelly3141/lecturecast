#' Build a narrated lecture video from a rendered deck
#'
#' Each slide's speaker notes are voiced with the provider set in
#' `lecturecast.yml`, each slide is captured in headless Chrome, and FFmpeg
#' joins them. Captions come from the script text. Every step checks its
#' output, and any failure stops the build with the step, the file and a fix.
#' Finished files are only written once every check has passed.
#'
#' @param deck Path to the deck's `.qmd`, or to its rendered reveal.js `.html`.
#'   A `.qmd` is mapped to its render using the project's `_quarto.yml`;
#'   lecturecast never renders, so a missing or out-of-date render stops.
#' @param config Path to a settings file. By default `lecturecast.yml` is
#'   looked for next to the deck and in parent folders up to the course root.
#' @param out_dir Folder for the finished files. Defaults to `video: out_dir:`
#'   in `lecturecast.yml` (relative to that file), else the deck's folder.
#' @param work_dir Folder for intermediate files (captures, audio, clips). By
#'   default a temporary folder that is removed after a successful build.
#' @param cache_dir Folder holding voiced segments for reuse. Defaults to the
#'   `lecturecast.cache_dir` option, else the user cache folder from
#'   [tools::R_user_dir()].
#' @param slides Slide numbers to build, as `lecture_script()` numbers them,
#'   for a test or a partial video. By default every slide. The whole deck's
#'   notes are still checked.
#' @param quiet If `TRUE`, print only errors.
#' @return Invisibly, a list with the paths of the video, captions and
#'   transcript, and the video's duration in seconds.
#' @export
build_video <- function(deck, config = NULL, out_dir = NULL, work_dir = NULL,
                        cache_dir = NULL, slides = NULL, quiet = FALSE) {
  input <- deck
  deck <- lc_check_deck(deck)
  cfg <- lecturecast_config(input, config)
  name <- tools::file_path_sans_ext(basename(deck))
  wh <- lc_resolutions[[cfg$video$resolution]]
  lc_say(quiet, "Settings: ", cfg$path, " (voice: ", cfg$voice$provider, ")")

  keep_work <- !is.null(work_dir)
  work <- lc_dir_create(work_dir %||% tempfile(paste0("lecturecast-", name, "-")))
  if (!keep_work) on.exit(if (isTRUE(ok)) unlink(work, recursive = TRUE), add = TRUE)
  ok <- FALSE
  out_dir <- lc_dir_create(lc_out_dir(out_dir, cfg, "video", input))
  for (d in c("png", "audio", "clips")) lc_dir_create(file.path(work, d))
  cache <- lc_cache_dir(cache_dir)

  # Script and capture, in one Chrome session.
  b <- lc_open_deck(deck, wh[1], wh[2])
  chrome_open <- TRUE
  on.exit(if (chrome_open) try(b$close(), silent = TRUE), add = TRUE)
  chosen <- slides
  slides <- lc_read_slides(b, deck)
  title <- lc_deck_title(b, deck)
  segs <- lc_segments(slides, cfg$video$silent, split_fragments = isTRUE(cfg$video$fragments %||% TRUE), deck = deck)
  segs <- lc_select_slides(segs, slides, chosen, deck)
  # [play: label] tags come out of the spoken text; the pieces between them
  # are voiced separately so each animation starts exactly at its tag.
  parsed <- lapply(segs$text, lc_parse_tags)
  segs$text <- vapply(parsed, function(p) p$text, "")
  segs$pieces <- lapply(parsed, function(p) p$pieces)
  segs$tags <- lapply(parsed, function(p) p$tags)
  n_voiced <- sum(is.na(segs$silent))
  lc_say(quiet, sprintf("Script: %d slides, %d segments (%d voiced, %d silent).",
                        nrow(slides), nrow(segs), n_voiced, nrow(segs) - n_voiced))

  voice <- lc_prepare_voice(cfg, segs, name, cache)

  lc_prepare_capture(b, deck)
  segs$png <- file.path(work, "png", paste0(segs$id, ".png"))
  # Each segment's still, then any animations its notes cue, in narration
  # order, so a later segment on the same slide starts from where the
  # chart was left.
  events <- vector("list", nrow(segs))
  captured <- vector("list", nrow(segs))
  played <- list()
  for (i in seq_len(nrow(segs))) {
    lc_goto(b, segs$h[i], segs$v[i], segs$fragment[i], deck)
    lc_screenshot(b, segs$png[i], wh[1], wh[2], deck)
    if (!isTRUE(cfg$video$animations) || !is.na(segs$silent[i])) next
    key <- as.character(segs$slide[i])
    buttons <- slides$buttons[[segs$slide[i]]]
    ev <- if (nrow(segs$tags[[i]])) {
      lc_tag_events(segs$tags[[i]], buttons, segs$slide[i], lc_title(segs[i, ]), deck)
    } else {
      lc_segment_events(segs$text[i], buttons, played[[key]] %||% character(0))
    }
    if (nrow(ev) == 0) next
    played[[key]] <- c(played[[key]], lc_label_key(ev$label))
    events[[i]] <- ev
    captured[[i]] <- lapply(seq_len(nrow(ev)), function(k) {
      lc_capture_event(b, ev[k, ], file.path(work, "png", sprintf("%s-anim%d", segs$id[i], k)), wh, deck)
    })
  }
  n_anim <- sum(vapply(events, function(e) if (is.null(e)) 0L else nrow(e), 0L))
  if (n_anim) lc_done(quiet, sprintf("Captured %d animations cued in the notes.", n_anim))
  cards <- lc_capture_cards(b, cfg, title, work, wh, deck)
  try(b$close(), silent = TRUE)
  chrome_open <- FALSE
  lc_done(quiet, sprintf("Captured %d slide states at %dx%d.", nrow(segs), wh[1], wh[2]))

  # Voice. Segments already voiced with the same text and settings come
  # from the cache and cost nothing.
  timings <- vector("list", nrow(segs))
  at <- vector("list", nrow(segs))
  segs$audio <- NA_character_
  reused <- 0L
  for (i in which(is.na(segs$silent))) {
    # Recorded narration is one file per segment, so its tags are placed by
    # the timing estimate, as quotes are.
    tagged <- !is.null(events[[i]]) && "over" %in% names(events[[i]]) && cfg$voice$provider != "recorded"
    v <- if (tagged) {
      seg_id <- segs$id[i]
      tv <- lc_voice_tagged(segs$pieces[[i]], events[[i]], captured[[i]],
                            function(txt, out) voice(list(text = txt, id = seg_id), out),
                            cfg, file.path(work, "audio", seg_id))
      at[i] <- list(tv$at)
      tv
    } else {
      voice(segs[i, ], file.path(work, "audio", paste0(segs$id[i], ".mp3")))
    }
    segs$audio[i] <- v$file
    timings[i] <- list(v$timing)
    reused <- reused + isTRUE(v$cached)
    if (!isTRUE(v$cached)) {
      lc_say(quiet, sprintf("Voiced %s (%d of %d).", segs$id[i], sum(!is.na(segs$audio)), n_voiced))
    }
  }
  lc_done(quiet, sprintf("Voice: %d segments voiced, %d reused from the cache.", n_voiced - reused, reused))

  # Clips, with a short fade between consecutive pictures and optional
  # title and end cards.
  segs$clip <- file.path(work, "clips", paste0(segs$id, ".mp4"))
  segs$clip_seconds <- NA_real_
  segs$audio_seconds <- NA_real_
  for (i in seq_len(nrow(segs))) {
    if (is.na(segs$silent[i])) segs$audio_seconds[i] <- lc_duration(segs$audio[i], "assemble")
    segs$clip_seconds[i] <- if (!is.null(events[[i]])) {
      sched <- lc_animation_schedule(segs$png[i], events[[i]], captured[[i]], segs$text[i], timings[[i]],
                                     segs$audio_seconds[i], cfg, at = at[[i]])
      lc_animated_clip(sched, segs$audio[i], segs$clip[i], cfg)
    } else if (is.na(segs$silent[i])) {
      lc_still_clip(segs$png[i], segs$clip[i], cfg, audio = segs$audio[i])
    } else {
      lc_still_clip(segs$png[i], segs$clip[i], cfg, seconds = segs$silent[i])
    }
  }
  # A fade out of an animated clip starts from its last frame.
  segs$png_out <- vapply(seq_len(nrow(segs)), function(i) {
    cap <- captured[[i]]
    if (is.null(cap)) segs$png[i] else { last <- cap[[length(cap)]]$files; last[length(last)] }
  }, "")
  timeline <- lc_timeline(segs, cards, cfg, work)

  # Join, caption, transcript. Written under temporary names, renamed once
  # every check has passed.
  final <- file.path(out_dir, paste0(name, c(".mp4", ".vtt", "-transcript.md")))
  part <- file.path(out_dir, paste0(name, c(".partial.mp4", ".partial.vtt", "-transcript.partial.md")))
  on.exit(unlink(part), add = TRUE)
  total <- lc_concat(timeline$clip, part[1])

  segs$start <- timeline$start[match(segs$id, timeline$id)]
  cues <- lc_video_cues(segs, timings, cfg)
  lc_write_vtt(cues, part[2])
  if (max(cues$end) > total + 0.5) {
    lc_abort("captions", "Captions run past the end of the video.", file = part[2])
  }
  lc_write_transcript(segs, title, part[3])

  lc_publish(part, final)
  ok <- TRUE
  lc_done(quiet, sprintf("Completed: %s (%s), captions and transcript checked.", final[1], lc_hms(total)))
  invisible(list(video = final[1], captions = final[2], transcript = final[3], seconds = total,
                 segments = segs))
}

# Keep only the segments of the chosen slides, numbered as lecture_script()
# numbers them. NULL keeps every slide.
lc_select_slides <- function(segs, slides, chosen, deck) {
  if (is.null(chosen)) return(segs)
  n <- nrow(slides)
  if (!is.numeric(chosen) || length(chosen) == 0 || anyNA(chosen) || any(chosen != round(chosen))) {
    lc_abort("script", "slides must be whole slide numbers, such as 1:9.", file = deck)
  }
  bad <- setdiff(chosen, seq_len(n))
  if (length(bad)) {
    lc_abort("script", sprintf("The deck has %d slides, so these do not exist: %s.", n, paste(bad, collapse = ", ")),
             file = deck, fix = "Use the slide numbers shown by lecture_script().")
  }
  segs <- segs[segs$slide %in% chosen, ]
  rownames(segs) <- NULL
  if (all(!is.na(segs$silent))) {
    lc_abort("script", "Every chosen slide is silent, so there is nothing to voice.", file = deck,
             fix = "Include at least one slide with speaker notes.")
  }
  segs
}

# The order of clips in the video, with fades between pictures. Returns a
# data frame of id, clip and start (seconds from the start of the video).
lc_timeline <- function(segs, cards, cfg, work) {
  items <- data.frame(id = segs$id, png = segs$png, png_out = segs$png_out %||% segs$png, clip = segs$clip,
                      seconds = segs$clip_seconds, stringsAsFactors = FALSE)
  if (!is.null(cards$title)) {
    d <- lc_still_clip(cards$title, file.path(work, "clips", "title-card.mp4"), cfg, seconds = cfg$video$card_seconds)
    items <- rbind(data.frame(id = "title-card", png = cards$title, png_out = cards$title, clip = file.path(work, "clips", "title-card.mp4"),
                              seconds = d), items)
  }
  if (!is.null(cards$end)) {
    d <- lc_still_clip(cards$end, file.path(work, "clips", "end-card.mp4"), cfg, seconds = cfg$video$card_seconds)
    items <- rbind(items, data.frame(id = "end-card", png = cards$end, png_out = cards$end, clip = file.path(work, "clips", "end-card.mp4"),
                                     seconds = d))
  }
  fade <- cfg$video$crossfade
  if (fade > 0 && nrow(items) > 1) {
    rows <- list(items[1, ])
    for (i in 2:nrow(items)) {
      tr <- file.path(work, "clips", sprintf("fade-%03d.mp4", i - 1))
      d <- lc_fade_clip(items$png_out[i - 1], items$png[i], tr, cfg)
      rows[[length(rows) + 1]] <- data.frame(id = paste0("fade-", i - 1), png = NA_character_, png_out = NA_character_,
                                             clip = tr, seconds = d)
      rows[[length(rows) + 1]] <- items[i, ]
    }
    items <- do.call(rbind, rows)
  }
  items$start <- c(0, cumsum(items$seconds))[seq_len(nrow(items))]
  items
}

lc_cache_dir <- function(cache_dir = NULL) {
  lc_dir_create(cache_dir %||% getOption("lecturecast.cache_dir", tools::R_user_dir("lecturecast", "cache")))
}

# The cache key for one voiced segment: everything that changes the audio.
lc_cache_key <- function(cfg, voice_id, text, model = NULL) {
  parts <- list(
    provider = cfg$voice$provider, voice = voice_id,
    model = if (cfg$voice$provider == "elevenlabs") model %||% cfg$voice$model else NULL,
    settings = if (cfg$voice$provider == "elevenlabs") cfg$voice$settings else NULL,
    rate = if (cfg$voice$provider == "edge") cfg$voice$edge_rate else NULL,
    engine = if (cfg$voice$provider == "edge") lc_edge_engine() else NULL,
    text = enc2utf8(text)
  )
  cli::hash_sha256(as.character(jsonlite::toJSON(parts, auto_unbox = TRUE, null = "null")))
}

# Voice through the cache: reuse the audio when the key matches, otherwise
# voice, check, then store. Entries are written under temporary names and
# renamed, audio first and the JSON last, so a JSON file marks a finished
# entry. A damaged entry stops the build and says which files to delete.
lc_cached_voice <- function(key, cache, voice_fun, work_file) {
  step <- "voice (cache)"
  audio <- file.path(cache, paste0(key, ".mp3"))
  meta <- file.path(cache, paste0(key, ".json"))
  if (file.exists(meta)) {
    fix <- paste0("Delete ", file.path(cache, paste0(key, ".*")), " and build again; that segment will be voiced afresh.")
    m <- tryCatch(jsonlite::fromJSON(meta),
                  error = function(e) lc_abort(step, "The cache entry is damaged.", file = meta, fix = fix))
    if (!file.exists(audio) || file.size(audio) == 0) lc_abort(step, "The cached audio is missing.", file = audio, fix = fix)
    d <- tryCatch(lc_duration(audio, step), lecturecast_error = function(e) {
      lc_abort(step, "The cached audio cannot be read.", file = audio, fix = fix)
    })
    if (is.null(m$seconds) || abs(d - m$seconds) > 0.05) {
      lc_abort(step, "The cached audio is not the length recorded for it.", file = audio, fix = fix)
    }
    timing <- m$timing
    if (is.list(timing) && !is.data.frame(timing) && length(timing) == 0) timing <- NULL
    return(list(file = audio, timing = timing, cached = TRUE))
  }
  v <- voice_fun(work_file)
  d <- lc_duration(v$file, step)
  tmp <- file.path(cache, paste0(key, c(".mp3", ".json"), ".tmp"))
  on.exit(unlink(tmp), add = TRUE)
  ok <- file.copy(v$file, tmp[1], overwrite = TRUE)
  writeLines(jsonlite::toJSON(list(seconds = d, timing = v$timing), dataframe = "rows", digits = NA,
                              auto_unbox = TRUE), tmp[2])
  if (!ok || !file.rename(tmp[1], audio) || !file.rename(tmp[2], meta)) {
    unlink(c(audio, meta))
    lc_abort(step, "Could not store the audio in the cache.", file = audio)
  }
  list(file = audio, timing = v$timing, cached = FALSE)
}

# Move finished files into place together. Old versions are set aside first
# and put back if any move fails, so captions never sit beside the wrong video.
lc_publish <- function(part, final) {
  backup <- paste0(final, ".old")
  had <- file.exists(final)
  unlink(backup)
  if (!all(file.rename(final[had], backup[had]))) {
    lc_abort("output", "Could not set aside the previous version.", file = final[had][1])
  }
  moved <- file.rename(part, final)
  if (!all(moved)) {
    unlink(final[moved])
    file.rename(backup[had], final[had])
    lc_abort("output", "Could not move the finished file into place; the previous version is restored.",
             file = final[!moved][1])
  }
  unlink(backup[had])
  invisible(final)
}

# A function voicing one segment row to a file, after checking the voice is
# usable. Recorded mode looks up every file before anything is built.
lc_prepare_voice <- function(cfg, segs, name, cache) {
  voiced <- segs$id[is.na(segs$silent)]
  if (cfg$voice$provider == "recorded") {
    files <- lc_recorded_files(voiced, cfg, name)
    return(function(seg, out) {
      f <- files[[seg$id]]
      lc_duration(f, "voice (recorded)")
      list(file = f, timing = NULL, cached = FALSE)
    })
  }
  voice_id <- lc_voice_id(cfg, "narrator")
  if (cfg$voice$provider == "edge") lc_edge_command()
  function(seg, out) {
    lc_cached_voice(lc_cache_key(cfg, voice_id, seg$text), cache,
                    function(f) lc_voice(seg$text, voice_id, cfg, f), out)
  }
}

lc_video_cues <- function(segs, timings, cfg) {
  starts <- segs$start %||% c(0, cumsum(segs$clip_seconds))[seq_len(nrow(segs))]
  out <- list()
  for (i in which(is.na(segs$silent))) {
    # The narration's own length: an animation can make the clip longer.
    a_dur <- segs$audio_seconds[i] %||% (segs$clip_seconds[i] - cfg$video$lead_in - cfg$video$tail)
    cues <- lc_segment_cues(segs$text[i], timings[[i]], a_dur)
    if (is.null(cues)) next
    off <- starts[i] + cfg$video$lead_in
    cues$start <- cues$start + off
    cues$end <- cues$end + off
    out[[length(out) + 1]] <- cues
  }
  do.call(rbind, out)
}

lc_write_transcript <- function(segs, title, file) {
  lines <- c(paste0("# ", title), "")
  for (i in seq_len(nrow(segs))) {
    if (!is.na(segs$silent[i])) next
    head <- paste0("## Slide ", segs$slide[i], if (nzchar(segs$title[i])) paste0(": ", segs$title[i]) else "")
    if (i == 1 || segs$slide[i] != segs$slide[i - 1]) lines <- c(lines, head, "")
    lines <- c(lines, segs$text[i], "")
  }
  writeLines(enc2utf8(lines), file, useBytes = TRUE)
  invisible(file)
}

lc_hms <- function(s) {
  s <- round(s)
  sprintf("%d:%02d", s %/% 60, s %% 60)
}
