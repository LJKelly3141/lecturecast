# Voice providers. Each returns the audio file and, when the provider gives
# it, timing data for captions. A failure stops the build; the provider is
# never switched.

lc_edge_version <- "7.3.1"

# The edge-tts command as c(command, leading args).
lc_edge_command <- function() {
  path <- lc_find_tool("edge-tts")
  if (nzchar(path)) return(path)
  uvx <- lc_find_tool("uvx")
  if (nzchar(uvx)) return(c(uvx, paste0("edge-tts@", getOption("lecturecast.edge_tts_version", lc_edge_version))))
  lc_abort("voice", "edge-tts was not found, and uv is not installed to run it.",
           fix = "Install uv (https://docs.astral.sh/uv/) or run: uv tool install edge-tts")
}

# The edge-tts version that will run, for the cache key: the pinned version
# under uvx, or what an installed edge-tts reports. Looked up once per session.
lc_edge_engine <- function() {
  cmd <- lc_edge_command()
  if (length(cmd) > 1) return(cmd[2])
  if (is.null(lc_state$edge_engine[[cmd]])) {
    res <- lc_run(cmd, "--version", step = "voice (edge)", timeout = 60)
    lc_state$edge_engine[[cmd]] <- paste0("edge-tts ", trimws(res$stdout))
  }
  lc_state$edge_engine[[cmd]]
}

lc_state <- new.env(parent = emptyenv())
lc_state$edge_engine <- list()

# Voice one piece of text to `out` (an .mp3 path). Returns
# list(file, timing) where timing is NULL, a data frame of cues (text,
# start, end) or a data frame of characters (char, start, end).
lc_voice <- function(text, voice_id, cfg, out, model = NULL) {
  switch(cfg$voice$provider,
    edge = lc_voice_edge(text, voice_id, cfg, out),
    elevenlabs = lc_voice_elevenlabs(text, voice_id, cfg, out, model = model),
    lc_abort("voice", paste0("Provider ", cfg$voice$provider, " cannot voice text."))
  )
}

lc_voice_edge <- function(text, voice_id, cfg, out) {
  step <- "voice (edge)"
  cmd <- lc_edge_command()
  txt <- tempfile(fileext = ".txt")
  srt <- tempfile(fileext = ".srt")
  on.exit(unlink(c(txt, srt)), add = TRUE)
  writeLines(enc2utf8(text), txt, useBytes = TRUE)
  args <- c(cmd[-1], "--voice", voice_id, "--file", txt,
            "--write-media", out, "--write-subtitles", srt)
  if (!is.null(cfg$voice$edge_rate)) args <- c(args, paste0("--rate=", cfg$voice$edge_rate))
  lc_run(cmd[1], args, step = step, file = out, timeout = 180,
         fix = "Check the voice id with: uvx edge-tts --list-voices. Edge voices need an internet connection.")
  lc_duration(out, step)
  timing <- if (file.exists(srt)) lc_parse_srt(readLines(srt, encoding = "UTF-8", warn = FALSE)) else NULL
  list(file = out, timing = timing)
}

