#' Read lecturecast settings
#'
#' Looks for `lecturecast.yml` next to the deck, then in each parent folder up
#' to the course root (the first folder holding `_quarto.yml` or `.git`).
#' The ElevenLabs key is never read from this file; it comes only from the
#' `ELEVENLABS_API_KEY` environment variable.
#'
#' @param deck Path to the deck. Used to find the settings file.
#' @param config Path to a settings file. Overrides the search.
#' @return A list of settings with defaults filled in.
#' @export
lecturecast_config <- function(deck = NULL, config = NULL) {
  step <- "settings"
  path <- config %||% lc_find_config(deck)
  if (is.null(path)) {
    lc_abort(step, "No lecturecast.yml was found, so no voice is set.",
             fix = "Create lecturecast.yml next to the deck or at the course root, with voice: provider: and voice ids.")
  }
  if (!file.exists(path)) lc_abort(step, "Settings file does not exist.", file = path)
  raw <- tryCatch(yaml::read_yaml(path),
                  error = function(e) lc_abort(step, paste0("Settings file is not valid YAML: ", conditionMessage(e)), file = path))
  cfg <- lc_config_defaults(raw %||% list())
  cfg$path <- normalizePath(path)
  lc_config_validate(cfg, path)
  cfg
}

lc_find_config <- function(deck) {
  if (is.null(deck)) return(NULL)
  dir <- normalizePath(dirname(deck), mustWork = FALSE)
  repeat {
    f <- file.path(dir, "lecturecast.yml")
    if (file.exists(f)) return(f)
    if (file.exists(file.path(dir, "_quarto.yml")) || file.exists(file.path(dir, ".git"))) {
      return(NULL)
    }
    parent <- dirname(dir)
    if (identical(parent, dir)) return(NULL)
    dir <- parent
  }
}

lc_config_defaults <- function(raw) {
  voice <- raw$voice %||% list()
  video <- raw$video %||% list()
  podcast <- raw$podcast %||% list()
  list(
    voice = list(
      provider = voice$provider,
      narrator = voice$narrator,
      host_a = voice$host_a,
      host_b = voice$host_b,
      model = voice$model %||% "eleven_multilingual_v2",
      dialogue_model = voice$dialogue_model %||% "eleven_v3",
      settings = voice$settings,
      recorded_dir = voice$recorded_dir,
      edge_rate = voice$edge_rate
    ),
    video = list(
      resolution = video$resolution %||% "1080p",
      fps = video$fps %||% 30,
      title_card = isTRUE(video$title_card %||% FALSE),
      end_card = isTRUE(video$end_card %||% FALSE),
      crossfade = video$crossfade %||% 0.5,
      lead_in = video$lead_in %||% 0.4,
      tail = video$tail %||% 0.8,
      card_seconds = video$card_seconds %||% 4,
      silent = video$silent %||% list()
    ),
    podcast = list(
      gap = podcast$gap %||% 0.35
    )
  )
}

lc_config_validate <- function(cfg, path) {
  step <- "settings"
  providers <- c("elevenlabs", "edge", "recorded")
  p <- cfg$voice$provider
  if (is.null(p) || !p %in% providers) {
    lc_abort(step, paste0("voice: provider: must be one of ", paste(providers, collapse = ", "), "."),
             file = path, fix = "Set voice: provider: in lecturecast.yml.")
  }
  if (p == "recorded" && is.null(cfg$voice$recorded_dir)) {
    lc_abort(step, "provider is recorded but voice: recorded_dir: is not set.", file = path,
             fix = "Set voice: recorded_dir: to the folder holding your audio files.")
  }
  if (!cfg$video$resolution %in% names(lc_resolutions)) {
    lc_abort(step, paste0("video: resolution: must be one of ", paste(names(lc_resolutions), collapse = ", "), "."),
             file = path)
  }
  invisible(TRUE)
}

lc_resolutions <- list(
  "720p" = c(1280L, 720L),
  "1080p" = c(1920L, 1080L),
  "1440p" = c(2560L, 1440L),
  "2160p" = c(3840L, 2160L)
)

# The voice id for a role, or stop if it is not set.
lc_voice_id <- function(cfg, role) {
  id <- cfg$voice[[role]]
  if (cfg$voice$provider != "recorded" && (is.null(id) || !nzchar(id))) {
    lc_abort("settings", paste0("voice: ", role, ": is not set."), file = cfg$path,
             fix = paste0("Set voice: ", role, ": to a voice id for the ", cfg$voice$provider, " provider."))
  }
  id
}
