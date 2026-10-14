# Turning slides and their notes into voiced segments.

# One row per segment. A slide with notes is one segment, or one per
# fragment step when `split_fragments` is TRUE and the notes carry the
# matching number of parts (see lc_split_fragment_notes). A slide with no
# notes stops the build unless it is marked silent with a duration.
lc_segments <- function(slides, silent = list(), split_fragments = FALSE, deck = NULL) {
  step <- "script"
  silent_secs <- lc_silent_map(slides, silent, deck)
  rows <- list()
  missing <- integer(0)
  for (i in seq_len(nrow(slides))) {
    s <- slides[i, ]
    secs <- silent_secs[i]
    has_notes <- nzchar(s$notes)
    if (has_notes && !is.na(secs)) {
      lc_abort(step, sprintf("Slide %d (%s) has speaker notes and is also marked silent.", s$index, lc_title(s)),
               file = deck, fix = "Remove the notes or the silent mark for that slide.")
    }
    if (!has_notes && is.na(secs)) {
      missing <- c(missing, i)
      next
    }
    parts <- if (has_notes && split_fragments && s$n_fragments > 0) {
      lc_split_fragment_notes(s, deck)
    } else if (has_notes) {
      s$notes
    } else {
      ""
    }
    # Part 1 is spoken before any fragment shows (fragment step -1). A single
    # part plays with every fragment shown.
    frag <- if (length(parts) > 1) seq_along(parts) - 2L else s$n_fragments - 1L
    for (k in seq_along(parts)) {
      rows[[length(rows) + 1]] <- data.frame(
        id = if (length(parts) > 1) sprintf("s%02d-%d", s$index, k) else sprintf("s%02d", s$index),
        slide = s$index, h = s$h, v = s$v, fragment = frag[k],
        title = s$title, text = parts[k],
        silent = if (has_notes) NA_real_ else secs,
        stringsAsFactors = FALSE
      )
    }
  }
  if (length(missing)) {
    which <- paste(sprintf("%d (%s)", slides$index[missing], vapply(missing, function(i) lc_title(slides[i, ]), "")),
                   collapse = ", ")
    lc_abort(step, paste0("These slides have no speaker notes: ", which, "."), file = deck,
             fix = "Add ::: notes to each, or mark it silent with a duration: {data-silent=\"3\"} on the slide heading, or video: silent: in lecturecast.yml (slide number or title: seconds).")
  }
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  if (all(!is.na(out$silent))) {
    lc_abort(step, "No slide has speaker notes, so there is nothing to voice.", file = deck,
             fix = "Add ::: notes to the slides to narrate.")
  }
  out
}

lc_title <- function(s) if (nzchar(s$title)) s$title else "untitled"

# Silent durations per slide, from the data-silent attribute and from the
# settings file, where keys are slide numbers or exact slide titles.
lc_silent_map <- function(slides, silent, deck) {
  secs <- slides$silent
  if (length(silent) == 0) return(secs)
  for (key in names(silent)) {
    val <- suppressWarnings(as.numeric(silent[[key]]))
    if (length(val) != 1 || is.na(val) || val <= 0) {
      lc_abort("settings", paste0("video: silent: ", key, " must be a number of seconds."))
    }
    num <- suppressWarnings(as.integer(key))
    hit <- if (!is.na(num) && grepl("^[0-9]+$", key)) {
      which(slides$index == num)
    } else {
      which(slides$title == key & !nzchar(slides$notes))
    }
    if (length(hit) == 0) {
      lc_abort("settings", paste0("video: silent: ", key, " matches no slide without notes."), file = deck,
               fix = "Use the slide number shown by lecture_script(), or the exact title.")
    }
    secs[hit] <- val
  }
  secs
}

# Notes for a slide with fragments: parts separated by a line holding only
# "---" or "|", one more part than there are fragment steps. If the notes
# have no separators, the whole text plays with every fragment shown.
lc_split_fragment_notes <- function(s, deck) {
  paras <- strsplit(s$notes, "\n\n", fixed = TRUE)[[1]]
  sep <- paras %in% c("---", "|", "\u2014", "\u2013")
  if (!any(sep)) return(s$notes)
  groups <- cumsum(sep)[!sep]
  parts <- vapply(split(paras[!sep], groups), paste, "", collapse = "\n\n")
  parts <- unname(parts)
  want <- s$n_fragments + 1L
  if (length(parts) != want) {
    lc_abort("script", sprintf("Slide %d (%s) has %d fragment steps, so its notes need %d parts, but they have %d.",
                               s$index, lc_title(s), s$n_fragments, want, length(parts)),
             file = deck, fix = "Separate the notes with a line holding only --- before each fragment's narration.")
  }
  parts
}

