# YouTube upload. A video built by build_video() goes up with its captions
# and chapters, and a state file records each upload (video id and file
# hashes), so running again updates the same YouTube entry instead of
# making a duplicate. Uploading publishes; nothing here runs on its own.

lc_yt_scope <- "https://www.googleapis.com/auth/youtube.force-ssl"
lc_yt_api <- "https://www.googleapis.com/youtube/v3/"
lc_yt_upload_api <- "https://www.googleapis.com/upload/youtube/v3/"

#' Log in to YouTube
#'
#' Opens a browser to sign in to the Google account that owns the channel,
#' and keeps the login on this computer so later uploads need no browser.
#' Run it once in an interactive R session, and again if an upload says the
#' login has lapsed. The OAuth client comes from the `YT_CLIENT_ID` and
#' `YT_CLIENT_SECRET` environment variables (set them in `~/.Renviron`).
#'
#' @param quiet If `TRUE`, print nothing.
#' @return Invisibly, the channel's title.
#' @export
youtube_login <- function(quiet = FALSE) {
  if (!interactive()) {
    lc_abort("youtube", "Logging in opens a browser, so it needs an interactive R session.",
             fix = "Start R (or RStudio) yourself and run lecturecast::youtube_login().")
  }
  client <- lc_yt_client()
  httr2::oauth_cache_clear(client, cache_disk = TRUE)
  resp <- lc_yt_perform(httr2::req_url_query(lc_yt_req(paste0(lc_yt_api, "channels")), part = "snippet", mine = "true"),
                        "read the channel")
  items <- httr2::resp_body_json(resp)$items
  if (length(items) == 0) {
    lc_abort("youtube", "The account you logged in with has no YouTube channel.",
             fix = "Run youtube_login() again and choose the account that owns the channel.")
  }
  name <- items[[1]]$snippet$title
  lc_done(quiet, "Logged in to YouTube as channel: ", name)
  invisible(name)
}

