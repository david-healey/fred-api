#' Download observations for one or more FRED series
#'
#' Fetches observations from the FRED API (`fred/series/observations`) for each
#' requested series and joins them into a single wide data.table, with one
#' numeric column per series. Arguments are validated before any request is
#' sent. Requests are throttled to stay under FRED's rate limit and retried on
#' transient failures.
#'
#' @param mnemonics Character vector of FRED series IDs, e.g.
#'   `c("UNRATE", "GDP")`.
#' @param startDate Start of the observation period, as `"YYYY-MM-DD"`.
#'   Defaults to `"2000-01-01"`.
#' @param endDate End of the observation period, as `"YYYY-MM-DD"` or a `Date`.
#'   Defaults to today.
#' @param realtimeStart,realtimeEnd Optional start and end of the real-time
#'   period, as `"YYYY-MM-DD"`. Use these to retrieve historical (revised)
#'   versions of the data. If omitted, FRED returns the latest values.
#' @param transformation Optional units transformation code. One of `"lin"`
#'   (levels, the FRED default), `"chg"`, `"ch1"`, `"pch"`, `"pc1"`, `"pca"`,
#'   `"cch"`, `"cca"` or `"log"`.
#' @param frequency Optional frequency code for aggregating to a lower
#'   frequency, e.g. `"m"`, `"q"`, `"a"`. See the FRED docs for the full list.
#' @param agg_method Optional aggregation method used with `frequency`. One of
#'   `"avg"`, `"sum"` or `"eop"` (end of period).
#' @param vintages Optional character vector of vintage dates, as
#'   `"YYYY-MM-DD"`. Returns the data as it existed on each of those dates.
#' @param api_key FRED API key. Defaults to the `FRED_API_KEY` environment
#'   variable.
#' @param return_metadata Whether to return metadata table. Defaults to false
#'
#' @return A data.table (data) or list with two elements:
#'   \describe{
#'     \item{`data`}{A data.table with columns `date` (class `Date`),
#'       `realtime_start`, `realtime_end`, and one numeric column per series,
#'       named by its ID. Missing values (`"."` in FRED) are `NA`. Series are
#'       full-outer-joined, so dates present in any series are kept.}
#'     \item{`metadata`}{A data.table of the request details FRED returned for
#'       each series, with one column per series.}
#'   }
#'
#' @examples
#' \dontrun{
#' x <- downloadFredData("UNRATE", "2024-01-01", "2024-12-31")
#' x
#'
#' y <- downloadFredData(c("UNRATE", "PAYEMS"), startDate = "2020-01-01")
#' }
downloadFredData <- function(mnemonics, startDate = "2000-01-01", endDate = Sys.Date(), realtimeStart = NULL, realtimeEnd = NULL, transformation = NULL, frequency = NULL, agg_method = NULL, vintages = NULL, api_key = Sys.getenv("FRED_API_KEY"), return_metadata = FALSE){

  # Helper function to check arguments for validity
  arg_check <- function(name, arg){
    switch(name,
    "series_id" = {
      if(is.null(arg)){cli::cli_abort("Mnemonic(s) missing!")}
    },
    "realtime_start" = {
      if(!(grepl("^\\d{4}-\\d{2}-\\d{2}$", arg) & !is.na(as.Date(arg, format = "%Y-%m-%d"))) | length(arg) != 1){
        cli::cli_abort("Improper date format in vintageStart!")
      }
    },
    "realtime_end" = {
      if(!(grepl("^\\d{4}-\\d{2}-\\d{2}$", arg) & !is.na(as.Date(arg, format = "%Y-%m-%d"))) | length(arg) != 1){
        cli::cli_abort("Improper date format in vintageEnd!")
      }
    },
    "observation_start" = {
      if(!(grepl("^\\d{4}-\\d{2}-\\d{2}$", arg) & !is.na(as.Date(arg, format = "%Y-%m-%d"))) | length(arg) != 1){
        cli::cli_abort("Improper date format in startDate!")
      }
    },
    "observation_end" = {
      if(!(grepl("^\\d{4}-\\d{2}-\\d{2}$", arg) & !is.na(as.Date(arg, format = "%Y-%m-%d"))) | length(arg) != 1){
        cli::cli_abort("Improper date format in endDate!")
      }
    },
    "vintage_dates" = {
      if(any(!(grepl("^\\d{4}-\\d{2}-\\d{2}$", arg) & !is.na(as.Date(arg, format = "%Y-%m-%d"))))){
        cli::cli_abort("Improper date format in vintages!")
      }
    },
    "frequency" = {
      if(!(arg %in% c('d', 'w', 'bw', 'm', 'q', 'sa', 'a', 'wef', 'weth', 'wew', 'wetu', 'wem', 'wesu', 'wesa', 'bwew', 'bwem')) | length(arg) != 1){
        cli::cli_abort("Improper frequency code!")
      }
    },
    "units" = {
      if(!(arg %in% c('lin', 'chg', 'ch1', 'pch', 'pc1', 'pca', 'cch', 'cca', 'log')) | length(arg) != 1){
        cli::cli_abort("Improper transformation code!")
      }
    },
    "aggregation_method" = {
      if(!(arg %in% c('avg', 'sum', 'eop')) | length(arg) != 1){
        cli::cli_abort("Improper aggregation method!")
      }
    },
    "api_key" = {
      if(nchar(arg) != 32 | length(arg) != 1){
        cli::cli_abort("Improper API key!")
      }
    }
    )
  }

  coreDownload <- function(mnemonic){
    # List of all arguments
    arguments <- list(
      series_id = mnemonic,
      realtime_start = realtimeStart,
      realtime_end = realtimeEnd,
      observation_start = startDate,
      observation_end = endDate,
      units = transformation,
      frequency = frequency,
      aggregation_method = agg_method,
      vintage_dates = vintages,
      api_key = api_key,
      file_type = "json"
    )

    # Delete null/missing arguments
    arguments <- arguments[unlist(lapply(arguments, function(x) !is.null(x)))]

    # Check all arguments
    invisible(mapply(arg_check, name = names(arguments), arg = arguments))
    
    # Construct url
    req <- httr2::request("https://api.stlouisfed.org/fred/series/observations") |> 
      httr2::req_url_query(!!!arguments, .multi = "comma") |> 
      httr2::req_throttle(capacity = 108, fill_time_s = 60) |> # 10% off to give margin
      httr2::req_retry(max_tries = 10, retry_on_failure = TRUE) |> 
      httr2::req_error(body = function(x) httr2::resp_body_json(x)$error_message)

    # Parse response
    response <- httr2::resp_body_json(httr2::req_perform(req))

    # Isolate and organize metadata
    metadata <- data.table::as.data.table(rbind(unlist(response[1:12])))
    metadata <- data.table::melt.data.table(metadata, measure.vars = names(metadata))
    data.table::setnames(metadata, "value", mnemonic)

    # Isolate, organize, and coerce data
    data <- data.table::as.data.table(data.table::rbindlist(response$observations))
    data[, date := as.Date(date)]
    data[, value := suppressWarnings(as.numeric(value))]
    #data <- data[, c("date", "value")]
    data.table::setnames(data, "value", mnemonic)
  
    return(list("data" = data, "metadata" = metadata))
  }
  
  # Download
  downloaded_data <- lapply(mnemonics, coreDownload)

  # Split datasets
  datasets <- lapply(downloaded_data, function(x) x[["data"]])
  metadatasets <- lapply(downloaded_data, function(x) x[["metadata"]])

  # Collapse
  data <- Reduce(function(x, y) data.table::merge.data.table(x, y, by = c("date", "realtime_start", "realtime_end"), all = T), datasets)
  metadata <- Reduce(data.table::merge.data.table, metadatasets)

  # Return
  if(return_metadata == T){
    return(list("data" = data, "metadata" = metadata))
  } else{
    return(data)
  }
}

