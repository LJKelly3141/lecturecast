# Notes that read badly aloud. The checks only report; nothing is edited,
# since the instructor approves every word that is voiced.

lc_lint_rules <- list(
  symbol = list(
    pattern = "(*UTF8)[%&=+<>#~\\x{00d7}\\x{00f7}\\x{2248}\\x{2260}\\x{2264}\\x{2265}\\x{2190}-\\x{21ff}\\x{2070}-\\x{209f}\\x{00b2}\\x{00b3}\\x{00b9}]|(?<=\\w)/(?=\\w)",
    advice = "Write the symbol as the words you would say (\"percent\", \"and\", \"equals\", \"A D one\")."
  ),
  abbreviation = list(
    pattern = "(?i)\\b(e\\.g|i\\.e|etc|vs|cf|approx|w/o?|aka)(\\.|\\b)",
    advice = "Say it in full: \"for example\", \"that is\", \"and so on\", \"versus\"."
  ),
  link = list(
    pattern = "(?i)\\bhttps?://|\\bwww\\.",
    advice = "A web address is hard to hear. Name the page and put the link on the slide or in the course site."
  ),
  room = list(
    pattern = "(?i)\\b(the room|in class|today in class|on the board|whiteboard|raise your hands?|your neighbou?r|the person next to you|pass (it|these) around|hand(ed)? out|click|clicking|press|tap)\\b",
    advice = "This was written for the live room. In the video nobody can click or talk to a neighbor, and the chart plays by itself."
  )
)

# Economics and statistics abbreviations a voice reads as a word or as
# letters, with what to say instead. Matched as capitalized here, whole
# words only, with an optional plural "s". Abbreviations people say as
# letters (GDP, CPI, Fed) are left alone.
lc_spoken_forms <- c(
  # Macroeconomics
  AD = "aggregate demand", AS = "aggregate supply",
  SRAS = "short-run aggregate supply", LRAS = "long-run aggregate supply",
  MPC = "marginal propensity to consume", MPS = "marginal propensity to save",
  MPI = "marginal propensity to import",
  NX = "net exports", NNP = "net national product",
  NAIRU = "the non-accelerating inflation rate of unemployment",
  FOMC = "the Federal Open Market Committee",
  # Microeconomics
  PPF = "production possibilities frontier", PPC = "production possibilities curve",
  MC = "marginal cost", MR = "marginal revenue", MB = "marginal benefit", MU = "marginal utility",
  TC = "total cost", TR = "total revenue", FC = "fixed cost", VC = "variable cost",
  ATC = "average total cost", AVC = "average variable cost", AFC = "average fixed cost",
  MPL = "marginal product of labor", MRP = "marginal revenue product",
  MRS = "marginal rate of substitution", DWL = "deadweight loss",
  # Statistics
  SD = "standard deviation", SE = "standard error", CI = "confidence interval",
  df = "degrees of freedom", OLS = "ordinary least squares",
  MLE = "maximum likelihood estimate", IID = "independent and identically distributed",
  CDF = "cumulative distribution function", SSE = "sum of squared errors",
  SSR = "sum of squared residuals", SST = "total sum of squares",
  MSE = "mean squared error", RMSE = "root mean squared error",
  ANOVA = "analysis of variance", H0 = "the null hypothesis", H1 = "the alternative hypothesis"
)

lc_spoken_pattern <- function() {
  keys <- names(lc_spoken_forms)[order(-nchar(names(lc_spoken_forms)))]
  paste0("(?<![\\w.])(", paste(keys, collapse = "|"), ")s?(?![\\w])")
}