#' Upload a lecture video to YouTube, or update the one already there
#'
#' Uploads a video made by [build_video()], with its captions (`.vtt`) as the
#' captions track, its chapters (`-chapters.txt`) at the end of the
#' description and its thumbnail (`-thumbnail.jpg`), and adds it to a
#' playlist if one is given. Each upload is
#' recorded in a state file, so running again with the same video updates
#' the existing entry (title, description, tags, privacy, captions,
#' thumbnail) rather
#' than uploading a duplicate.
#'
#' YouTube cannot swap the file of an existing video. If the video file has
#' changed since it was uploaded, the call stops, unless `replace = TRUE`:
#' then the new file is uploaded, it takes the old video's place in the
#' playlist, and the old video is set to private (not deleted).
#'
#' Uploading publishes. Run with `dry_run = TRUE` first to see exactly what
#' would be sent.
#'
#' @param video Path to the `.mp4` from [build_video()].
#' @param title The video's title (at most 100 characters).
#' @param description The description, before the chapter list.
#' @param tags Character vector of tags.
#' @param privacy `"unlisted"` (the default), `"private"` or `"public"`.
#' @param playlist A playlist id, or a playlist link. `NULL` adds the video to
#'   no playlist (a replaced video keeps its old playlist).
#' @param captions If `TRUE`, upload the `.vtt` beside the video.
#' @param chapters If `TRUE`, add the chapters beside the video to the
#'   description. YouTube needs at least three.
#' @param thumbnail `TRUE` to upload the thumbnail beside the video, `FALSE`
#'   for none (YouTube picks a frame), or the path to a JPEG or PNG of your
#'   own (at most 2 MB; 1280x720 is best). Custom thumbnails need a verified
#'   channel.
#' @param replace If `TRUE`, a changed video file is uploaded as a new video
#'   that replaces the old one, as described above.
#' @param state Path to the state file. By default `lecturecast-youtube.json`
#'   next to the `lecturecast.yml` that applies to the video, else beside the
#'   video. Keep it in git: without it, the next run uploads a duplicate.
#' @param dry_run If `TRUE`, show what would be done and send nothing.
#' @param quiet If `TRUE`, print only errors.
#' @return Invisibly, a list with the action, video id and link.
#' @export
youtube_upload <- function(video, title, description = "", tags = character(0),
                           privacy = c("unlisted", "private", "public"), playlist = NULL,
                           captions = TRUE, chapters = TRUE, thumbnail = TRUE, replace = FALSE,
                           state = NULL, dry_run = FALSE, quiet = FALSE) {
  privacy <- match.arg(privacy)
  plan <- lc_yt_plan(video, title, description, tags, privacy, playlist, captions, chapters, replace, state,
                     thumbnail)
  lc_yt_show(plan, quiet || !dry_run)
  if (dry_run) return(invisible(plan))

  e <- plan$entry
  if (!is.null(e)) lc_yt_check_exists(e$video_id, plan$state)
  save <- function(e) lc_yt_write_state(plan$state, plan$key, e)

  if (plan$action %in% c("upload", "replace")) {
    old <- e
    id <- lc_yt_insert_video(plan, quiet)
    now <- lc_yt_now()
    e <- list(video_id = id, video_hash = plan$video_hash, title = plan$title,
              description = plan$description, tags = as.list(plan$tags), privacy = plan$privacy,
              uploaded_at = now, updated_at = now)
    if (!is.null(old)) {
      e$superseded <- c(unlist(old$superseded), old$video_id)
      e$pending_private <- old$video_id
      if (!is.null(old$playlist_item_id)) {
        e$replace_item <- list(playlist = old$playlist, item = old$playlist_item_id)
      }
    }
    save(e)
    lc_done(quiet, "Uploaded ", plan$video, " as https://youtu.be/", id, " (", plan$privacy, ").")
  } else if (length(plan$changes)) {
    lc_yt_update_video(e$video_id, plan)
    e[c("title", "description", "privacy")] <- list(plan$title, plan$description, plan$privacy)
    e$tags <- as.list(plan$tags)
    e$updated_at <- lc_yt_now()
    save(e)
    lc_done(quiet, "Updated ", paste(plan$changes, collapse = ", "), " of https://youtu.be/", e$video_id, ".")
  }

  if (!is.null(plan$captions) && (is.null(e$caption_id) || !identical(e$captions_hash, plan$captions_hash))) {
    if (!is.null(e$caption_id)) {
      lc_yt_perform(httr2::req_method(httr2::req_url_query(lc_yt_req(paste0(lc_yt_api, "captions")), id = e$caption_id),
                                      "DELETE"), "remove the old captions", ok404 = TRUE)
      e$caption_id <- NULL
      save(e)
    }
    e$caption_id <- lc_yt_insert_captions(e$video_id, plan$captions)
    e$captions_hash <- plan$captions_hash
    save(e)
    lc_done(quiet, "Captions uploaded from ", plan$captions, ".")
  }

  if (!is.null(plan$thumbnail) && !identical(e$thumbnail_hash, plan$thumbnail_hash)) {
    lc_yt_set_thumbnail(e$video_id, plan$thumbnail)
    e$thumbnail_hash <- plan$thumbnail_hash
    save(e)
    lc_done(quiet, "Thumbnail uploaded from ", plan$thumbnail, ".")
  }

  if (!is.null(plan$playlist) && !(identical(e$playlist, plan$playlist) && !is.null(e$playlist_item_id))) {
    pos <- NULL
    if (!is.null(e$replace_item) && identical(e$replace_item$playlist, plan$playlist)) {
      pos <- lc_yt_item_position(e$replace_item$item)
    }
    # A playlist sorted by YouTube (not by hand) takes no position.
    e$playlist_item_id <- if (is.null(pos)) {
      lc_yt_add_to_playlist(plan$playlist, e$video_id)
    } else {
      tryCatch(lc_yt_add_to_playlist(plan$playlist, e$video_id, pos),
               lecturecast_error = function(err) lc_yt_add_to_playlist(plan$playlist, e$video_id))
    }
    e$playlist <- plan$playlist
    save(e)
    lc_done(quiet, "Added to playlist ", plan$playlist, ".")
  }
  if (!is.null(e$replace_item)) {
    lc_yt_perform(httr2::req_method(httr2::req_url_query(lc_yt_req(paste0(lc_yt_api, "playlistItems")),
                                                         id = e$replace_item$item), "DELETE"),
                  "remove the old video from the playlist", ok404 = TRUE)
    e$replace_item <- NULL
    save(e)
  }
  if (!is.null(e$pending_private)) {
    lc_yt_set_private(e$pending_private)
    lc_done(quiet, "Set the old video https://youtu.be/", e$pending_private, " to private.")
    e$pending_private <- NULL
    save(e)
  }
  if (plan$action == "update" && length(plan$changes) == 0 && identical(e, plan$entry)) {
    lc_done(quiet, "Nothing to change: https://youtu.be/", e$video_id, " is up to date.")
  }
  lc_done(quiet, "Completed: https://youtu.be/", e$video_id, " (state in ", plan$state, ").")
  invisible(list(action = plan$action, video_id = e$video_id, url = paste0("https://youtu.be/", e$video_id)))
}

