#' @title Generate a frequency table (1-, 2-, or 3-way).
#'
#' @description
#' A fully-featured alternative to \code{table()}.  Results are data.frames and can be formatted and enhanced with janitor's family of \code{adorn_} functions.
#'
#' Specify a data.frame and the one, two, or three unquoted column names you want to tabulate.  Three variables generates a list of 2-way tabyls, split by the third variable.
#'
#' Alternatively, you can tabulate a single variable that isn't in a data.frame by calling \code{tabyl} on a vector, e.g., \code{tabyl(mtcars$gear)}.
#'
#' @param dat a data.frame containing the variables you wish to count.  Or, a vector you want to tabulate.
#' @param var1 the column name of the first variable.
#' @param var2 (optional) the column name of the second variable (the rows in a 2-way tabulation).
#' @param var3 (optional) the column name of the third variable (the list in a 3-way tabulation).
#' @param show_na should counts of \code{NA} values be displayed?  In a one-way tabyl, the presence of \code{NA} values triggers an additional column showing valid percentages(calculated excluding \code{NA} values).
#' @param show_missing_levels should counts of missing levels of factors be displayed?  These will be rows and/or columns of zeroes.  Useful for keeping consistent output dimensions even when certain factor levels may not be present in the data.
#' @param ... the arguments to tabyl (here just for the sake of documentation compliance, as all arguments are listed with the vector- and data.frame-specific methods)
#' @return Returns a data.frame with frequencies and percentages of the tabulated variable(s).  A 3-way tabulation returns a list of data.frames.
#' @export
#' @examples
#'
#' tabyl(mtcars, cyl)
#' tabyl(mtcars, cyl, gear)
#' tabyl(mtcars, cyl, gear, am)
#'
#' # or using the %>% pipe
#' mtcars %>%
#'   tabyl(cyl, gear)
#'
#' # illustrating show_na functionality:
#' my_cars <- rbind(mtcars, rep(NA, 11))
#' my_cars %>% tabyl(cyl)
#' my_cars %>% tabyl(cyl, show_na = FALSE)
#'
#' # Calling on a single vector not in a data.frame:
#' val <- c("hi", "med", "med", "lo")
#' tabyl(val)


tabyl <- function(dat, ...) UseMethod("tabyl")


#' @inheritParams tabyl
#' @export
#' @rdname tabyl
# retain this method for calling tabyl() on plain vectors

tabyl.default <- function(dat, show_na = TRUE, show_missing_levels = TRUE, ...) {
  if (is.list(dat) && !"data.frame" %in% class(dat)) {
    stop("tabyl() is meant to be called on vectors and data.frames; convert non-data.frame lists to one of these types")
  }
  # catch and adjust input variable name.
  if (is.null(names(dat)) || is.vector(dat)) {
    var_name <- deparse(substitute(dat))
  } else {
    var_name <- names(dat)
  }


  # useful error message if input vector doesn't exist
  if (is.null(dat)) {
    stop(paste0("object ", var_name, " not found"))
  }
  # an odd variable name can be deparsed into a vector of length >1, rare but throws warning, see issue #87
  if (length(var_name) > 1) {
    var_name <- paste(var_name, collapse = "")
  }

  # calculate initial counts table
  # convert vector to a 1 col data.frame
  if (mode(dat) %in% c("logical", "numeric", "character", "list") && !is.matrix(dat)) {
    # to preserve factor properties when vec is passed in as a list from data.frame method:
    if (is.list(dat)) {
      dat <- dat[[1]]
    }
    dat_df <- data.frame(dat, stringsAsFactors = is.factor(dat))
    names(dat_df)[1] <- "dat"

    # suppress a dplyr-specific warning message related to NA values in factors
    # the suggestion to use forcats::fct_explicit_na is unnecessary and confusing
    # source: https://stackoverflow.com/a/16521046/4470365
    withCallingHandlers({
      result <- dat_df %>% dplyr::count(dat)
    }, warning = function(w) {
      if (endsWith(conditionMessage(w), "fct_explicit_na\`"))
        invokeRestart("muffleWarning")
    })

    if (is.factor(dat) && show_missing_levels) {
      expanded <- tidyr::expand(result, dat)
      result <- merge( # can't use left_join b/c NA matching changed in 0.6.0
        x = expanded,
        y = result,
        by = "dat",
        all.x = TRUE,
        all.y = TRUE
      )
      result <- dplyr::arrange(result, dat) # restore sorting by factor level
    }
  } else {
    stop("input must be a vector of type logical, numeric, character, list, or factor")
  }

  # calculate percent, move NA row to bottom
  result <- result %>%
    dplyr::mutate(percent = n / sum(n, na.rm = TRUE))

  # sort the NA row to the bottom, necessary to retain factor sorting
  result <- result[order(is.na(result$dat)), ]
  result$is_na <- NULL

  # replace all NA values with 0 - only applies to missing factor levels
  result <- tidyr::replace_na(result, replace = list(n = 0, percent = 0))

  ## NA handling:
  # if there are NA values & show_na = T, calculate valid % as a new column
  if (show_na && sum(is.na(result[[1]])) > 0) {
    valid_total <- sum(result$n[!is.na(result[[1]])], na.rm = TRUE)
    result$valid_percent <- result$n / valid_total
    result$valid_percent[is.na(result[[1]])] <- NA
  } else { # don't show NA values, which necessitates adjusting the %s
    result <- result %>%
      dplyr::filter(!is.na(.[1])) %>%
      dplyr::mutate(percent = n / sum(n, na.rm = TRUE)) # recalculate % without NAs
  }

  # reassign correct variable name
  names(result)[1] <- var_name

  # in case input var name was "n" or "percent", call helper function to set unique names
  result <- handle_if_special_names_used(result)

  data.frame(result, check.names = FALSE) %>%
    as_tabyl(axes = 1)
}


