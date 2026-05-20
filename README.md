# ravenwavcut

Cut WAV files into subsections based on Raven Pro selection tables.

## Overview

`ravenwavcut` is an R package that takes:

1. A folder of WAV recordings.
2. A folder of [Raven Pro](https://www.ravensoundsoftware.com/) selection tables
   (tab-delimited `.txt` files) whose file names share the same prefix as the
   corresponding WAV files.

It writes every selection as a separate WAV file into a third output folder.
Each output file is named after the source WAV with a zero-padded counter
appended, e.g.:

```
morning_chorus.wav  +  morning_chorus.txt  (3 selections)
  →  morning_chorus_01.wav
     morning_chorus_02.wav
     morning_chorus_03.wav
```

## Requirements

- R ≥ 4.0
- [tuneR](https://CRAN.R-project.org/package=tuneR) package

## Installation

```r
# install.packages("remotes")
remotes::install_github("rasanderson/raven_wav_cut")
```

## Usage

```r
library(ravenwavcut)

raven_wav_cut(
  wav_dir = "path/to/wav_files",        # folder containing .wav files
  sel_dir = "path/to/selection_tables", # folder containing Raven .txt tables
  out_dir = "path/to/output"            # folder for extracted selections
)
```

### Selection table format

The function expects standard Raven Pro selection tables exported as
tab-delimited text.  The only columns it needs are:

| Column | Description |
|--------|-------------|
| `Begin Time (s)` | Start of the selection in seconds |
| `End Time (s)` | End of the selection in seconds |

All other columns are ignored.

### Selection table naming

The function matches each WAV file to a selection table using the following
strategy (first match wins, all comparisons are case-insensitive):

1. **Exact name**: `<base>.txt`  (e.g. `morning_chorus.txt`)
2. **Base-name match**: any `.txt` file whose name without extension equals
   `<base>`
3. **Raven Pro prefix**: any `.txt` file whose name starts with `<base>.`
   — this covers Raven Pro's default export names such as
   `morning_chorus.Table 1 Selections 1.txt` and
   `morning_chorus.wav.Table 1 Selections 1.txt`

If a WAV file in `wav_dir` has no matching `.txt` file in `sel_dir`, it is
silently skipped with an informational message.  This is expected behaviour —
you do not need a selection table for every WAV file.

## Output naming

Output files follow the pattern `<source_base>_NN.wav` where `NN` is a
zero-padded integer (at least two digits, wider when a file has ≥ 100
selections).

## License

GPL (≥ 3)