# Everything decided before anything is sent: checked inputs, the full
# description, file hashes, the state entry and the action.
lc_yt_plan <- function(video, title, description, tags, privacy, playlist, captions, chapters, replace, state,
                       thumbnail = FALSE) {
  step <- "youtube"
  if (!is.character(video) || length(video) != 1 || !file.exists(video)) {
    lc_abort(step, "The video file does not exist.", file = if (is.character(video)) video[1] else NULL)
  }
  if (!grepl("\\.mp4$", video, ignore.case = TRUE)) lc_abort(step, "The video must be an .mp4 from build_video().", file = video)
  video <- normalizePath(video)
  base <- sub("\\.mp4$", "", video, ignore.case = TRUE)
  if (!is.character(title) || length(title) != 1 || !nzchar(trimws(title))) lc_abort(step, "The video needs a title.")
  title <- trimws(title)
  if (nchar(title) > 100) lc_abort(step, sprintf("The title is %d characters; YouTube allows 100.", nchar(title)))
  tags <- as.character(unlist(tags))
  if (length(playlist)) playlist <- lc_yt_playlist_id(playlist)

  ch_file <- paste0(base, "-chapters.txt")
  ch_lines <- character(0)
  if (isTRUE(chapters)) {
    if (!file.exists(ch_file)) {
      lc_abort(step, "The chapter list is missing.", file = ch_file,
               fix = "Build the video again with this version of lecturecast, or use chapters = FALSE.")
    }
    ch_lines <- readLines(ch_file, warn = FALSE, encoding = "UTF-8")
    ch_lines <- ch_lines[nzchar(trimws(ch_lines))]
  }
  full <- trimws(paste(description, collapse = "\n"))
  if (length(ch_lines) >= 3) {
    full <- paste0(full, if (nzchar(full)) "\n\n" else "", paste(ch_lines, collapse = "\n"))
  }
  for (x in list(list("title", title), list("description", full))) {
    if (grepl("[<>]", x[[2]])) lc_abort(step, sprintf("YouTube does not allow < or > in the %s.", x[[1]]))
  }
  if (nchar(full, type = "bytes") > 5000) {
    lc_abort(step, sprintf("The description is %d bytes with the chapters; YouTube allows 5000.", nchar(full, type = "bytes")))
  }

  vtt <- NULL
  vtt_hash <- NULL
  if (isTRUE(captions)) {
    vtt <- paste0(base, ".vtt")
    if (!file.exists(vtt)) lc_abort(step, "The captions file is missing.", file = vtt, fix = "Build the video again, or use captions = FALSE.")
    vtt_hash <- cli::hash_file_sha256(vtt)
  }

  thumb <- NULL
  thumb_hash <- NULL
  if (!isFALSE(thumbnail) && !is.null(thumbnail)) {
    thumb <- if (isTRUE(thumbnail)) paste0(base, "-thumbnail.jpg") else as.character(thumbnail)[1]
    if (!file.exists(thumb)) {
      lc_abort(step, "The thumbnail is missing.", file = thumb,
               fix = if (isTRUE(thumbnail)) "Build the video again with this version of lecturecast, or use thumbnail = FALSE." else NULL)
    }
    if (!grepl("\\.(jpe?g|png)$", thumb, ignore.case = TRUE)) lc_abort(step, "The thumbnail must be a JPEG or PNG.", file = thumb)
    if (file.size(thumb) > 2e6) lc_abort(step, "The thumbnail is over YouTube's 2 MB limit.", file = thumb)
    thumb <- normalizePath(thumb)
    thumb_hash <- cli::hash_file_sha256(thumb)
  }

  state <- state %||% {
    cfg <- lc_find_config(video)
    file.path(if (is.null(cfg)) dirname(video) else dirname(normalizePath(cfg)), "lecturecast-youtube.json")
  }
  key <- basename(base)
  entry <- lc_yt_read_state(state)[[key]]
  hash <- cli::hash_file_sha256(video)
  action <- if (is.null(entry)) "upload" else if (identical(entry$video_hash, hash)) "update" else "replace"
  if (action == "replace" && !isTRUE(replace)) {
    lc_abort(step, sprintf("The video file has changed since it was uploaded as https://youtu.be/%s, and YouTube cannot swap a video's file.",
                           entry$video_id), file = video,
             fix = "Run again with replace = TRUE to upload it as a new video that takes the old one's playlist place; the old video is set to private, not deleted.")
  }
  if (action == "replace" && is.null(playlist)) playlist <- entry$playlist

  changes <- character(0)
  if (action == "update") {
    if (!identical(entry$title, title)) changes <- c(changes, "title")
    if (!identical(entry$description, full)) changes <- c(changes, "description")
    if (!identical(as.character(unlist(entry$tags)), tags)) changes <- c(changes, "tags")
    if (!identical(entry$privacy, privacy)) changes <- c(changes, "privacy")
  }
  list(video = video, title = title, description = full, tags = tags, privacy = privacy,
       playlist = playlist, captions = vtt, captions_hash = vtt_hash, chapters = length(ch_lines),
       thumbnail = thumb, thumbnail_hash = thumb_hash,
       chapters_file = ch_file, state = state, key = key, entry = entry, video_hash = hash,
       action = action, changes = changes)
}