#' @inheritParams tabyl
#' @export
#' @rdname tabyl
# Main dispatching function to underlying functions depending on whether "..." contains 1, 2, or 3 variables
tabyl.data.frame <- function(dat, var1, var2, var3, show_na = TRUE, show_missing_levels = TRUE, ...) {
  if (missing(var1) && missing(var2) && missing(var3)) {
    stop("if calling on a data.frame, specify unquoted column names(s) to tabulate.  Did you mean to call tabyl() on a vector?")
  }
  if (dplyr::is_grouped_df(dat)) {
    dat <- dplyr::ungroup(dat)
  }

  if (missing(var2) && missing(var3) && !missing(var1)) {
    tabyl_1way(dat, rlang::enquo(var1), show_na = show_na, show_missing_levels = show_missing_levels)
  } else if (missing(var3) && !missing(var1) && !missing(var1)) {
    tabyl_2way(dat, rlang::enquo(var1), rlang::enquo(var2), show_na = show_na, show_missing_levels = show_missing_levels)
  } else if (!missing(var1) &&
    !missing(var2) &&
    !missing(var3)) {
    tabyl_3way(dat, rlang::enquo(var1), rlang::enquo(var2), rlang::enquo(var3), show_na = show_na, show_missing_levels = show_missing_levels)
  } else {
    stop("please specify var1 OR var1 & var2 OR var1 & var2 & var3")
  }
}

# a one-way frequency table; this was called "tabyl" in janitor <= 0.3.0
tabyl_1way <- function(dat, var1, show_na = TRUE, show_missing_levels = TRUE) {
  x <- dplyr::select(dat, !! var1)

  # gather up arguments, pass them to tabyl.default
  arguments <- list()
  arguments$dat <- x[1]
  arguments$show_na <- show_na
  arguments$show_missing_levels <- show_missing_levels

  do.call(tabyl.default,
    args = arguments
  )
}


