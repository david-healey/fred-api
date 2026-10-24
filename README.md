# fred-api

An R function for downloading economic data from the
[FRED API](https://fred.stlouisfed.org/docs/api/fred/) (Federal Reserve Bank of
St. Louis) into a tidy, wide `data.table`: one date column and one numeric
column per series.

## Features

- Download one or many series in a single call, joined on date
- Optional date range, units transformation, frequency aggregation, and
  real-time / vintage queries for revised data
- Arguments validated up front, with clear error messages
- FRED's own error message shown when a request fails (e.g. a bad series ID)
- Requests throttled under FRED's rate limit and retried on transient failures
- Dates returned as `Date`, values as numeric (FRED's `"."` becomes `NA`)

## Setup

1. **Get a free API key** at
   <https://fred.stlouisfed.org/docs/api/api_key.html>.

2. **Store the key in `.Renviron`**, never in code. In the project folder
   (or your home folder), add this line to a file named `.Renviron`:

   ```
   FRED_API_KEY=your_key_here
   ```

   Make sure `.Renviron` is listed in `.gitignore`, then restart R. Check it
   loaded with:

   ```r
   nchar(Sys.getenv("FRED_API_KEY"))  # should be 32
   ```

3. **Install the required packages:**

   ```r
   install.packages(c("httr2", "jsonlite", "data.table", "cli"))
   ```

## Usage

```r
source("R/fred.R")

# One series
x <- downloadFredData("UNRATE", startDate = "2024-01-01", endDate = "2024-12-31")
x$data

# Several series, joined on date
y <- downloadFredData(c("UNRATE", "PAYEMS"), startDate = "2020-01-01")
y$data

# Quarterly averages of a monthly series
z <- downloadFredData("UNRATE", frequency = "q", agg_method = "avg")

# The data as it looked on specific past dates
v <- downloadFredData("GDP", vintages = c("2024-01-01", "2025-01-01"))
```

## Arguments

| Argument | Description |
|---|---|
| `mnemonics` | Character vector of FRED series IDs, e.g. `c("UNRATE", "GDP")` |
| `startDate`, `endDate` | Observation period, `"YYYY-MM-DD"`. Defaults: `"2000-01-01"` to today |
| `realtimeStart`, `realtimeEnd` | Optional real-time period for revised data |
| `vintages` | Optional vector of vintage dates: data as it existed on those days |
| `transformation` | Optional units code: `lin`, `chg`, `ch1`, `pch`, `pc1`, `pca`, `cch`, `cca`, `log` |
| `frequency` | Optional code to aggregate to a lower frequency, e.g. `m`, `q`, `a` |
| `agg_method` | Aggregation used with `frequency`: `avg`, `sum` or `eop` |
| `api_key` | Defaults to `Sys.getenv("FRED_API_KEY")` |

See the function's roxygen header in `R/fred.R` for full details, and the
[FRED docs](https://fred.stlouisfed.org/docs/api/fred/series_observations.html)
for the meaning of each code.

## Output

A list with two `data.table`s:

- **`data`**: `date` (class `Date`), `realtime_start`, `realtime_end`, and one
  numeric column per series, named by its ID. Series are full-outer-joined, so
  dates that appear in any series are kept, with `NA` where a series has no
  value.
- **`metadata`**: request details returned by FRED for each series.

## Notes

- If any series fails, the whole call stops with an error.
- When mixing frequencies (e.g. daily and quarterly), expect many `NA`s.
  Passing `frequency` puts all series on a common frequency.
- Real-time and vintage queries can return several versions of the same date,
  so the output may have more than one row per date.

## Roadmap

- Series metadata (title, units, frequency) from the `fred/series` endpoint
- Option to return successful series with a warning when some fail