lc_yt_show <- function(plan, quiet) {
  if (quiet) return(invisible())
  e <- plan$entry
  what <- switch(plan$action,
    upload = "Upload as a new video.",
    replace = sprintf("Upload the changed file as a new video, then set the old one (https://youtu.be/%s) to private%s.",
                      e$video_id, if (!is.null(e$playlist_item_id)) " and put the new one in its playlist place" else ""),
    update = if (length(plan$changes)) sprintf("Update https://youtu.be/%s: %s.", e$video_id, paste(plan$changes, collapse = ", "))
             else sprintf("https://youtu.be/%s has the same file, title, description, tags and privacy.", e$video_id))
  was <- if (!is.null(e) && !identical(e$privacy, plan$privacy)) paste0(" (was ", e$privacy, ")") else ""
  cap <- if (is.null(plan$captions)) "none" else if (plan$action == "update" && identical(e$captions_hash, plan$captions_hash) &&
                                                     !is.null(e$caption_id)) paste(plan$captions, "(unchanged)") else plan$captions
  ch <- if (plan$chapters >= 3) sprintf("%d, in the description", plan$chapters)
        else if (plan$chapters > 0) sprintf("%d, left out (YouTube needs at least 3)", plan$chapters) else "none"
  cli::cli_h2("YouTube")
  lines <- c(
    paste0("Action: ", what),
    paste0("Video: ", plan$video),
    paste0("Title: ", plan$title),
    paste0("Privacy: ", plan$privacy, was),
    paste0("Playlist: ", plan$playlist %||% "none"),
    paste0("Tags: ", if (length(plan$tags)) paste(plan$tags, collapse = ", ") else "none"),
    paste0("Captions: ", cap),
    paste0("Chapters: ", ch),
    paste0("Thumbnail: ", if (is.null(plan$thumbnail)) "none (YouTube picks a frame)"
                          else if (!is.null(e) && identical(e$thumbnail_hash, plan$thumbnail_hash)) paste(plan$thumbnail, "(unchanged)")
                          else plan$thumbnail),
    paste0("State file: ", plan$state)
  )
  for (ln in lines) cli::cli_text(lc_esc(ln))
  cli::cli_text("Description:")
  cli::cli_verbatim(if (nzchar(plan$description)) plan$description else "(empty)")
  invisible()
}

lc_yt_playlist_id <- function(x) {
  x <- trimws(as.character(x)[1])
  m <- regmatches(x, regexec("[?&]list=([A-Za-z0-9_-]+)", x))[[1]]
  if (length(m) == 2) x <- m[2]
  if (!grepl("^[A-Za-z0-9_-]+$", x)) {
    lc_abort("youtube", paste0("This is not a playlist id or link: ", x),
             fix = "Copy the playlist's link from YouTube; its id follows list=.")
  }
  x
}

# State: one JSON object keyed by video name (the .mp4's name without
# extension). Written whole to a temporary file, then renamed.
lc_yt_read_state <- function(path) {
  if (!file.exists(path)) return(list())
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE),
           error = function(e) lc_abort("youtube", paste0("The state file is not valid JSON: ", conditionMessage(e)), file = path,
                                        fix = "Restore it from git; without it the next upload would be a duplicate."))
}

