# COPOM Sentiment (R)

Minimal script to analyze **COPOM** minutes with the **Loughran–McDonald** lexicon. Fetches recent minutes (PDF), extracts text, computes per‑sentiment counts, and relates **net sentiment** (positive − negative) to the **Selic** rate.

## Requirements

* R ≥ 4.2
* Packages: `pdftools`, `dplyr`, `tidytext`, `textdata`, `ggplot2`, `lubridate`, `httr`, `jsonlite`, `tidyr`, `wordcloud`, `RColorBrewer`, `stringr`
* Poppler for `pdftools`
  macOS: `brew install poppler`
  Debian/Ubuntu: `sudo apt-get install libpoppler-cpp-dev`

### Install packages

```r
pkgs <- c("pdftools","dplyr","tidytext","textdata","ggplot2","lubridate",
          "httr","jsonlite","tidyr","wordcloud","RColorBrewer","stringr")
inst <- pkgs[!(pkgs %in% installed.packages()[, "Package"])]
if (length(inst)) install.packages(inst)
```

## Run

```bash
Rscript copom_sentiment.R
```

*Default: processes the 25 most recent minutes (edit `head(25)` to change).*

## What it does

* Pulls minutes metadata from the BCB API
* Downloads PDFs and extracts text (`pdftools`)
* Tokenizes text (`tidytext`), removes EN stopwords, joins `lexicon_loughran()`
* Computes sentiment counts and `net_sentiment`
* Extracts **Selic** via regex
* Produces `ggplot2` charts and `cor(net_sentiment, selic_rate)`

## Outputs

* In‑memory: `analysis_data`, `sentiment_long`
* To save plots:

```r
ggsave("fig1.png", width = 10, height = 6, dpi = 300)
```

## Notes

* Loughran–McDonald is **English**; results depend on minutes language
* Selic regex may fail if wording changes
* Wordcloud is illustrative

## License

MIT (suggested). COPOM minutes: Banco Central do Brasil (see site terms).

