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

# One row per issue in a set of slides from lc_read_slides().
lc_lint_slides <- function(slides, max_words = 30) {
  rows <- list()
  add <- function(s, issue, found, sentence, advice) {
    rows[[length(rows) + 1]] <<- data.frame(slide = s$index, title = lc_title(s), issue = issue,
                                            found = found, sentence = sentence, advice = advice,
                                            stringsAsFactors = FALSE)
  }
  for (i in seq_len(nrow(slides))) {
    s <- slides[i, ]
    if (!nzchar(s$notes)) next
    text <- gsub("\n\\s*(---|\\|)\\s*\n", "\n\n", paste0("\n", s$notes, "\n"))
    for (sent in lc_sentences(text)) {
      for (issue in names(lc_lint_rules)) {
        r <- lc_lint_rules[[issue]]
        m <- regmatches(sent, gregexpr(r$pattern, sent, perl = TRUE))[[1]]
        if (length(m)) add(s, issue, paste(unique(m), collapse = " "), sent, r$advice)
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
#' addresses, phrases written for the live room ("the room can see",
#' "click"), and long sentences. Nothing is changed; edit the notes in the
#' deck's source and render it again. See
#' `vignette("narration", package = "lecturecast")` for the reasoning.
#'
#' @param deck Path to the rendered reveal.js HTML file.
#' @param max_words Sentences longer than this many words are reported.
#' @param quiet If `TRUE`, print nothing.
#' @return Invisibly, a data frame with one row per issue and columns `slide`,
#'   `title`, `issue`, `found`, `sentence` and `advice`.
#' @export
lint_notes <- function(deck, max_words = 30, quiet = FALSE) {
  lc_check_deck(deck)
  if (!is.numeric(max_words) || length(max_words) != 1 || is.na(max_words) || max_words < 1) {
    lc_abort("lint notes", "max_words must be a positive number.")
  }
  b <- lc_open_deck(deck, 1280L, 720L)
  on.exit(try(b$close(), silent = TRUE), add = TRUE)
  out <- lc_lint_slides(lc_read_slides(b, deck), max_words)
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
