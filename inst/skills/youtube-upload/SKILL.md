---
name: youtube-upload
description: Upload a lecture video built by lecturecast to YouTube, with its captions and chapters, or update one already uploaded. Use when the instructor says "upload the video", "put it on YouTube", "publish the lecture", "update the YouTube video", "replace the video on YouTube", or asks to change a lecture video's title, description, privacy or playlist.
---

# YouTube upload

Uploading publishes under the instructor's name. Nothing goes to YouTube
without the instructor's yes for that upload.

## Rules

1. **Confirm before every upload or update.** Show the dry run (step 2)
   and get the instructor's yes to the title, privacy and playlist, and to
   the description as shown. A yes covers that one call only. A yes for one
   video is not a yes for the next, and an earlier session's yes is not a
   yes now.
2. **Never upload on your own initiative**, in a loop, or as a step of a
   build. A finished `build_video()` is not a request to upload.
3. **Privacy defaults to unlisted.** Use public or private only when the
   instructor says so for this video.
4. **Do not invent metadata.** Propose a title and description from the
   deck (its title, the chapter it covers), mark them as proposals, and use
   only what the instructor approves. No em-dashes in the title or
   description.
5. **Replace only on request.** If the video file changed since it was
   uploaded, `youtube_upload()` stops. `replace = TRUE` uploads a new
   video, moves it into the old one's playlist place and sets the old one
   to private. Say all three to the instructor and get a yes before using
   it. Nothing is ever deleted from YouTube.
6. **Keep the state file.** `lecturecast-youtube.json` (next to
   `lecturecast.yml`) records each upload. Without it the next run uploads
   a duplicate. Suggest committing it after an upload; do not commit
   without the instructor's say-so.
7. **Never print or write the OAuth client secret or tokens.** They come
   from `YT_CLIENT_ID` and `YT_CLIENT_SECRET` in `~/.Renviron` and the login
   httr2 keeps in its cache.

## Steps

0. **Login, once per computer.** The first upload needs a browser login,
   which only works in an interactive R session, not in `Rscript`. Ask the
   instructor to start R or RStudio and run `lecturecast::youtube_login()`
   there. It prints the
   channel's name; check it is the right channel. If the Google project is
   in "Testing", the login lapses after 7 days and has to be repeated.
1. **Check the files.** The `.mp4`, `.vtt` and `-chapters.txt` from
   `build_video()` sit together in the output folder. Read the chapter list
   and point out any chapter titles that read badly; fix them in the deck
   (slide titles) and rebuild, never by editing the file by hand without
   asking.
2. **Dry run.**
   ```r
   lecturecast::youtube_upload("build/video/<deck>.mp4",
     title = "<approved title>", description = "<approved text>",
     tags = c("<tag>", "..."), privacy = "unlisted",
     playlist = "<playlist id or link>", dry_run = TRUE)
   ```
   It prints the action (new upload, update with the fields that change,
   or the replace a changed file needs), title, privacy (and what it was),
   playlist, tags, captions, chapters, thumbnail and the full description.
   Nothing is sent. Show the instructor the thumbnail image too
   (`<deck>-thumbnail.jpg`, the title slide unless `video: thumbnail:` in
   `lecturecast.yml` names another slide; `thumbnail = "<file>"` uses their
   own image, such as one made with Codex; see "A generated thumbnail").
   Custom thumbnails need a verified channel. Show it to the instructor.
3. **Upload** with the same call and `dry_run = FALSE`, only after the yes.
   Report the link (`https://youtu.be/<id>`) and what was done.
4. **If it stops partway** (network, quota), run the same call again: the
   state file records what is done, and the next run does the rest. A quota
   error means the day's YouTube API allowance is used up; try tomorrow.

## What it does on a second run

- Same video file: updates title, description, tags and privacy if they
  differ, and replaces the captions or thumbnail if that file changed. Edits made in
  YouTube Studio to those fields are overwritten.
- Changed video file: stops, unless `replace = TRUE` (rule 5).
- A video deleted in Studio: stops, and says to remove its entry from the
  state file.

## Chapters

`build_video()` writes `<deck>-chapters.txt` from each slide's start time:
first chapter at 0:00, each at least 10 seconds (a shorter one joins the
next), a section divider (`#` heading) folded into the slide after it, the
title slide named "Introduction", and slides that share a title in a row
joined. The chapter titles are the slide titles, so good slide titles make
good chapters. YouTube shows chapters only when there are at least three.

## A generated thumbnail

Only when the instructor asks for one. The package never calls an image
model; Codex makes the image, and it goes to `youtube_upload()` as a file.

1. **Agree the brief first.** Propose the words on the image (the lecture
   title, short) and the idea for the picture, from the deck. Get a yes
   before generating: each run uses the instructor's OpenAI allowance.
2. **Generate** into the build folder, never into the course source:
   ```sh
   codex exec --skip-git-repo-check -s workspace-write -C build/video \
     -i build/video/<deck>-thumbnail.jpg \
     "Use your image generation tool to make a 16:9 YouTube thumbnail for a
      lecture titled '<approved words>'. <approved idea>. Bold short title
      text, flat illustration, no logos, no real people, no other text.
      Save it in this folder as <deck>-thumbnail-ai.png and reply with its path."
   ```
   `-i` passes the built thumbnail for its colours and layout; leave it out
   for a free design. It takes about a minute.
3. **Fit it to YouTube's size** (1280x720 JPEG, under 2 MB):
   ```sh
   ffmpeg -y -i build/video/<deck>-thumbnail-ai.png \
     -vf "scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2:white" \
     -q:v 2 build/video/<deck>-thumbnail-ai.jpg
   ```
4. **Show the image** and check the spelling of every word on it, since
   image models misspell. The instructor approves it, asks for another
   (say what to change), or keeps the built one.
5. Pass the approved file: `thumbnail = "build/video/<deck>-thumbnail-ai.jpg"`
   in the dry run and the upload.

No real people, logos, or anything that looks like a real photo. The
thumbnail must not promise content the lecture does not have.
