# Headless Chrome control for a rendered reveal.js deck: open it, read its
# slides and speaker notes, and capture each slide state.

lc_open_deck <- function(deck, width, height, timeout = 60) {
  step <- "open deck"
  if (!requireNamespace("chromote", quietly = TRUE)) {
    lc_abort(step, "The chromote package is not installed.", fix = "install.packages(\"chromote\")")
  }
  chrome <- lc_find_chrome()
  if (!nzchar(chrome)) {
    lc_abort(step, "Chrome was not found.", fix = "Install Google Chrome, or set the CHROMOTE_CHROME environment variable to its path.")
  }
  old <- options(chromote.timeout = timeout)
  on.exit(options(old), add = TRUE)
  b <- tryCatch(
    chromote::ChromoteSession$new(width = width, height = height),
    error = function(e) lc_abort(step, paste0("Chrome did not start: ", conditionMessage(e)), file = chrome)
  )
  url <- lc_file_url(deck)
  # Close Chrome if the deck never becomes ready, then pass the error on.
  tryCatch({
    tryCatch(b$Page$navigate(url, wait_ = FALSE),
             error = function(e) lc_abort(step, paste0("Chrome could not open the deck: ", conditionMessage(e)), file = deck))
    lc_wait_js(b, "typeof Reveal !== 'undefined' && Reveal.isReady && Reveal.isReady()",
               step = step, file = deck, timeout = timeout,
               problem = "The page loaded but reveal.js never reported ready.",
               fix = "Open the deck in a browser and check that it is a rendered reveal.js HTML file.")
  }, error = function(e) {
    try(b$close(), silent = TRUE)
    stop(e)
  })
  b
}

lc_file_url <- function(path) {
  parts <- strsplit(normalizePath(path), "/", fixed = TRUE)[[1]]
  paste0("file://", paste(vapply(parts, utils::URLencode, "", reserved = TRUE), collapse = "/"))
}

# Evaluate JavaScript and return its value. Promises are awaited. A lost
# connection to Chrome is a lecturecast_chrome_error; an exception in the
# page is a plain lecturecast_error.
lc_js <- function(b, js, step, file = NULL, timeout = 60) {
  r <- tryCatch(
    b$Runtime$evaluate(js, awaitPromise = TRUE, returnByValue = TRUE, timeout_ = timeout),
    error = function(e) lc_abort(step, paste0("Chrome did not answer: ", conditionMessage(e)), file = file,
                                 class = "lecturecast_chrome_error")
  )
  if (!is.null(r$exceptionDetails)) {
    detail <- r$exceptionDetails$exception$description %||% r$exceptionDetails$text
    lc_abort(step, paste0("JavaScript error in the deck: ", detail), file = file)
  }
  r$result$value
}

lc_wait_js <- function(b, condition, step, file, timeout, problem, fix = NULL) {
  deadline <- Sys.time() + timeout
  repeat {
    # A page exception (say, Reveal not defined yet) means not ready; a
    # lost connection to Chrome stops at once.
    ok <- tryCatch(isTRUE(lc_js(b, condition, step, file, timeout = 10)),
                   lecturecast_chrome_error = function(e) stop(e),
                   lecturecast_error = function(e) FALSE)
    if (ok) return(invisible(TRUE))
    if (Sys.time() > deadline) lc_abort(step, problem, file = file, fix = fix)
    Sys.sleep(0.25)
  }
}

# One row per slide: index (1-based, in deck order), h, v, title, notes text,
# fragment count, data-silent attribute.
lc_read_slides <- function(b, deck) {
  js <- "(() => {
    const toText = (html) => {
      const d = document.createElement('div');
      d.style.cssText = 'position:absolute;left:-99999px;top:0;width:800px;white-space:normal';
      d.innerHTML = html || '';
      d.querySelectorAll('style,script,.MJX_Assistive_MathML,mjx-assistive-mml').forEach(e => e.remove());
      // Pandoc turns a notes line of --- into <hr> and a lone | into an
      // empty line block. Both mark a fragment break.
      d.querySelectorAll('hr, div.line-block').forEach(e => {
        if (e.tagName === 'HR' || !e.textContent.trim()) {
          const p = document.createElement('p'); p.textContent = '---'; e.replaceWith(p);
        }
      });
      document.body.appendChild(d);
      const t = d.innerText;
      d.remove();
      return t;
    };
    return JSON.stringify(Reveal.getSlides().map((s, i) => {
      const ix = Reveal.getIndices(s);
      const head = s.querySelector('h1, h2, h3');
      return {
        index: i + 1, h: ix.h, v: ix.v === undefined ? 0 : ix.v,
        title: head ? head.textContent.trim() : '',
        // Quarto's title slide, and the divider a level-one heading makes.
        title_slide: s.id === 'title-slide',
        section: s.classList.contains('level1') && s.id !== 'title-slide',
        notes: toText(Reveal.getSlideNotes(s)),
        notes_html: Reveal.getSlideNotes(s) || '',
        fragments: Array.from(s.querySelectorAll('.fragment'))
          .map(f => f.hasAttribute('data-fragment-index') ? Number(f.getAttribute('data-fragment-index')) : null),
        silent: s.getAttribute('data-silent'),
        buttons: Array.from(s.querySelectorAll('.js-plotly-plot')).flatMap((gd, pi) =>
          ((gd.layout && gd.layout.updatemenus) || []).flatMap((m, mi) =>
            (m.buttons || []).map((bt, bi) => ({
              plot: pi, menu: mi, button: bi, label: String(bt.label || ''),
              method: bt.method || 'restyle'
            }))))
      };
    }));
  })()"
  x <- jsonlite::fromJSON(lc_js(b, js, "read slides", deck), simplifyVector = FALSE)
  if (length(x) == 0) lc_abort("read slides", "The deck has no slides.", file = deck)
  data.frame(
    index = vapply(x, function(s) s$index, integer(1)),
    h = vapply(x, function(s) s$h, integer(1)),
    v = vapply(x, function(s) s$v, integer(1)),
    title = vapply(x, function(s) s$title, character(1)),
    title_slide = vapply(x, function(s) isTRUE(s$title_slide), logical(1)),
    section = vapply(x, function(s) isTRUE(s$section), logical(1)),
    notes = vapply(x, function(s) lc_clean_notes(s$notes), character(1)),
    notes_html = vapply(x, function(s) s$notes_html, character(1)),
    n_fragments = vapply(x, function(s) lc_fragment_steps(s$fragments), integer(1)),
    silent = vapply(x, function(s) if (is.null(s$silent)) NA_real_ else suppressWarnings(as.numeric(s$silent)), numeric(1)),
    buttons = I(lapply(x, function(s) lc_buttons_df(s$buttons))),
    stringsAsFactors = FALSE
  )
}

