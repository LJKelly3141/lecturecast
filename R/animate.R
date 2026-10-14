# Plotly animations played on cue. A quoted phrase in the notes that matches
# a button label on the slide (for example "AD falls") plays that button
# when the narration reaches the quote. Each Plotly frame is drawn and
# captured one at a time, then held for the frame duration the button sets,
# so the video is exact rather than a screen recording.

# Quoted phrases in the notes and where each starts, counted in non-space
# characters as the caption time map counts them.
lc_quotes <- function(text) {
  m <- gregexpr("(*UTF8)[\"\\x{201c}]([^\"\\x{201c}\\x{201d}]+)[\"\\x{201d}]", enc2utf8(text), perl = TRUE)[[1]]
  if (m[1] == -1) return(data.frame(phrase = character(0), pos = numeric(0)))
  starts <- as.integer(m)
  raw <- regmatches(enc2utf8(text), list(m))[[1]]
  phrase <- sub("^.", "", sub(".$", "", raw))
  phrase <- trimws(sub("[.,;:!?]+$", "", phrase))
  pos <- vapply(starts, function(s) lc_nows(substr(text, 1, s - 1)), numeric(1))
  data.frame(phrase = phrase, pos = pos, stringsAsFactors = FALSE)
}

# Labels and quotes compare without case or trailing punctuation.
lc_label_key <- function(x) tolower(trimws(sub("[.,;:!?]+$", "", trimws(x))))

# Buttons to play in one segment: quoted phrases matching a button label on
# the slide, case aside, in order. Only the first mention of a label on a
# slide plays, so a later reference ("as after 'AD falls'") does not replay
# it. `used` holds labels already played on this slide.
lc_segment_events <- function(text, buttons, used = character(0)) {
  none <- data.frame(label = character(0), plot = integer(0), menu = integer(0),
                     button = integer(0), pos = numeric(0), stringsAsFactors = FALSE)
  if (is.null(buttons) || nrow(buttons) == 0 || !nzchar(text)) return(none)
  q <- lc_quotes(text)
  if (nrow(q) == 0) return(none)
  key <- lc_label_key(buttons$label)
  rows <- list()
  for (k in seq_len(nrow(q))) {
    hit <- match(lc_label_key(q$phrase[k]), key)
    if (is.na(hit) || key[hit] %in% used) next
    used <- c(used, key[hit])
    rows[[length(rows) + 1]] <- data.frame(label = buttons$label[hit], plot = buttons$plot[hit],
                                           menu = buttons$menu[hit], button = buttons$button[hit],
                                           pos = q$pos[k], stringsAsFactors = FALSE)
  }
  if (length(rows) == 0) none else do.call(rbind, rows)
}

# Play one button on the current slide, capturing every frame. Returns the
# captured files and how long the deck holds each one, in seconds.
lc_capture_event <- function(b, ev, base, wh, deck) {
  step <- "animation"
  sel <- sprintf("Reveal.getCurrentSlide().querySelectorAll('.js-plotly-plot')[%d]", ev$plot)
  plan_js <- sprintf("(async () => {
    const gd = %s;
    if (!gd) return JSON.stringify({error: 'chart not found'});
    const bt = gd.layout.updatemenus[%d].buttons[%d];
    const args = bt.args || [];
    const method = bt.method || 'restyle';
    await Plotly.relayout(gd, {'updatemenus[%d].active': %d});
    if (method === 'skip') return JSON.stringify({error: 'the button does nothing (method skip)'});
    if (method !== 'animate') {
      if (typeof Plotly[method] !== 'function') return JSON.stringify({error: 'unknown button method ' + method});
      await Plotly[method](gd, ...args);
      return JSON.stringify({kind: 'static'});
    }
    const all = (gd._transitionData && gd._transitionData._frames) || [];
    let names = args[0];
    // As plotly.js reads them: null plays every frame, a string or number is
    // a frame group, an array lists frames by name (or frame objects).
    if (names === null || names === undefined) names = all.map(f => f.name);
    else if (!Array.isArray(names)) names = all.filter(f => String(f.group) === String(names)).map(f => f.name);
    else names = names.map(n => (n !== null && typeof n === 'object') ? n.name : n).filter(n => n !== null && n !== undefined).map(String);
    const opt = args[1] || {};
    if (Array.isArray(opt.frame) || Array.isArray(opt.transition)) return JSON.stringify({error: 'per-frame timing arrays are not supported'});
    // plotly.js defaults: frame 500 ms, transition 500 ms.
    const fd = (opt.frame && typeof opt.frame.duration === 'number') ? opt.frame.duration : 500;
    const td = (opt.transition && typeof opt.transition.duration === 'number') ? opt.transition.duration : 500;
    window.__lcFrames = names;
    return JSON.stringify({kind: 'animate', names: names, frame_ms: fd, transition_ms: td});
  })()", sel, ev$menu, ev$button, ev$menu, ev$button)
  plan <- jsonlite::fromJSON(lc_js(b, plan_js, step, deck))
  if (!is.null(plan$error)) {
    lc_abort(step, sprintf("Button \"%s\": %s.", ev$label, plan$error), file = deck)
  }
  settle <- "new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => r(true))))"
  if (identical(plan$kind, "static")) {
    lc_js(b, settle, step, deck)
    f <- sprintf("%s-001.png", base)
    lc_screenshot(b, f, wh[1], wh[2], deck)
    return(list(label = ev$label, files = f, seconds = 0.5))
  }
  if (plan$transition_ms > 0) {
    lc_abort(step, sprintf("Button \"%s\" uses Plotly transitions (%d ms), which cannot yet be captured frame by frame.",
                           ev$label, as.integer(plan$transition_ms)), file = deck,
             fix = "Set transition: {duration: 0} on that button, or turn off video: animations: in lecturecast.yml.")
  }
  if (length(plan$names) == 0) {
    lc_abort(step, sprintf("Button \"%s\" plays no frames.", ev$label), file = deck)
  }
  files <- character(length(plan$names))
  for (k in seq_along(plan$names)) {
    lc_js(b, sprintf("Plotly.animate(%s, [window.__lcFrames[%d]], {mode: 'immediate', frame: {duration: 0, redraw: true}, transition: {duration: 0}}).then(() => true)",
                     sel, k - 1L), step, deck)
    lc_js(b, settle, step, deck)
    files[k] <- sprintf("%s-%03d.png", base, k)
    lc_screenshot(b, files[k], wh[1], wh[2], deck)
  }
  list(label = ev$label, files = files, seconds = plan$frame_ms / 1000)
}

