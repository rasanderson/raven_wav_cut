#' Cut WAV files into selections based on Raven selection tables
#'
#' Reads all WAV files from `wav_dir`, finds a matching Raven selection table
#' (a tab-delimited `.txt` file with the same base name) in `sel_dir`, and
#' writes each selection as a separate WAV file to `out_dir`.
#'
#' Output files are named `<base>_01.wav`, `<base>_02.wav`, ... where
#' `<base>` is the original WAV file name without its extension and the
#' numeric suffix is zero-padded to at least two digits (more digits are
#' used automatically when a file contains 100 or more selections).
#'
#' Raven selection tables must be tab-delimited text files containing at
#' least the columns **"Begin Time (s)"** and **"End Time (s)"**.  When R
#' reads the header, spaces and parentheses are converted to dots, so the
#' function accepts both the original Raven column names and their
#' dot-converted equivalents.
#'
#' @param wav_dir  Path to the directory containing source WAV files.
#' @param sel_dir  Path to the directory containing Raven selection-table TXT
#'   files.  Each TXT file must share its base name with a WAV file in
#'   `wav_dir`.
#' @param out_dir  Path to the directory where extracted WAV selections will
#'   be written.  Created recursively if it does not already exist.
#'
#' @return Invisibly returns a character vector of the output file paths that
#'   were successfully written.
#'
#' @examples
#' \dontrun{
#' raven_wav_cut(
#'   wav_dir = "path/to/wav_files",
#'   sel_dir = "path/to/selection_tables",
#'   out_dir = "path/to/output"
#' )
#' }
#'
#' @importFrom tuneR readWave writeWave extractWave
#' @importFrom tools file_path_sans_ext
#' @export
raven_wav_cut <- function(wav_dir, sel_dir, out_dir) {

  # ── Validate inputs ─────────────────────────────────────────────────────────
  if (!dir.exists(wav_dir)) {
    stop("WAV directory does not exist: ", wav_dir)
  }
  if (!dir.exists(sel_dir)) {
    stop("Selection table directory does not exist: ", sel_dir)
  }

  # ── Prepare output directory ─────────────────────────────────────────────────
  if (!dir.exists(out_dir)) {
    dir.create(out_dir, recursive = TRUE)
  }

  # ── Discover WAV files ───────────────────────────────────────────────────────
  wav_files <- list.files(wav_dir, pattern = "\\.wav$",
                          ignore.case = TRUE, full.names = TRUE)

  if (length(wav_files) == 0) {
    warning("No WAV files found in: ", wav_dir)
    return(invisible(character(0)))
  }

  output_files <- character(0)

  for (wav_file in wav_files) {

    wav_base <- tools::file_path_sans_ext(basename(wav_file))

    # ── Find matching selection table ──────────────────────────────────────────
    sel_file <- .find_sel_file(sel_dir, wav_base)
    if (is.null(sel_file)) {
      warning("No selection table found for '", wav_base, "' — skipping.")
      next
    }

    # ── Read selection table ───────────────────────────────────────────────────
    sel_table <- tryCatch(
      read.table(sel_file, header = TRUE, sep = "\t",
                 stringsAsFactors = FALSE, check.names = TRUE),
      error = function(e) {
        warning("Could not read selection table '", sel_file,
                "': ", conditionMessage(e), " — skipping.")
        NULL
      }
    )

    if (is.null(sel_table) || nrow(sel_table) == 0) {
      warning("Empty or unreadable selection table: '", sel_file, "' — skipping.")
      next
    }

    # ── Locate Begin/End Time columns ─────────────────────────────────────────
    begin_col <- grep("^Begin.Time", names(sel_table), value = TRUE)[1]
    end_col   <- grep("^End.Time",   names(sel_table), value = TRUE)[1]

    if (is.na(begin_col) || is.na(end_col)) {
      warning("Selection table '", sel_file,
              "' is missing 'Begin Time (s)' or 'End Time (s)' columns — skipping.")
      next
    }

    # ── Read source WAV ────────────────────────────────────────────────────────
    wav_data <- tryCatch(
      tuneR::readWave(wav_file),
      error = function(e) {
        warning("Could not read WAV file '", wav_file,
                "': ", conditionMessage(e), " — skipping.")
        NULL
      }
    )
    if (is.null(wav_data)) next

    # ── Extract and write each selection ──────────────────────────────────────
    n_sel    <- nrow(sel_table)
    n_digits <- max(2L, nchar(as.character(n_sel)))
    fmt      <- paste0("_%0", n_digits, "d")

    for (i in seq_len(n_sel)) {

      begin_s <- sel_table[[begin_col]][i]
      end_s   <- sel_table[[end_col]][i]

      if (!is.finite(begin_s) || !is.finite(end_s) || begin_s >= end_s) {
        warning("Selection ", i, " in '", sel_file,
                "' has invalid times (", begin_s, " – ", end_s, ") — skipping.")
        next
      }

      # Clamp to WAV duration
      sr         <- wav_data@samp.rate
      n_samples  <- length(wav_data@left)
      wav_dur_s  <- n_samples / sr

      begin_s <- max(0, begin_s)
      end_s   <- min(wav_dur_s, end_s)

      if (begin_s >= end_s) {
        warning("Selection ", i, " in '", sel_file,
                "' falls outside WAV duration — skipping.")
        next
      }

      # Convert to 1-based sample indices.
      # round(begin_s * sr) gives the number of samples before the selection
      # (0-based), so + 1L converts to tuneR's 1-based index.
      from_samp <- max(1L, as.integer(round(begin_s * sr)) + 1L)
      to_samp   <- min(n_samples, as.integer(round(end_s * sr)))

      if (from_samp > to_samp) {
        warning("Selection ", i, " in '", sel_file,
                "' yields zero samples — skipping.")
        next
      }

      selection <- tuneR::extractWave(wav_data,
                                      from     = from_samp,
                                      to       = to_samp,
                                      interact = FALSE)

      out_name <- paste0(wav_base, sprintf(fmt, i), ".wav")
      out_path <- file.path(out_dir, out_name)

      tuneR::writeWave(selection, out_path)

      message("Written: ", out_name)
      output_files <- c(output_files, out_path)
    }
  }

  invisible(output_files)
}


# ── Internal helpers ───────────────────────────────────────────────────────────

#' Find a Raven selection-table file for a given WAV base name
#'
#' Performs a case-insensitive search for `<wav_base>.txt` inside `sel_dir`.
#'
#' @param sel_dir  Directory to search.
#' @param wav_base Base name of the WAV file (no extension).
#'
#' @return Full path to the matching TXT file, or `NULL` if not found.
#' @keywords internal
.find_sel_file <- function(sel_dir, wav_base) {
  # Exact match first
  exact <- file.path(sel_dir, paste0(wav_base, ".txt"))
  if (file.exists(exact)) return(exact)

  # Case-insensitive fallback
  all_txt <- list.files(sel_dir, pattern = "\\.txt$",
                        ignore.case = TRUE, full.names = FALSE)
  bases   <- tools::file_path_sans_ext(all_txt)
  hit     <- which(tolower(bases) == tolower(wav_base))
  if (length(hit) == 0L) return(NULL)
  file.path(sel_dir, all_txt[hit[1L]])
}