# Where the picture changes in a slide's notes, as character positions in
# `text`: each fragment step (a --- line) and the first quote of each chart
# button label. Returns the positions, the button labels quoted and those
# never quoted.
lc_visual_changes <- function(text, buttons, n_fragments = 0L) {
  at <- integer(0)
  sep <- gregexpr("\n\\s*(---|\\|)\\s*\n", text, perl = TRUE)[[1]]
  kind <- character(0)
  if (n_fragments > 0 && sep[1] > 0) {
    at <- c(at, as.integer(sep))
    kind <- c(kind, rep("fragment", length(sep)))
  }
  labels <- if (is.null(buttons) || !is.data.frame(buttons)) character(0) else buttons$label
  keys <- lc_label_key(labels)
  quoted <- character(0)
  unknown <- character(0)
  tg <- gregexpr(lc_tag_regex, enc2utf8(text), perl = TRUE)[[1]]
  if (tg[1] > 0) {
    # Tags mark the changes exactly; quotes are then ordinary text.
    tl <- trimws(sub(lc_tag_regex, "\\1", regmatches(enc2utf8(text), list(tg))[[1]], perl = TRUE))
    at <- c(at, as.integer(tg))
    kind <- c(kind, rep("button", length(tg)))
    tk <- lc_label_key(tl)
    quoted <- unique(tk[tk %in% keys])
    unknown <- unique(tl[!tk %in% keys])
  } else if (length(keys)) {
    m <- gregexpr("(*UTF8)[\"\\x{201c}]([^\"\\x{201c}\\x{201d}]+)[\"\\x{201d}]", enc2utf8(text), perl = TRUE)[[1]]
    if (m[1] > 0) {
      ph <- regmatches(enc2utf8(text), list(m))[[1]]
      k <- lc_label_key(sub("^.", "", sub(".$", "", ph)))
      hit <- k %in% keys & !duplicated(k)
      at <- c(at, as.integer(m)[hit])
      kind <- c(kind, rep("button", sum(hit)))
      quoted <- unique(k[hit])
    }
  }
  # The first button of each menu shows the chart's starting state, which is
  # already on screen, so it need not be cued.
  playable <- if (length(labels)) buttons$button > 0 else logical(0)
  o <- order(at)
  list(at = at[o], kind = kind[o], uncued = unique(labels[playable & !keys %in% quoted]), unknown = unknown)
}

# Content words said at the end of one sentence and again at the start of
# the next. Words of four letters or more, apart from common function words
# and the slide title's own words (a slide about sticky wages may say
# "wages" often), are compared by a rough stem, so "course" and "courses"
# match.
lc_repeat_stop <- c(
  "about", "after", "again", "also", "back", "because", "been", "before", "being", "both", "come", "could",
  "does", "doing", "done", "down", "each", "even", "every", "first", "from", "going", "good", "have", "here",
  "into", "just", "know", "like", "look", "make", "many", "more", "most", "much", "must", "next", "only",
  "other", "over", "same", "says", "should", "show", "shows", "some", "still", "such", "take", "than", "that",
  "that's", "their", "them", "then", "there", "there's", "these", "they", "they're", "thing", "things", "this",
  "those", "through", "time", "under", "very", "want", "well", "were", "what", "what's", "when", "where",
  "which", "while", "will", "with", "would", "your", "you're", "you'll", "you've", "it's", "here's", "let's"
)

lc_stem <- function(w) {
  w <- sub("'s$", "", w)
  w <- sub("ies$", "y", w)
  w <- ifelse(grepl("ss$", w), w, sub("s$", "", w))
  w <- ifelse(nchar(w) >= 6, sub("(ing|ed)$", "", w), w)
  w
}

# Every word of a sentence, and which are content words (with their stems).
lc_words <- function(x) {
  x <- gsub("[\u2018\u2019]", "'", tolower(x))
  w <- regmatches(x, gregexpr("[a-z0-9]+('[a-z]+)?", x))[[1]]
  content <- nchar(w) >= 4 & !w %in% lc_repeat_stop & !grepl("^[0-9]", w)
  data.frame(word = w, stem = lc_stem(w), content = content, stringsAsFactors = FALSE)
}

lc_content_stems <- function(x) {
  w <- lc_words(x)
  stats::setNames(w$stem[w$content], w$word[w$content])
}

