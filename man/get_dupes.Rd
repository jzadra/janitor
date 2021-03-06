% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/get_dupes.R
\name{get_dupes}
\alias{get_dupes}
\title{Get rows of a \code{data.frame} with identical values for the specified variables.}
\usage{
get_dupes(dat, ...)
}
\arguments{
\item{dat}{The input data.frame.}

\item{...}{Unquoted variable names to search for duplicates. This takes a tidyselect specification.}
}
\value{
Returns a data.frame (actually a \code{tbl_df}) with the full records where the specified variables have duplicated values, as well as a variable \code{dupe_count} showing the number of rows sharing that combination of duplicated values.
}
\description{
For hunting duplicate records during data cleaning.  Specify the data.frame and the variable combination to search for duplicates and get back the duplicated rows.
}
\examples{
get_dupes(mtcars, mpg, hp)
# or called with the magrittr pipe \%>\% :
mtcars \%>\% get_dupes(wt)
# or using tidyselect:
mtcars \%>\% get_dupes(weight = wt, starts_with("cy"))

}