# The picture schedule for an animated segment: which image shows from when.
# Each animation starts when the narration reaches its quote, or when the
# one before it ends, whichever is later. Returns the images, their display
# lengths and the clip's total length.
lc_animation_schedule <- function(still, events, captured, text, timing, a_dur, cfg) {
  v <- cfg$video
  f <- lc_time_map(text, timing, a_dur)
  sentences <- lc_sentences(text)
  sent_end <- cumsum(lc_nows(sentences))
  files <- character(0)
  secs <- numeric(0)
  now <- 0
  current <- still
  for (k in seq_len(nrow(events))) {
    cap <- captured[[k]]
    start <- max(now, v$lead_in + f$start(events$pos[k]))
    frame_s <- cap$seconds / v$animation_speed
    run <- frame_s * length(cap$files)
    if (v$animation_pace == "sentence") {
      end_pos <- sent_end[which(sent_end > events$pos[k])[1]] %||% max(sent_end)
      span <- v$lead_in + f$end(end_pos) - start
      if (span > run) {
        frame_s <- span / length(cap$files)
        run <- span
      }
    }
    files <- c(files, current, cap$files)
    secs <- c(secs, start - now, rep(frame_s, length(cap$files)))
    now <- start + run
    current <- cap$files[length(cap$files)]
  }
  total <- max(v$lead_in + a_dur + v$tail, now + v$tail)
  files <- c(files, current)
  secs <- c(secs, total - now)
  keep <- secs > 1e-6
  list(files = files[keep], seconds = secs[keep], total = total)
}

# A clip that shows a schedule of pictures over the narration.
lc_animated_clip <- function(schedule, audio, out, cfg) {
  step <- "assemble"
  v <- cfg$video
  wh <- lc_resolutions[[v$resolution]]
  list_file <- paste0(out, ".txt")
  on.exit(unlink(list_file), add = TRUE)
  esc <- gsub("'", "'\\\\''", normalizePath(schedule$files))
  body <- as.vector(rbind(paste0("file '", esc, "'"), sprintf("duration %.4f", schedule$seconds)))
  # The concat demuxer needs the last picture listed again to honour its duration.
  writeLines(c("ffconcat version 1.0", body, paste0("file '", esc[length(esc)], "'")), list_file)
  lead_ms <- round(v$lead_in * 1000)
  graph <- paste(
    sprintf("[0:v]scale=%d:%d:flags=lanczos,setsar=1,fps=%s,format=yuv420p[v]", wh[1], wh[2], v$fps),
    sprintf("[1:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,adelay=%d:all=1,apad[a]", lead_ms),
    sep = ";")
  args <- c("-y", "-hide_banner", "-loglevel", "error",
            "-f", "concat", "-safe", "0", "-i", list_file, "-i", audio,
            "-filter_complex", graph, "-map", "[v]", "-map", "[a]",
            "-t", sprintf("%.3f", schedule$total), lc_ffmpeg_video_args(v$fps), out)
  lc_run(lc_tool("ffmpeg", step), args, step = step, file = out, timeout = 600)
  got <- lc_duration(out, step)
  if (abs(got - schedule$total) > 0.2) {
    lc_abort(step, sprintf("Animated clip is %.2f s long, expected %.2f s.", got, schedule$total), file = out)
  }
  got
}
