# FFmpeg assembly. Every clip has the same codecs, frame rate and audio
# layout, so they can be joined without re-encoding.

lc_ffmpeg_video_args <- function(fps) {
  c("-c:v", "libx264", "-preset", "medium", "-tune", "stillimage", "-crf", "18",
    "-pix_fmt", "yuv420p", "-r", as.character(fps),
    "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2")
}

# A clip of one still image. With audio, the clip is lead_in + audio + tail
# seconds long; without, it is `seconds` of silence.
lc_still_clip <- function(png, out, cfg, audio = NULL, seconds = NULL) {
  step <- "assemble"
  v <- cfg$video
  wh <- lc_resolutions[[v$resolution]]
  if (!is.null(audio)) {
    a_dur <- lc_duration(audio, step)
    total <- v$lead_in + a_dur + v$tail
    lead_ms <- round(v$lead_in * 1000)
    audio_in <- c("-i", audio)
    afilter <- sprintf("[1:a]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo,adelay=%d:all=1,apad[a]", lead_ms)
  } else {
    total <- seconds
    audio_in <- c("-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo")
    afilter <- "[1:a]anull[a]"
  }
  vfilter <- sprintf("[0:v]scale=%d:%d:flags=lanczos,setsar=1,format=yuv420p[v]", wh[1], wh[2])
  args <- c("-y", "-hide_banner", "-loglevel", "error",
            "-loop", "1", "-framerate", as.character(v$fps), "-i", png,
            audio_in,
            "-filter_complex", paste(vfilter, afilter, sep = ";"),
            "-map", "[v]", "-map", "[a]", "-t", sprintf("%.3f", total),
            lc_ffmpeg_video_args(v$fps), out)
  lc_run(lc_tool("ffmpeg", step), args, step = step, file = out, timeout = 300)
  got <- lc_duration(out, step)
  if (abs(got - total) > 0.2) {
    lc_abort(step, sprintf("Clip is %.2f s long, expected %.2f s.", got, total), file = out)
  }
  got
}

# Join clips end to end, without re-encoding. Returns the duration.
lc_concat <- function(clips, out, step = "assemble") {
  list_file <- tempfile(fileext = ".txt")
  on.exit(unlink(list_file), add = TRUE)
  esc <- gsub("'", "'\\\\''", normalizePath(clips))
  writeLines(paste0("file '", esc, "'"), list_file)
  args <- c("-y", "-hide_banner", "-loglevel", "error", "-f", "concat", "-safe", "0",
            "-i", list_file, "-c", "copy", "-movflags", "+faststart", out)
  lc_run(lc_tool("ffmpeg", step), args, step = step, file = out, timeout = 600)
  want <- sum(vapply(clips, lc_duration, numeric(1), step = step))
  got <- lc_duration(out, step)
  if (abs(got - want) > 0.1 * length(clips) + 0.25) {
    lc_abort(step, sprintf("Joined file is %.2f s long, but its parts add up to %.2f s.", got, want), file = out)
  }
  got
}

# A short silent clip fading from one picture to the next. It sits in the
# pause between two narrations, so no speech overlaps.
lc_fade_clip <- function(png_a, png_b, out, cfg) {
  step <- "assemble"
  v <- cfg$video
  wh <- lc_resolutions[[v$resolution]]
  d <- v$crossfade
  scale <- sprintf("scale=%d:%d:flags=lanczos,setsar=1,format=yuv420p,fps=%s", wh[1], wh[2], v$fps)
  graph <- sprintf("[0:v]%s[a];[1:v]%s[b];[a][b]xfade=transition=fade:duration=%.3f:offset=0[v]", scale, scale, d)
  args <- c("-y", "-hide_banner", "-loglevel", "error",
            "-loop", "1", "-framerate", as.character(v$fps), "-t", sprintf("%.3f", d), "-i", png_a,
            "-loop", "1", "-framerate", as.character(v$fps), "-t", sprintf("%.3f", d), "-i", png_b,
            "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
            "-filter_complex", graph, "-map", "[v]", "-map", "2:a", "-t", sprintf("%.3f", d),
            lc_ffmpeg_video_args(v$fps), out)
  lc_run(lc_tool("ffmpeg", step), args, step = step, file = out, timeout = 120)
  got <- lc_duration(out, step)
  if (abs(got - d) > 0.15) lc_abort(step, sprintf("Fade is %.2f s long, expected %.2f s.", got, d), file = out)
  got
}
