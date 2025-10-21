# Brazil Central Bank Monetary Policy Minutes Sentiment Analysis (R)

This repo analyzes the **monetary policy meeting minutes** published by the **Central Bank of Brazil** to quantify tone and relate it to the **Selic** policy rate. Minutes are produced by the Bank’s **Monetary Policy Committee (COPOM)**   the group that decides Brazil’s interest rate.

## What it does (in plain English)

* Downloads recent **official minutes (PDFs)** from the Central Bank of Brazil
* Extracts text and **scores sentiment** with the **Loughran–McDonald** financial lexicon
* Computes **net sentiment** (positive − negative) and links it to the **Selic** (time series, scatter, correlation)
* Produces a simple **word cloud** and bar charts by sentiment category

## Why this is useful

A quick way to track how the **policy tone** in Brazil’s central‑bank communications evolves and how it relates to **interest‑rate decisions**.

## Requirements

* R ≥ 4.2
* Packages: `pdftools`, `dplyr`, `tidytext`, `textdata`, `ggplot2`, `lubridate`, `httr`, `jsonlite`, `tidyr`, `wordcloud`, `RColorBrewer`, `stringr`
* Poppler for `pdftools`

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

## Outputs

* In‑memory: `analysis_data` (with date, Selic, and sentiment counts), `sentiment_long`
* To save plots:

```r
ggsave("fig1.png", width = 10, height = 6, dpi = 300)
```

## Notes / limitations

* The **Loughran–McDonald** lexicon is **English**; results depend on minutes language
* **Selic** extraction relies on regex and may fail if wording changes
* Word cloud is illustrative only

## License

MIT (suggested). Monetary policy minutes © Central Bank of Brazil (see site terms).