lc_yt_write_state <- function(path, key, entry) {
  all <- lc_yt_read_state(path)
  all[[key]] <- entry
  all <- all[order(names(all))]
  tmp <- paste0(path, ".tmp")
  writeLines(enc2utf8(as.character(jsonlite::toJSON(all, auto_unbox = TRUE, pretty = TRUE, null = "null"))),
             tmp, useBytes = TRUE)
  if (!file.rename(tmp, path)) {
    unlink(tmp)
    lc_abort("youtube", "Could not write the state file.", file = path,
             fix = paste0("Note the video id ", entry$video_id, " and add it to the state file by hand."))
  }
  invisible(path)
}

lc_yt_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

lc_yt_client <- function() {
  id <- Sys.getenv("YT_CLIENT_ID")
  secret <- Sys.getenv("YT_CLIENT_SECRET")
  if (!nzchar(id) || !nzchar(secret)) {
    lc_abort("youtube", "YT_CLIENT_ID and YT_CLIENT_SECRET are not both set.",
             fix = "Add both to ~/.Renviron (the OAuth client from Google Cloud Console) and restart R.")
  }
  httr2::oauth_client(id = id, token_url = "https://oauth2.googleapis.com/token", secret = secret,
                      name = "lecturecast-youtube")
}

lc_yt_req <- function(url) {
  req <- httr2::request(url)
  req <- httr2::req_oauth_auth_code(req, lc_yt_client(), auth_url = "https://accounts.google.com/o/oauth2/v2/auth",
                                    scope = lc_yt_scope, redirect_uri = "http://localhost:1410/",
                                    auth_params = list(access_type = "offline", prompt = "consent"),
                                    cache_disk = TRUE)
  req <- httr2::req_timeout(req, 120)
  httr2::req_error(req, is_error = function(resp) FALSE)
}

# Send a request and stop with YouTube's own reason on failure.
lc_yt_perform <- function(req, what, file = NULL, ok404 = FALSE) {
  step <- "youtube"
  resp <- tryCatch(httr2::req_perform(req), error = function(e) {
    msg <- conditionMessage(e)
    if (grepl("interactive", msg, ignore.case = TRUE)) {
      lc_abort(step, "YouTube needs you to log in, and this R session cannot open a browser.", file = file,
               fix = "Run lecturecast::youtube_login() once in an interactive R session, then try again.")
    }
    lc_abort(step, paste0("Could not reach YouTube to ", what, ": ", msg), file = file)
  })
  st <- httr2::resp_status(resp)
  if (st == 404 && ok404) return(resp)
  if (st >= 400) {
    b <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
    detail <- b$error$message %||% ""
    reason <- tryCatch(b$error$errors[[1]]$reason, error = function(e) NULL) %||% ""
    fix <- if (st == 401) {
      "Run lecturecast::youtube_login() again."
    } else if (grepl("quota", reason, ignore.case = TRUE)) {
      "The day's YouTube API quota is used up. Try again tomorrow; what is done is in the state file, and the next run picks up from there."
    } else if (st == 403) {
      "Check that the account you logged in with owns the channel, the video and the playlist."
    } else NULL
    lc_abort(step, sprintf("YouTube refused to %s (HTTP %d%s).", what, st,
                           if (nzchar(detail)) paste0(": ", detail) else ""), file = file, fix = fix)
  }
  resp
}

# A resumable upload: send the metadata, then the file to the address
# YouTube gives back. Returns the response to the file.
lc_yt_resumable <- function(url, query, meta, file, type, what, timeout = 600, progress = FALSE) {
  req <- httr2::req_url_query(lc_yt_req(url), uploadType = "resumable", !!!query)
  req <- httr2::req_headers(req, `X-Upload-Content-Type` = type,
                            `X-Upload-Content-Length` = format(file.size(file), scientific = FALSE))
  resp <- lc_yt_perform(httr2::req_body_json(req, meta, auto_unbox = TRUE), what, file = file)
  loc <- httr2::resp_header(resp, "location")
  if (is.null(loc)) lc_abort("youtube", paste0("YouTube gave no upload address to ", what, "."), file = file)
  put <- httr2::req_body_file(httr2::req_method(lc_yt_req(loc), "PUT"), file, type = type)
  put <- httr2::req_timeout(put, timeout)
  if (progress) put <- httr2::req_progress(put, "up")
  lc_yt_perform(put, what, file = file)
}

lc_yt_snippet <- function(plan) {
  s <- list(title = plan$title, description = plan$description, categoryId = "27",
            defaultLanguage = "en-US", defaultAudioLanguage = "en-US")
  if (length(plan$tags)) s$tags <- as.list(plan$tags)
  s
}

