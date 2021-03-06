% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/Logging.R
\name{registerLogger}
\alias{registerLogger}
\title{Register a logger}
\usage{
registerLogger(logger)
}
\arguments{
\item{logger}{An object of type \code{Logger} as created using the \code{\link{createLogger}}
function.}
}
\description{
Register a logger
}
\details{
Registers a logger as created using the \code{\link{createLogger}} function to the logging system.

Deprecated. This function has moved to ParallelLogger.
}