# A repeat the ear catches: the same content word close on both sides of the
# sentence break, fewer than `gap` words apart (as in "...this course. In this course").
lc_repeated_words <- function(prev, cur, title = "", gap = 5) {
  a <- lc_words(prev)
  b <- lc_words(cur)
  skip <- lc_content_stems(title)
  a$dist <- nrow(a) - seq_len(nrow(a))
  b$dist <- seq_len(nrow(b)) - 1
  hits <- character(0)
  for (k in which(b$content & !b$stem %in% skip)) {
    m <- which(a$content & a$stem == b$stem[k])
    if (length(m) && min(a$dist[m]) + b$dist[k] < gap) hits <- c(hits, b$word[k])
  }
  unique(hits)
}

# Number words come back in spoken numbers ("twenty-two point three to
# thirty-six point four"), so they never count as repeats in one sentence.
lc_number_words <- c(
  "zero", "three", "seven", "eight", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
  "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty",
  "ninety", "hundred", "thousand", "million", "billion", "trillion", "point", "percent", "half", "halves",
  "quarter", "third", "fourth", "fifth", "tenth", "minus", "times"
)

# A content word of five letters or more said twice in one sentence (as in
# "counts each bin, and draws the counts"), compared by stem. Quoted text,
# such as a button or book title, is left out.
lc_repeated_within <- function(sentence) {
  x <- gsub("\"[^\"]*\"|\u201c[^\u201d]*\u201d", " ", sentence)
  w <- lc_words(x)
  w <- w[w$content & nchar(sub("'s$", "", w$word)) >= 5 & !w$stem %in% lc_stem(lc_number_words), ]
  unique(w$word[duplicated(w$stem)])
}

# Stretches of narration with nothing changing on screen, one per gap
# between changes: words, the text that starts it, and which change it
# follows (0 for the start of the slide, k for the k-th change).
lc_still_stretches <- function(text, at) {
  cuts <- c(1L, at, nchar(text) + 1L)
  out <- lapply(seq_len(length(cuts) - 1), function(k) {
    piece <- substr(text, cuts[k], cuts[k + 1] - 1)
    piece <- gsub(lc_tag_regex, " ", piece, perl = TRUE)
    piece <- trimws(gsub("(^|\n)\\s*(---|\\|)\\s*(\n|$)", " ", piece, perl = TRUE))
    n <- if (nzchar(piece)) length(strsplit(piece, "\\s+")[[1]]) else 0
    data.frame(words = n, start = piece, after = k - 1L, stringsAsFactors = FALSE)
  })
  do.call(rbind, out)
}

