#' Solve an integer progam with LattE
#'
#' \code{latte_max} and \code{latte_min} use LattE's
#' \code{latte-maximize} and \code{latte-minimize} functions to find
#' the maximum or minimum of a linear objective function over the
#' integers points in a polytope (i.e. satisfying linearity
#' constraints). This makes use of the digging algorithm; see the
#' LattE manual at \url{http://www.math.ucdavis.edu/~latte} for
#' details.
#'
#' @param objective A linear polynomial to pass to \code{\link{mp}},
#'   see examples
#' @param constraints A collection of linear polynomial
#'   (in)equalities that define the feasibility region, the integers
#'   in the polytope
#' @param method Method \code{"LP"} or \code{"cones"}
#' @param dir Directory to place the files in, without an ending /
#' @param opts Options; see the LattE manual at
#'   \url{http://www.math.ucdavis.edu/~latte}
#' @param quiet Show latte output
#' @param type \code{"max"} or \code{"min"}
#' @return A named list with components \code{par}, a named-vector
#'   of optimizing arguments, and \code{value}, the value of the
#'   objective function at the optimial point.
#' @name latte_optim
#' @examples
#'
#'
#' \dontrun{ requires LattE
#'
#' latte_max("-2 x + 3 y", c("x + y <= 10", "x >= 0", "y >= 0"))
#'
#' library("tidyverse")
#'
#'
#' tibble("x" = 0:10, "y" = 0:10) %>%
#'   cross_df() %>%
#'   filter(x + y <= 10L) %>%
#'   mutate(objective = -2*x + 3*y) %>%
#'   ggplot(aes(x, y, size = objective)) +
#'     geom_point()
#'
#' latte_min(
#'   "-2 x + 3 y",
#'   c("x + y <= 10", "x >= 0", "y >= 0"),
#'   method = "cones"
#' )
#'
#'
#'
#' latte_min("-2 x - 3 y - 4 z", c(
#'   "3 x + 2 y + z <= 10",
#'   "2 x + 5 y + 3 z <= 15",
#'   "x >= 0", "y >= 0", "z >= 0"
#' ), "cones", quiet = FALSE)
#'
#' tibble("x" = 0:10, "y" = 0:10, "z" = 0:10) %>%
#'   cross_df() %>%
#'   filter(
#'     3*x + 2*y + z <= 10,
#'     2*x + 5*y + 3*z <= 15
#'   ) %>%
#'   mutate(objective = -2*x - 3*y - 4*z) %>%
#'   arrange(objective)
#'
#'
#'
#'
#' }
#'
latte_optim <- function(objective, constraints, type = c("max", "min"),
  method = c("lp","cones"), dir = tempdir(),
  opts = "", quiet = TRUE
){


  ## check for latte
  program_not_found_stop("latte_path")



  ## check args
  type   <- match.arg(type)
  method <- match.arg(method)


  ## set executable to use
  if(type == "max"){
    latteProgram <- "latte-maximize"
  } else if(type == "min"){
    latteProgram <- "latte-minimize"
  }


  ## check for latte
  if(is.null(getOption("latte_path"))){
    stop(
      "algstat doesn't know where ", latteProgram, " is (or any other latte programs),\n",
      "  and so can't perform maximization.  see ?setLattePath", call. = FALSE
    )
  }


  ## parse objective
  if(is.character(objective)) objective <- mp(objective)
  stopifnot(is.linear(objective))


  ## parse constraints into the poly <= 0 format
  nConstraints <- length(constraints)

  if(is.character(constraints) && nConstraints > 1){

  	parsedCons <- as.list(rep(NA, nConstraints))

  	geqNdcs <- which(str_detect(constraints, " >= "))
  	leqNdcs <- which(str_detect(constraints, " <= "))
  	eeqNdcs <- which(str_detect(constraints, " == "))
  	eqNdcs  <- which(str_detect(constraints, " = "))

    if(length(geqNdcs) > 0){
      tmp <- strsplit(constraints[geqNdcs], " >= ")
      parsedCons[geqNdcs] <- lapply(tmp, function(v) mp(v[2]) - mp(v[1]))
    }

    if(length(leqNdcs) > 0){
      tmp <- strsplit(constraints[leqNdcs], " <= ")
      parsedCons[leqNdcs] <- lapply(tmp, function(v) mp(v[1]) - mp(v[2]))
    }

    if(length(eeqNdcs) > 0){
      tmp <- strsplit(constraints[eeqNdcs], " == ")
      parsedCons[eeqNdcs] <- lapply(tmp, function(v) mp(v[1]) - mp(v[2]))
    }

    if(length(eqNdcs) > 0){
      tmp <- strsplit(constraints[eqNdcs], " = ")
      parsedCons[eqNdcs] <- lapply(tmp, function(v) mp(v[1]) - mp(v[2]))
    }

    linearityNdcs <- sort(c(eeqNdcs, eqNdcs))

    constraints <- parsedCons
    class(constraints) <- "mpolyList"

    if(!all(is.linear(constraints))){
      stop("all polynomials must be linear.", call. = FALSE)
    }

  }


  ## mpoly_list_to_mat is in file count.r
  matFull <- mpoly_list_to_mat(c(list(objective), constraints))


  ## make dir to put latte files in (within the tempdir) timestamped
  dir2 <- file.path2(dir, timeStamp())
  suppressWarnings(dir.create(dir2))


  ## switch to temporary directory
  oldWd <- getwd(); on.exit(setwd(oldWd), add = TRUE)
  setwd(dir2)


  ## convert constraints to latte hrep code and write file
  mat <- cbind(
    -matFull[-1,"coef",drop=FALSE],
    -matFull[-1,-ncol(matFull)]
  )

  if(length(linearityNdcs) > 0){
    attr(mat, "linearity")   <- linearityNdcs

  }
  # note: the nonnegative stuff is built into this
  write.latte(mat, "optimCode")


  ## convert objective to latte hrep code and write file
  mat <- cbind(
    matFull[1,"coef",drop=FALSE],
    matFull[1,-ncol(matFull),drop=FALSE]
  )[,-1, drop = FALSE]
  write.latte(mat, "optimCode.cost")



  ## run latte function
  if(is.unix()){ # includes OS-X
  	# bizarrely, latte-maximize returns its output as stderr
    system(
      paste(
        file.path2(getOption("latte_path"), latteProgram),
        opts,
        file.path2(dir2, "optimCode 2> out.txt")
      ),
      intern = FALSE, ignore.stderr = FALSE
    )
    outPrint <- readLines(file.path2(dir2, "out.txt"))
  } else if(is.win()){ # windows
    matFile <- file.path2(dir2, "optimCode 2> out.txt")
    matFile <- chartr("\\", "/", matFile)
    matFile <- str_c("/cygdrive/c", str_sub(matFile, 3))
    system(
      paste(
        paste0("cmd.exe /c env.exe"),
        file.path(getOption("latte_path"), latteProgram),
        opts,
        matFile
      ),
      intern = FALSE, ignore.stderr = FALSE
    )
    outPrint <- readLines(file.path2(dir2, "out.txt"))
  }


  ## print count output when quiet = FALSE
  if(!quiet) cat(outPrint, sep = "\n")


  ## parse output
  lookFor <- ifelse(method == "cones", "An optimal", "A vertex which we found via LP")
  par <- outPrint[which(str_detect(outPrint, lookFor))]
  par <- strsplit(par, ": ")[[1]][2]
  if(method == "cones") par <- str_sub(par, 2, -3)
  if(method == "lp")    par <- str_sub(par, 2, -2)
  par <- as.integer(strsplit(par, " ")[[1]])
  names(par) <- colnames(matFull)[1:(ncol(matFull)-1)]

  lookFor <- ifelse(method == "cones", "The optimal value is", "The LP optimal value is")
  val <- outPrint[which(str_detect(outPrint, lookFor))]
  val <- strsplit(val, ": ")[[1]][2]
  if(method == "cones") val <- str_sub(val, 1, -2)
  val <- as.integer(val)

  ## out
  list(par = par, value = val)
}












#' @rdname latte_optim
#' @export
latte_max <- function(objective, constraints, method = c("lp","cones"),
  dir = tempdir(), opts = "", quiet = TRUE
){

  latte_optim(objective, constraints, "max", method, dir, opts, quiet)

}




#' @rdname latte_optim
#' @export
latte_min <- function(objective, constraints, method = c("lp","cones"),
  dir = tempdir(), opts = "", quiet = TRUE
){

  latte_optim(objective, constraints, "min", method, dir, opts, quiet)

}