lc_parse_srt <- function(lines) {
  lines <- sub("\r$", "", lines)
  arrow <- grep("-->", lines, fixed = TRUE)
  if (length(arrow) == 0) return(NULL)
  to_sec <- function(x) {
    p <- as.numeric(strsplit(sub(",", ".", trimws(x), fixed = TRUE), ":", fixed = TRUE)[[1]])
    p[1] * 3600 + p[2] * 60 + p[3]
  }
  cues <- lapply(seq_along(arrow), function(k) {
    i <- arrow[k]
    stop_at <- if (k < length(arrow)) arrow[k + 1] - 2 else length(lines)
    body <- lines[(i + 1):max(i + 1, stop_at)]
    body <- body[nzchar(trimws(body))]
    tt <- strsplit(lines[i], "-->", fixed = TRUE)[[1]]
    data.frame(text = paste(body, collapse = " "), start = to_sec(tt[1]), end = to_sec(tt[2]),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, cues)
}

lc_elevenlabs_key <- function(step) {
  key <- Sys.getenv("ELEVENLABS_API_KEY")
  if (!nzchar(key)) {
    lc_abort(step, "ELEVENLABS_API_KEY is not set.",
             fix = "Set it in ~/.Renviron (ELEVENLABS_API_KEY=...) and restart R. The key is never read from a settings file.")
  }
  key
}

lc_elevenlabs_base <- function() getOption("lecturecast.elevenlabs_url", "https://api.elevenlabs.io")

# Send a request to ElevenLabs and stop with a plain reason on failure.
lc_elevenlabs_perform <- function(req, step, out) {
  req <- httr2::req_timeout(req, getOption("lecturecast.http_timeout", 300))
  req <- httr2::req_error(req, is_error = function(resp) FALSE)
  resp <- tryCatch(httr2::req_perform(req),
                   error = function(e) lc_abort(step, paste0("Could not reach ElevenLabs: ", conditionMessage(e)),
                                                file = out, fix = "Check the internet connection, then build again."))
  status <- httr2::resp_status(resp)
  if (status >= 400) {
    detail <- tryCatch({
      b <- httr2::resp_body_json(resp)
      d <- b$detail
      if (is.list(d)) paste(unlist(d[c("status", "message")]), collapse = ": ") else as.character(d)
    }, error = function(e) "")
    fix <- switch(as.character(status),
      "401" = "The API key was refused. Check ELEVENLABS_API_KEY.",
      "402" = "The account is out of credits or the plan does not allow this. Check the ElevenLabs subscription.",
      "422" = "ElevenLabs rejected the request. Check the voice id and model in lecturecast.yml.",
      "429" = "ElevenLabs is rate limiting or out of quota. Wait, or check the account's credits.",
      "Try again later; the build will reuse audio already made.")
    if (grepl("quota|credit", detail, ignore.case = TRUE)) fix <- "The account is out of credits. Add credits, then build again."
    lc_abort(step, paste0("ElevenLabs returned HTTP ", status, if (nzchar(detail)) paste0(": ", detail) else "", "."),
             file = out, fix = fix)
  }
  resp
}

lc_voice_elevenlabs <- function(text, voice_id, cfg, out, model = NULL) {
  step <- "voice (elevenlabs)"
  key <- lc_elevenlabs_key(step)
  body <- list(text = text, model_id = model %||% cfg$voice$model)
  if (!is.null(cfg$voice$settings)) body$voice_settings <- cfg$voice$settings
  req <- httr2::request(lc_elevenlabs_base())
  req <- httr2::req_url_path_append(req, "v1", "text-to-speech", voice_id, "with-timestamps")
  req <- httr2::req_url_query(req, output_format = "mp3_44100_128")
  req <- httr2::req_headers(req, `xi-api-key` = key, .redact = "xi-api-key")
  req <- httr2::req_body_json(req, body, auto_unbox = TRUE)
  resp <- lc_elevenlabs_perform(req, step, out)
  res <- httr2::resp_body_json(resp, simplifyVector = TRUE)
  if (is.null(res$audio_base64)) lc_abort(step, "ElevenLabs returned no audio.", file = out)
  writeBin(jsonlite::base64_dec(res$audio_base64), out)
  lc_duration(out, step)
  list(file = out, timing = lc_alignment_chars(res$alignment))
}

lc_alignment_chars <- function(al) {
  if (is.null(al) || is.null(al$characters)) return(NULL)
  data.frame(char = unlist(al$characters),
             start = unlist(al$character_start_times_seconds),
             end = unlist(al$character_end_times_seconds),
             stringsAsFactors = FALSE)
}

# Recorded mode: <recorded_dir>/<deck name>/<segment id>.<wav|mp3|m4a|aiff>.
# Every missing file is listed before anything is built.
lc_recorded_files <- function(ids, cfg, deck_name) {
  base <- cfg$voice$recorded_dir
  if (!grepl("^(/|~|[A-Za-z]:)", base)) base <- file.path(dirname(cfg$path), base)
  dir <- file.path(base, deck_name)
  exts <- c("wav", "mp3", "m4a", "aiff")
  found <- vapply(ids, function(id) {
    f <- file.path(dir, paste0(id, ".", exts))
    hit <- f[file.exists(f)]
    if (length(hit)) hit[1] else NA_character_
  }, character(1))
  if (anyNA(found)) {
    lc_abort("voice (recorded)", paste0("Missing recordings: ", paste(ids[is.na(found)], collapse = ", "), "."),
             file = dir, fix = "Record each segment as <segment id>.wav (or .mp3, .m4a) in that folder. lecture_script() lists the slides.")
  }
  found
}
