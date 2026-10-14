# Title and end cards: plain pages drawn by the same headless Chrome, so
# they match the slides' size exactly.

lc_capture_cards <- function(b, cfg, title, work, wh, deck) {
  out <- list()
  specs <- list(title = cfg$video$title_card, end = cfg$video$end_card)
  defaults <- list(title = list(title = title, subtitle = ""),
                   end = list(title = title, subtitle = "End of lecture"))
  for (k in names(specs)) {
    spec <- specs[[k]]
    if (is.null(spec)) next
    spec <- utils::modifyList(defaults[[k]], spec)
    html <- file.path(work, paste0(k, "-card.html"))
    png <- file.path(work, "png", paste0(k, "-card.png"))
    writeLines(enc2utf8(lc_card_html(spec, cfg)), html, useBytes = TRUE)
    tryCatch(b$Page$navigate(lc_file_url(html), wait_ = FALSE),
             error = function(e) lc_abort("cards", paste0("Chrome could not open the card: ", conditionMessage(e)), file = html))
    lc_wait_js(b, "document.readyState === 'complete' && document.fonts.status === 'loaded' && !!document.getElementById('lc-card')",
               step = "cards", file = html, timeout = 30, problem = "The card page did not finish loading.")
    lc_screenshot(b, png, wh[1], wh[2], html)
    out[[k]] <- png
  }
  out
}

lc_html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

lc_card_html <- function(spec, cfg) {
  sub <- if (nzchar(spec$subtitle %||% "")) sprintf("<p>%s</p>", lc_html_escape(spec$subtitle)) else ""
  sprintf('<!doctype html>
<html><head><meta charset="utf-8"><style>
html, body { margin: 0; height: 100%%; background: %s; color: %s; }
body { display: flex; align-items: center; justify-content: center; text-align: center;
       font-family: "Helvetica Neue", Arial, sans-serif; }
#lc-card { max-width: 80vw; }
h1 { font-size: 6vw; margin: 0 0 3vh 0; line-height: 1.1; }
p { font-size: 2.6vw; margin: 0; opacity: 0.8; }
</style></head>
<body><div id="lc-card"><h1>%s</h1>%s</div></body></html>',
          cfg$video$card_background, cfg$video$card_color, lc_html_escape(spec$title %||% ""), sub)
}