# One row per issue in a set of slides from lc_read_slides(). `max_still` is
# the longest the picture may sit unchanged, in seconds, estimated at
# `words_per_second` (Edge voices speak at roughly 2.6).
lc_lint_slides <- function(slides, max_words = 30, max_still = 30, words_per_second = 2.6, repeat_gap = 5) {
  rows <- list()
  add <- function(s, issue, found, sentence, advice) {
    rows[[length(rows) + 1]] <<- data.frame(slide = s$index, title = lc_title(s), issue = issue,
                                            found = found, sentence = sentence, advice = advice,
                                            stringsAsFactors = FALSE)
  }
  for (i in seq_len(nrow(slides))) {
    s <- slides[i, ]
    buttons <- if ("buttons" %in% names(slides)) slides$buttons[[i]] else NULL
    if (!nzchar(s$notes)) {
      where <- if (s$index == 1) {
        "Give the title slide a short spoken intro: in the deck's YAML, add title-slide-attributes: with data-notes: \"...\"."
      } else {
        "Add ::: notes, even a one-sentence transition, so the video never sits silent."
      }
      add(s, "dead air", if (is.na(s$silent)) "no notes" else sprintf("silent %g s", s$silent), "",
          paste("Nothing is said while this slide shows.", where))
      next
    }
    raw <- paste0("\n", s$notes, "\n")
    ch <- lc_visual_changes(raw, buttons, s$n_fragments)
    if (length(ch$unknown)) {
      add(s, "unknown tag", paste(sprintf("[play: %s]", ch$unknown), collapse = " "), "",
          "No chart button on this slide has that label, so the build will stop. Use a label exactly as the button shows it.")
    }
    if (length(ch$uncued)) {
      add(s, "animation not cued", paste(sprintf("\"%s\"", ch$uncued), collapse = " "), "",
          "The chart has buttons the narration never plays. Put [play: label] in the notes at the moment each should play.")
    }
    st <- lc_still_stretches(raw, ch$at)
    st$secs <- st$words / words_per_second
    st$after_button <- st$after > 0 & ch$kind[pmax(st$after, 1)] == "button"
    for (k in which(st$after_button & st$secs > max_still)) {
      add(s, "static after animation", sprintf("about %d s unchanged", round(st$secs[k])), lc_sentences(st$start[k])[1],
          paste0("The narration walks through what the animation showed while the chart sits at its end. ",
                 "Give the chart a button for each step that jumps to that step's state, and put [play: label] where each step is discussed, ",
                 "so the whole plays first and then each step is shown again as it is explained."))
    }
    other <- st[!st$after_button, ]
    if (nrow(other) && max(other$secs) > max_still) {
      k <- which.max(other$secs)
      add(s, "static slide", sprintf("about %d s unchanged", round(other$secs[k])), lc_sentences(other$start[k])[1],
          paste0("Show, don't just tell. Reveal the points as they are spoken (fragments, with --- between their notes), ",
                 "play a chart step with a [play: label] tag, or split the slide."))
    }
    text <- gsub("\n\\s*(---|\\|)\\s*\n", "\n\n", gsub(lc_tag_regex, "", raw, perl = TRUE))
    # Repeats count within a fragment step; a new step is a new moment.
    steps <- strsplit(gsub(lc_tag_regex, "", raw, perl = TRUE), "\n\\s*(---|\\|)\\s*\n")[[1]]
    for (step_text in if (repeat_gap > 0) steps else character(0)) {
      st_sents <- lc_sentences(step_text)
      for (sent in st_sents) {
        rep_words <- lc_repeated_within(sent)
        if (length(rep_words)) {
          add(s, "repetition", paste(rep_words, collapse = " "), sent,
              "The listener hears this word twice in one sentence. Use a pronoun or a different word, or rephrase. A deliberate parallel can stay.")
        }
      }
      for (k in seq_along(st_sents)[-1]) {
        rep_words <- lc_repeated_words(st_sents[k - 1], st_sents[k], s$title, repeat_gap)
        if (length(rep_words)) {
          add(s, "repetition", paste(rep_words, collapse = " "), st_sents[k],
              "The listener hears this twice in a row. Drop the repeat, or use a pronoun or a different word.")
        }
      }
    }
    for (sent in lc_sentences(text)) {
      for (issue in names(lc_lint_rules)) {
        r <- lc_lint_rules[[issue]]
        m <- regmatches(sent, gregexpr(r$pattern, sent, perl = TRUE))[[1]]
        if (length(m)) add(s, issue, paste(unique(m), collapse = " "), sent, r$advice)
      }
      m <- regmatches(sent, gregexpr(lc_spoken_pattern(), sent, perl = TRUE))[[1]]
      if (length(m)) {
        keys <- unique(sub("s$", "", m))
        say <- paste(sprintf("%s as \"%s\"", keys, lc_spoken_forms[keys]), collapse = "; ")
        add(s, "acronym", paste(keys, collapse = " "), sent,
            paste0("The voice reads these as a word or as letters. Say ", say,
                   ". If one is inside a quoted button name, leave the quote as it is."))
      }
      n <- length(strsplit(trimws(sent), "\\s+")[[1]])
      if (n > max_words) {
        add(s, "long sentence", sprintf("%d words", n), sent,
            "Listeners cannot reread. Split it so each sentence carries one idea.")
      }
    }
  }
  if (length(rows) == 0) {
    return(data.frame(slide = integer(0), title = character(0), issue = character(0), found = character(0),
                      sentence = character(0), advice = character(0), stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

#' Find speaker notes that will read badly aloud
#'
#' Reads the rendered deck's speaker notes and reports what a listener will
#' stumble on: symbols and subscripts, abbreviations such as "e.g.", web
#' addresses, economics and statistics abbreviations such as "SRAS" (with
#' the words to say instead), phrases written for the live room ("the room
#' can see", "click"), long sentences, a content word repeated across a
#' sentence break ("...this course. In this course...") or within one
#' sentence ("counts each bin, and draws the counts"), and the pacing of the picture: slides
#' with no narration (dead air), chart buttons the notes never play,
#' stretches of narration over a slide that does not change, and narration
#' that walks through an animation's steps after it has finished playing. Nothing is changed; edit the notes in the
#' deck's source and render it again. See
#' `vignette("narration", package = "lecturecast")` for the reasoning.
#'
#' @param deck Path to the deck's `.qmd`, or to its rendered reveal.js `.html`.
#'   A `.qmd` is mapped to its render using the project's `_quarto.yml`;
#'   lecturecast never renders, so a missing or out-of-date render stops.
#' @param max_words Sentences longer than this many words are reported.
#' @param max_still Report a slide when its picture would sit unchanged for
#'   longer than this many seconds of narration, estimated from the word
#'   count. Fragment steps and cued chart buttons count as changes.
#' @param repeat_gap Report a content word said at the end of one sentence
#'   and again at the start of the next, fewer than this many words apart
#'   across the break ("...this course. In this course..."). Words in the
#'   slide's title are left out. A content word of five letters or more said
#'   twice in one sentence is reported too, apart from number words
#'   ("twenty", "point") and quoted text. `0` turns both checks off.
#' @param quiet If `TRUE`, print nothing.
#' @return Invisibly, a data frame with one row per issue and columns `slide`,
#'   `title`, `issue`, `found`, `sentence` and `advice`.
#' @export
lint_notes <- function(deck, max_words = 30, max_still = 30, repeat_gap = 5, quiet = FALSE) {
  deck <- lc_check_deck(deck)
  if (!is.numeric(max_words) || length(max_words) != 1 || is.na(max_words) || max_words < 1) {
    lc_abort("lint notes", "max_words must be a positive number.")
  }
  if (!is.numeric(max_still) || length(max_still) != 1 || is.na(max_still) || max_still <= 0) {
    lc_abort("lint notes", "max_still must be a positive number of seconds.")
  }
  if (!is.numeric(repeat_gap) || length(repeat_gap) != 1 || is.na(repeat_gap) || repeat_gap < 0) {
    lc_abort("lint notes", "repeat_gap must be a number of words (0 turns the check off).")
  }
  b <- lc_open_deck(deck, 1280L, 720L)
  on.exit(try(b$close(), silent = TRUE), add = TRUE)
  out <- lc_lint_slides(lc_read_slides(b, deck), max_words, max_still, repeat_gap = repeat_gap)
  if (!quiet) lc_print_lint(out)
  invisible(out)
}

lc_print_lint <- function(out) {
  if (nrow(out) == 0) {
    cli::cli_alert_success("No notes found that read badly aloud.")
    return(invisible())
  }
  for (sl in unique(out$slide)) {
    rows <- out[out$slide == sl, ]
    cli::cli_h3(lc_esc(sprintf("Slide %d: %s", sl, rows$title[1])))
    for (k in seq_len(nrow(rows))) {
      cli::cli_alert_warning(lc_esc(sprintf("%s (%s): %s", rows$issue[k], rows$found[k], rows$sentence[k])))
    }
  }
  counts <- table(out$issue)
  cli::cli_text("")
  cli::cli_text(lc_esc(sprintf("%d issue%s on %d slide%s: %s.", nrow(out), if (nrow(out) == 1) "" else "s",
                               length(unique(out$slide)), if (length(unique(out$slide)) == 1) "" else "s",
                               paste(sprintf("%s %d", names(counts), as.integer(counts)), collapse = ", "))))
  cli::cli_text("The advice column says what to change. Nothing was edited.")
  invisible()
}