lc_yt_insert_video <- function(plan, quiet) {
  meta <- list(snippet = lc_yt_snippet(plan), status = list(privacyStatus = plan$privacy))
  lc_say(quiet, "Uploading ", basename(plan$video), sprintf(" (%.0f MB).", file.size(plan$video) / 1e6))
  resp <- lc_yt_resumable(paste0(lc_yt_upload_api, "videos"), list(part = "snippet,status"), meta,
                          plan$video, "video/mp4", "upload the video", timeout = 6 * 3600, progress = !quiet)
  id <- httr2::resp_body_json(resp)$id
  if (is.null(id)) lc_abort("youtube", "YouTube accepted the upload but returned no video id.", file = plan$video,
                            fix = "Check YouTube Studio for the video before uploading again.")
  id
}

lc_yt_update_video <- function(id, plan) {
  body <- list(id = id, snippet = lc_yt_snippet(plan), status = list(privacyStatus = plan$privacy))
  req <- httr2::req_url_query(lc_yt_req(paste0(lc_yt_api, "videos")), part = "snippet,status")
  lc_yt_perform(httr2::req_method(httr2::req_body_json(req, body, auto_unbox = TRUE), "PUT"), "update the video")
}

lc_yt_set_private <- function(id) {
  body <- list(id = id, status = list(privacyStatus = "private"))
  req <- httr2::req_url_query(lc_yt_req(paste0(lc_yt_api, "videos")), part = "status")
  lc_yt_perform(httr2::req_method(httr2::req_body_json(req, body, auto_unbox = TRUE), "PUT"),
                "set the old video to private")
}

lc_yt_check_exists <- function(id, state) {
  resp <- lc_yt_perform(httr2::req_url_query(lc_yt_req(paste0(lc_yt_api, "videos")), part = "id", id = id),
                        "look up the video")
  if (length(httr2::resp_body_json(resp)$items) == 0) {
    lc_abort("youtube", sprintf("The state file records https://youtu.be/%s, but that video is not on the channel.", id),
             file = state, fix = "If it was deleted on purpose, remove its entry from the state file; the next run uploads afresh.")
  }
  invisible(TRUE)
}

lc_yt_insert_captions <- function(id, vtt) {
  meta <- list(snippet = list(videoId = id, language = "en", name = "English", isDraft = FALSE))
  resp <- lc_yt_resumable(paste0(lc_yt_upload_api, "captions"), list(part = "snippet"), meta,
                          vtt, "application/octet-stream", "upload the captions")
  cid <- httr2::resp_body_json(resp)$id
  if (is.null(cid)) lc_abort("youtube", "YouTube accepted the captions but returned no id.", file = vtt)
  cid
}

lc_yt_add_to_playlist <- function(playlist, id, position = NULL) {
  snip <- list(playlistId = playlist, resourceId = list(kind = "youtube#video", videoId = id))
  if (!is.null(position)) snip$position <- position
  req <- httr2::req_url_query(lc_yt_req(paste0(lc_yt_api, "playlistItems")), part = "snippet")
  resp <- lc_yt_perform(httr2::req_body_json(req, list(snippet = snip), auto_unbox = TRUE), "add the video to the playlist")
  httr2::resp_body_json(resp)$id
}

# Where an item sits in its playlist, or NULL if it is gone.
lc_yt_item_position <- function(item) {
  resp <- lc_yt_perform(httr2::req_url_query(lc_yt_req(paste0(lc_yt_api, "playlistItems")), part = "snippet", id = item),
                        "look up the old playlist place")
  items <- httr2::resp_body_json(resp)$items
  if (length(items) == 0) NULL else items[[1]]$snippet$position
}

lc_yt_set_thumbnail <- function(id, file) {
  type <- if (grepl("\\.png$", file, ignore.case = TRUE)) "image/png" else "image/jpeg"
  req <- httr2::req_url_query(lc_yt_req(paste0(lc_yt_upload_api, "thumbnails/set")), videoId = id, uploadType = "media")
  tryCatch(lc_yt_perform(httr2::req_body_file(req, file, type = type), "set the thumbnail", file = file),
           lecturecast_error = function(err) {
             msg <- conditionMessage(err)
             if (!grepl("HTTP 403", msg) || grepl("quota", msg, ignore.case = TRUE)) stop(err)
             lc_abort("youtube", "YouTube refused the custom thumbnail (HTTP 403).", file = file,
                      fix = "Custom thumbnails need a verified channel (youtube.com/verify). Or use thumbnail = FALSE; the video is uploaded either way.")
           })
}