# a two-way frequency table; this was called "crosstab" in janitor <= 0.3.0
tabyl_2way <- function(dat, var1, var2, show_na = TRUE, show_missing_levels = TRUE) {
  dat <- dplyr::select(dat, !! var1, !! var2)

  if (!show_na) {
    dat <- dat[!is.na(dat[[1]]) & !is.na(dat[[2]]), ]
  }
  if (nrow(dat) == 0) { # if passed a zero-length input, or an entirely NA input, return a zero-row data.frame
    message("No records to count so returning a zero-row tabyl")
    return(dat %>%
      dplyr::select(1) %>%
      dplyr::slice(0))
  }

  # Suppress unnecessary dplyr warning - see this same code above
  # in tabyl.default for more explanation
  withCallingHandlers({
    tabl <- dat %>%
      dplyr::count(!! var1, !! var2)
  }, warning = function(w) {
    if (endsWith(conditionMessage(w), "fct_explicit_na\`"))
      invokeRestart("muffleWarning")
  })

  # Optionally expand missing factor levels.
  if (show_missing_levels) {
    tabl <- tidyr::complete(tabl, !! var1, !! var2)
  }

  # replace NA with string NA_ in vec2 to avoid invalid col name after spreading
  # if this col is a factor, need to add that level to the factor
  if (is.factor(tabl[[2]])) {
    levels(tabl[[2]]) <- c(levels(tabl[[2]]), "NA_")
  }
  tabl[2][is.na(tabl[2])] <- "NA_"
  result <- tabl %>%
    tidyr::spread(!! var2, "n", fill = 0)

  if ("NA_" %in% names(result)) {
    # move NA_ column to end, from http://stackoverflow.com/a/18339562
    result <- result[c(setdiff(names(result), "NA_"), "NA_")]
  }

  result %>%
    data.frame(., check.names = FALSE) %>%
    as_tabyl(axes = 2, row_var_name = names(dat)[1], col_var_name = names(dat)[2])
}


# a list of two-way frequency tables, split into a list on a third variable
tabyl_3way <- function(dat, var1, var2, var3, show_na = TRUE, show_missing_levels = TRUE) {
  dat <- dplyr::select(dat, !! var1, !! var2, !! var3)
  
  # Keep factor levels for ordering the list at the end
  if(is.factor(dat[[3]])){
    third_levels_for_sorting <- levels(dat[[3]])
  }
  dat[[3]] <- as.character(dat[[3]]) # don't want empty factor levels in the result list - they would be empty data.frames

  # grab class of 1st variable to restore it later
  col1_class <- class(dat[[1]])
  col1_levels <- NULL
  if (col1_class %in% "factor") {
    col1_levels <- levels(dat[[1]])
  }

  # print NA level as its own data.frame, and make it appear last
  if (show_na && sum(is.na(dat[[3]])) > 0) {
    dat[[3]] <- factor(dat[[3]], levels = c(sort(unique(dat[[3]])), "NA_"))
    dat[[3]][is.na(dat[[3]])] <- "NA_"
    if(exists("third_levels_for_sorting")){
      third_levels_for_sorting <- c(third_levels_for_sorting, "NA_")
    }
  }

  if (!show_missing_levels) { # this shows missing factor levels, to make the crosstabs consistent across each data.frame in the list based on values of var3
    if (is.factor(dat[[1]])) {
      dat[[1]] <- as.character(dat[[1]])
    }
    if (is.factor(dat[[2]])) {
      dat[[2]] <- as.character(dat[[2]])
    }
  } else {
    dat[[1]] <- as.factor(dat[[1]])
    dat[[2]] <- as.factor(dat[[2]])
  }

  result <- split(dat, dat[[rlang::quo_name(var3)]]) %>%
    purrr::map(tabyl_2way, var1, var2, show_na = show_na, show_missing_levels = show_missing_levels) %>%
    purrr::map(reset_1st_col_status, col1_class, col1_levels) # reset class of var in 1st col to its input class, #168

  # reorder when var 3 is a factor, per #250
  if(exists("third_levels_for_sorting")){
    result <- result[order(third_levels_for_sorting[third_levels_for_sorting %in% unique(dat[[3]])])] 
  }
  
  result
}

### Helper functions called by tabyl() ------------

# function that checks if col 1 name is "n" or "percent",
## if so modifies the appropriate other column name to avoid duplicates
handle_if_special_names_used <- function(dat) {
  if (names(dat)[1] == "n") {
    names(dat)[2] <- "n_n"
  } else if (names(dat)[1] == "percent") {
    names(dat)[3] <- "percent_percent"
  }
  dat
}

# reset the 1st col's class of a data.frame to a provided class
# also reset in tabyl's core
reset_1st_col_status <- function(dat, new_class, lvls) {
  if (new_class %in% "factor") {
    dat[[1]] <- factor(dat[[1]], levels = lvls)
    attr(dat, "core")[[1]] <- factor(attr(dat, "core")[[1]], levels = lvls)
  } else {
    dat[[1]] <- as.character(dat[[1]]) # first do as.character in case eventual class is numeric
    class(dat[[1]]) <- new_class
    attr(dat, "core")[[1]] <- as.character(attr(dat, "core")[[1]])
    class(attr(dat, "core")[[1]]) <- new_class
  }
  dat
}
