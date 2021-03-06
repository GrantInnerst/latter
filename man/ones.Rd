% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/ones.R
\name{ones}
\alias{ones}
\title{Make an array of ones}
\usage{
ones(...)
}
\arguments{
\item{...}{A sequence of dimensions separated by commas}
}
\value{
An integer array of ones
}
\description{
Make an array of ones
}
\examples{

ones(5)
ones(5,1)
ones(1,5)
ones(2, 3)
ones(2, 3, 2)

str(ones(5))

}