lc_buttons_df <- function(b) {
  if (length(b) == 0) {
    return(data.frame(plot = integer(0), menu = integer(0), button = integer(0),
                      label = character(0), method = character(0), stringsAsFactors = FALSE))
  }
  data.frame(plot = vapply(b, function(x) as.integer(x$plot), 0L),
             menu = vapply(b, function(x) as.integer(x$menu), 0L),
             button = vapply(b, function(x) as.integer(x$button), 0L),
             label = vapply(b, function(x) x$label, ""),
             method = vapply(b, function(x) x$method, ""), stringsAsFactors = FALSE)
}

# Number of fragment steps on a slide. Fragments sharing an index reveal
# together; unindexed ones each take their own step after the indexed ones.
lc_fragment_steps <- function(idx) {
  if (length(idx) == 0) return(0L)
  given <- unlist(idx[!vapply(idx, is.null, logical(1))])
  as.integer(length(unique(given)) + sum(vapply(idx, is.null, logical(1))))
}

# Notes as narration: one paragraph per line, whitespace tidied.
lc_clean_notes <- function(x) {
  if (is.null(x) || !nzchar(trimws(x))) return("")
  lines <- trimws(gsub("[ \t\u00a0]+", " ", strsplit(x, "\n", fixed = TRUE)[[1]]))
  lines <- lines[nzchar(lines)]
  paste(lines, collapse = "\n\n")
}

lc_deck_title <- function(b, deck) {
  t <- lc_js(b, "document.title", "read slides", deck)
  if (is.null(t) || !nzchar(t)) tools::file_path_sans_ext(basename(deck)) else t
}

# Hide the on-screen controls and turn off transitions so each capture is
# the finished slide.
lc_prepare_capture <- function(b, deck) {
  js <- "(() => {
    Reveal.configure({controls: false, progress: false, slideNumber: false,
                      transition: 'none', backgroundTransition: 'none',
                      autoSlide: 0, help: false});
    const st = document.createElement('style');
    st.textContent = '.slide-menu-button, .reveal .controls, .reveal .progress, .slide-number, .slide-chalkboard-buttons, .quarto-toc-toggle { display: none !important; } * { cursor: none !important; }';
    document.head.appendChild(st);
    return true;
  })()"
  lc_js(b, js, "capture", deck)
  invisible(TRUE)
}

# Go to slide (h, v) at fragment step f (-1 = before any fragment) and wait
# until fonts, MathJax and every Plotly chart on it are drawn.
lc_goto <- function(b, h, v, f, deck, timeout = 30) {
  lc_js(b, sprintf("Reveal.slide(%d, %d, %d); true", h, v, f), "capture", deck)
  ready <- "(() => {
    const s = Reveal.getCurrentSlide();
    if (!s) return false;
    if (document.fonts && document.fonts.status !== 'loaded') return false;
    if (window.MathJax && MathJax.startup && MathJax.startup.promise && !window.__lcMath) {
      MathJax.startup.promise.then(() => { window.__lcMath = true; });
      return false;
    }
    const plots = s.querySelectorAll('.js-plotly-plot');
    for (const p of plots) {
      if (!p._fullLayout || p._transitioning || p._transitionData && p._transitionData._frameQueue && p._transitionData._frameQueue.length) return false;
      if (p.offsetWidth === 0) return false;
    }
    const widgets = s.querySelectorAll('.html-widget');
    for (const w of widgets) if (w.offsetWidth === 0) return false;
    return true;
  })()"
  lc_wait_js(b, ready, "capture", deck, timeout,
             problem = sprintf("Slide %d.%d did not finish drawing within %d seconds.", h, v, timeout),
             fix = "Open the slide in a browser and check that its charts and maths load.")
  # Two animation frames plus a short settle for charts that resize on show.
  lc_js(b, "new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(() => r(true), 400))))",
        "capture", deck)
  invisible(TRUE)
}

lc_screenshot <- function(b, file, width, height, deck) {
  step <- "capture"
  r <- tryCatch(
    b$Page$captureScreenshot(format = "png", captureBeyondViewport = FALSE, timeout_ = 60),
    error = function(e) lc_abort(step, paste0("Chrome could not take a screenshot: ", conditionMessage(e)), file = deck)
  )
  writeBin(jsonlite::base64_dec(r$data), file)
  wh <- lc_dimensions(file, step)
  if (!identical(wh, c(width, height))) {
    lc_abort(step, sprintf("Capture is %dx%d, expected %dx%d.", wh[1], wh[2], width, height), file = file)
  }
  invisible(file)
}
