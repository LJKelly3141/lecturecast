#' Build a narrated lecture video from a rendered deck
#'
#' Each slide's speaker notes are voiced with the provider set in
#' `lecturecast.yml`, each slide is captured in headless Chrome, and FFmpeg
#' joins them. Captions come from the script text. Every step checks its
#' output, and any failure stops the build with the step, the file and a fix.
#' Finished files are only written once every check has passed.
#'
#' @param deck Path to the rendered reveal.js HTML file.
#' @param config Path to a settings file. By default `lecturecast.yml` is
#'   looked for next to the deck and in parent folders up to the course root.
#' @param out_dir Folder for the finished files. Defaults to the deck's folder.
#' @param work_dir Folder for intermediate files (captures, audio, clips). By
#'   default a temporary folder that is removed after a successful build.
#' @param quiet If `TRUE`, print only errors.
#' @return Invisibly, a list with the paths of the video, captions and
#'   transcript, and the video's duration in seconds.
#' @export
build_video <- function(deck, config = NULL, out_dir = dirname(deck), work_dir = NULL,
                        quiet = FALSE) {
  lc_check_deck(deck)
  deck <- normalizePath(deck)
  cfg <- lecturecast_config(deck, config)
  name <- tools::file_path_sans_ext(basename(deck))
  wh <- lc_resolutions[[cfg$video$resolution]]
  lc_say(quiet, "Settings: ", cfg$path, " (voice: ", cfg$voice$provider, ")")

  keep_work <- !is.null(work_dir)
  work <- lc_dir_create(work_dir %||% tempfile(paste0("lecturecast-", name, "-")))
  if (!keep_work) on.exit(if (isTRUE(ok)) unlink(work, recursive = TRUE), add = TRUE)
  ok <- FALSE
  out_dir <- lc_dir_create(out_dir)
  for (d in c("png", "audio", "clips")) lc_dir_create(file.path(work, d))

  # Script and capture, in one Chrome session.
  b <- lc_open_deck(deck, wh[1], wh[2])
  chrome_open <- TRUE
  on.exit(if (chrome_open) try(b$close(), silent = TRUE), add = TRUE)
  slides <- lc_read_slides(b, deck)
  title <- lc_deck_title(b, deck)
  segs <- lc_segments(slides, cfg$video$silent, split_fragments = isTRUE(cfg$video$fragments %||% TRUE), deck = deck)
  n_voiced <- sum(is.na(segs$silent))
  lc_say(quiet, sprintf("Script: %d slides, %d segments (%d voiced, %d silent).",
                        nrow(slides), nrow(segs), n_voiced, nrow(segs) - n_voiced))

  voice <- lc_prepare_voice(cfg, segs, name)

  lc_prepare_capture(b, deck)
  segs$png <- file.path(work, "png", paste0(segs$id, ".png"))
  for (i in seq_len(nrow(segs))) {
    lc_goto(b, segs$h[i], segs$v[i], segs$fragment[i], deck)
    lc_screenshot(b, segs$png[i], wh[1], wh[2], deck)
  }
  try(b$close(), silent = TRUE)
  chrome_open <- FALSE
  lc_done(quiet, sprintf("Captured %d slide states at %dx%d.", nrow(segs), wh[1], wh[2]))

  # Voice.
  timings <- vector("list", nrow(segs))
  segs$audio <- NA_character_
  for (i in which(is.na(segs$silent))) {
    v <- voice(segs[i, ], file.path(work, "audio", paste0(segs$id[i], ".mp3")))
    segs$audio[i] <- v$file
    timings[i] <- list(v$timing)
    lc_say(quiet, sprintf("Voiced %s (%d of %d).", segs$id[i], sum(!is.na(segs$audio)), n_voiced))
  }

  # Clips.
  segs$clip <- file.path(work, "clips", paste0(segs$id, ".mp4"))
  segs$clip_seconds <- NA_real_
  for (i in seq_len(nrow(segs))) {
    segs$clip_seconds[i] <- if (is.na(segs$silent[i])) {
      lc_still_clip(segs$png[i], segs$clip[i], cfg, audio = segs$audio[i])
    } else {
      lc_still_clip(segs$png[i], segs$clip[i], cfg, seconds = segs$silent[i])
    }
  }

  # Join, caption, transcript. Written under temporary names, renamed once
  # every check has passed.
  final <- file.path(out_dir, paste0(name, c(".mp4", ".vtt", "-transcript.md")))
  part <- file.path(out_dir, paste0(name, c(".partial.mp4", ".partial.vtt", "-transcript.partial.md")))
  on.exit(unlink(part), add = TRUE)
  total <- lc_concat(segs$clip, part[1])

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
lc_prepare_voice <- function(cfg, segs, name) {
  voiced <- segs$id[is.na(segs$silent)]
  if (cfg$voice$provider == "recorded") {
    files <- lc_recorded_files(voiced, cfg, name)
    return(function(seg, out) {
      f <- files[[seg$id]]
      lc_duration(f, "voice (recorded)")
      list(file = f, timing = NULL)
    })
  }
  voice_id <- lc_voice_id(cfg, "narrator")
  if (cfg$voice$provider == "elevenlabs") lc_elevenlabs_key("voice (elevenlabs)")
  if (cfg$voice$provider == "edge") lc_edge_command()
  function(seg, out) lc_voice(seg$text, voice_id, cfg, out)
}

lc_video_cues <- function(segs, timings, cfg) {
  starts <- c(0, cumsum(segs$clip_seconds))[seq_len(nrow(segs))]
  out <- list()
  for (i in which(is.na(segs$silent))) {
    a_dur <- segs$clip_seconds[i] - cfg$video$lead_in - cfg$video$tail
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