#' Show the narration script for a deck
#'
#' Reads the rendered deck in headless Chrome and returns one row per slide
#' with its speaker notes, as they will be voiced. Use it to review every word
#' before building.
#'
#' @param deck Path to the deck's `.qmd`, or to its rendered reveal.js `.html`.
#' @return A data frame with columns `index`, `title`, `notes`, `n_fragments`
#'   and `silent`.
#' @export
lecture_script <- function(deck) {
  deck <- lc_check_deck(deck)
  b <- lc_open_deck(deck, 1280L, 720L)
  on.exit(try(b$close(), silent = TRUE), add = TRUE)
  slides <- lc_read_slides(b, deck)
  slides[, c("index", "title", "notes", "n_fragments", "silent")]
}

# The rendered deck to read. A .html path is used as given. A .qmd path is
# mapped to its render: the nearest _quarto.yml above it sets the project
# root and project: output-dir:, so <root>/<dir>/<deck>.qmd renders to
# <root>/<output-dir>/<dir>/<deck>.html, or beside the .qmd with no
# output-dir. lecturecast never renders; a missing or stale render stops.
lc_check_deck <- function(deck) {
  step <- "open deck"
  if (!is.character(deck) || length(deck) != 1 || !file.exists(deck)) {
    lc_abort(step, "Deck file not found.", file = as.character(deck)[1])
  }
  if (grepl("\\.qmd$", deck, ignore.case = TRUE)) return(lc_rendered_deck(deck))
  if (!grepl("\\.html?$", deck, ignore.case = TRUE)) {
    lc_abort(step, "lecturecast needs a deck's .qmd or its rendered .html.", file = deck)
  }
  normalizePath(deck)
}

lc_rendered_deck <- function(qmd) {
  step <- "open deck"
  qmd <- normalizePath(qmd)
  root <- lc_quarto_root(dirname(qmd))
  name <- paste0(tools::file_path_sans_ext(basename(qmd)), ".html")
  out <- NULL
  if (!is.null(root)) {
    proj <- tryCatch(yaml::read_yaml(file.path(root, "_quarto.yml")),
                     error = function(e) lc_abort(step, paste0("_quarto.yml is not valid YAML: ", conditionMessage(e)),
                                                  file = file.path(root, "_quarto.yml")))
    out <- proj$project$`output-dir`
  }
  html <- if (is.null(out)) {
    file.path(dirname(qmd), name)
  } else {
    rel <- substring(dirname(qmd), nchar(root) + 2)
    base <- if (grepl("^(/|~|[A-Za-z]:)", out)) path.expand(out) else file.path(root, out)
    if (nzchar(rel)) file.path(base, rel, name) else file.path(base, name)
  }
  if (!file.exists(html)) {
    fix <- "Render it first with quarto render."
    rel <- if (is.null(root)) "" else substring(dirname(qmd), nchar(root) + 2)
    if (!is.null(root) && !is.null(proj$project$render) && nzchar(rel)) {
      top <- strsplit(rel, "/", fixed = TRUE)[[1]][1]
      fix <- sprintf("Render it first with quarto render. The project renders only the files listed under project: render: in _quarto.yml, so add \"%s/**/*.qmd\" there if the deck is not covered.", top)
    }
    lc_abort(step, "The deck has not been rendered.", file = html, fix = fix)
  }
  if (file.mtime(html) < file.mtime(qmd)) {
    lc_abort(step, "The rendered deck is older than its .qmd, so it would not match the notes you edited.",
             file = html, fix = paste0("Render it again: quarto render ", qmd))
  }
  normalizePath(html)
}

# The nearest folder at or above `dir` holding _quarto.yml.
lc_quarto_root <- function(dir) {
  repeat {
    if (file.exists(file.path(dir, "_quarto.yml"))) return(dir)
    parent <- dirname(dir)
    if (identical(parent, dir)) return(NULL)
    dir <- parent
  }
}
