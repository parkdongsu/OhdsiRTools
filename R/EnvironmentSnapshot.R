# @file OhdsiRTools.R
#
# Copyright 2019 Observational Health Data Sciences and Informatics
#
# This file is part of OhdsiRTools
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#' Take a snapshot of the R environment
#'
#' @details
#' This function records all versions used in the R environment that are used by one root package.
#' This can be used for example to restore the environment to the state it was when a particular study
#' package was run using the \code{\link{restoreEnvironment}} function.
#'
#' @param rootPackage   The name of the root package
#'
#' @return
#' A data frame listing all the dependencies of the root package and their version numbers, in the
#' order in which they should be installed.
#'
#' @examples
#' snapshot <- takeEnvironmentSnapshot("OhdsiRTools")
#' snapshot
#'
#' @export
takeEnvironmentSnapshot <- function(rootPackage) {

  splitPackageList <- function(packageList) {
    if (is.null(packageList)) {
      return(c())
    } else {
      return(strsplit(gsub("\\([^)]*\\)", "", gsub(" ", "", gsub("\n", "", packageList))),
                      ",")[[1]])
    }
  }

  fetchDependencies <- function(package, recursive = TRUE, level = 0) {
    description <- packageDescription(package)
    packages <- splitPackageList(description$Depends)
    packages <- c(packages, splitPackageList(description$Imports))
    # Note: if we want to include suggests, we'll need to consider circular references packages <-
    # c(packages, splitPackageList(description$Suggests))
    packages <- packages[packages != "R"]
    packages <- data.frame(name = packages, level = rep(level,
                                                        length(packages)), stringsAsFactors = FALSE)
    if (recursive && nrow(packages) > 0) {
      all <- lapply(packages$name, fetchDependencies, recursive = TRUE, level = level + 1)
      dependencies <- do.call("rbind", all)
      if (nrow(dependencies) > 0) {
        packages <- rbind(packages, dependencies)
        packages <- aggregate(level ~ name, packages, max)
      }
    }
    return(packages)
  }

  packages <- fetchDependencies(rootPackage, recursive = TRUE)
  packages <- packages[order(-packages$level), ]
  getVersion <- function(package) {
    return(packageDescription(package)$Version)
  }
  versions <- sapply(c(packages$name, rootPackage), getVersion)
  snapshot <- data.frame(package = names(versions), version = as.vector(versions))
  s <- sessionInfo()
  rVersion <- data.frame(package = "R",
                         version = paste(s$R.version$major, s$R.version$minor, sep = "."))
  snapshot <- rbind(rVersion, snapshot)
  return(snapshot)
}

comparable <- function(installedVersion, requiredVersion) {
  parts1 <- strsplit(as.character(installedVersion), "[^0-9]")[[1]]
  parts2 <- strsplit(as.character(requiredVersion), "[^0-9]")[[1]]
  if (parts1[1] != parts2[1]) {
    return(FALSE)
  } 
  parts1 <- as.numeric(parts1)
  parts2 <- as.numeric(parts2)
  if (length(parts1) > 1 && parts1[2] > parts2[2]) {
    return(TRUE)
  } else if (length(parts1) > 2 && parts1[2] == parts2[2] && parts1[3] > parts2[3]) {
    return(TRUE)
  } else if (length(parts1) > 3 && parts1[2] == parts2[2] && parts1[3] == parts2[3] && parts1[4] > parts2[4]) {
    return(TRUE)
  }
  return(FALSE)
}


#' Restore the R environment to a snapshot
#'
#' @details
#' This function restores the R environment to a previous snapshot, meaning all the packages will be
#' restored to the versions they were at at the time of the snapshot. Note: on Windows you will very
#' likely need to have RTools installed to build the various packages.
#'
#' @param snapshot              The snapshot data frame as generated using the
#'                              \code{\link{takeEnvironmentSnapshot}} function.
#' @param stopOnWrongRVersion   Should the function stop when the wrong version of R is installed? Else
#'                              just a warning will be thrown when the version doesn't match.
#' @param strict                If TRUE, the exact version of each package will installed. If FALSE, a
#'                              package will only be installed if (a) a newer version is required than
#'                              currently installed, or (b) the major version number is different.
#' @param skipLast              Skip last entry in snapshot? This is usually the study package that needs
#'                              to be installed manualy.
#'
#'
#' @examples
#' \dontrun{
#' snapshot <- takeEnvironmentSnapshot("OhdsiRTools")
#' write.csv(snapshot, "snapshot.csv")
#'
#' # 5 years later
#'
#' snapshot <- read.csv("snapshot.csv")
#' restoreEnvironment(snapshot)
#' }
#' @export
restoreEnvironment <- function(snapshot, stopOnWrongRVersion = FALSE, strict = FALSE, skipLast = TRUE) {
  start <- Sys.time()
  # R core packages that cannot be installed:
  corePackages <- c("grDevices", "graphics", "utils", "stats", "methods", "tools", "grid", "datasets", "rlang", "devtools")
  
  # OHDSI packages not in CRAN:
  ohdsiPackages <- c("Achilles", "BigKnn", "CaseControl", "CaseCrossover", "CohortMethod", 
                     "EvidenceSynthesis", "FeatureExtraction", "IcTemporalPatternDiscovery", 
                     "MethodEvaluation", "OhdsiRTools", "OhdsiSharing", "PatientLevelPrediction",
                     "PheValuator", "SelfControlledCaseSeries", "SelfControlledCohort")
  
  s <- sessionInfo()
  rVersion <- paste(s$R.version$major, s$R.version$minor, sep = ".")
  if (rVersion != as.character(snapshot$version[snapshot$package == "R"])) {
    message <- sprintf("Wrong R version: need version %s, found version %s",
                       as.character(snapshot$version[snapshot$package == "R"]),
                       rVersion)
    if (stopOnWrongRVersion) {
      stop(message)
    } else {
      warning(message)
    }
  }
  
  snapshot <- snapshot[snapshot$package != "R", ]
  if (skipLast) {
    snapshot <- snapshot[1:(nrow(snapshot) - 1), ]
  }
  for (i in 1:nrow(snapshot)) {
    package <- as.character(snapshot$package[i])
    requiredVersion <- as.character(snapshot$version[i])
    isInstalled <- package %in% installed.packages()
    if (isInstalled) {
      installedVersion <- packageDescription(package)$Version
    }
    if (package %in% corePackages) {
      writeLines(sprintf("Skipping %s (%s) because part of R core", package, requiredVersion))
    } else if (isInstalled && requiredVersion == installedVersion) {
      writeLines(sprintf("Skipping %s (%s) because correct version already installed", package, requiredVersion))
    } else if (!strict && isInstalled && comparable(installedVersion, requiredVersion)) {  
      writeLines(sprintf("Skipping %s because installed version (%s) is newer than required version (%s), and major version number is the same", 
                         package,
                         installedVersion, 
                         requiredVersion))
    } else if (package %in% ohdsiPackages) {
      if (isInstalled) {
        writeLines(sprintf("Installing %s because version %s needed but version %s found", package, requiredVersion, installedVersion))
      } else {
        writeLines(sprintf("Installing %s (%s)", package, requiredVersion))
      }
      url <- sprintf("https://github.com/OHDSI/drat/raw/gh-pages/src/contrib/%s_%s.tar.gz", package, requiredVersion)
      devtools::install_url(url, dependencies = FALSE)
    } else {
      if (package %in% installed.packages()) {
        writeLines(sprintf("Installing %s because version %s needed but version %s found", package, requiredVersion, installedVersion))
      } else {
        writeLines(sprintf("Installing %s (%s)", package, requiredVersion))
      }
      devtools::install_version(package = package, version = requiredVersion, type = "source", dependencies = FALSE)
    }
  }
  delta <- Sys.time() - start
  writeLines(paste("Restoring environment took", delta, attr(delta, "units")))
  invisible(NULL)
}


#' Store snapshot of the R environment in the package
#'
#' @details
#' This function records all versions used in the R environment that are used by one root package, and
#' stores them in a CSV file in the R package that is currently being developed. The default location is
#' \code{inst/settings/rEnvironmentSnapshot.csv}.This can be used for example to restore the
#' environment to the state it was when a particular study package was run using the
#' \code{\link{restoreEnvironment}} function.
#'
#' @param rootPackage   The name of the root package
#' @param pathToCsv    The path for saving the snapshot (as CSV file).
#'
#' @examples
#' \dontrun{
#' insertEnvironmentSnapshotInPackage("OhdsiRTools")
#' }
#'
#' @export
insertEnvironmentSnapshotInPackage <- function(rootPackage, pathToCsv = "inst/settings/rEnvironmentSnapshot.csv") {
  snapshot <- takeEnvironmentSnapshot(rootPackage)
  folder <- dirname(pathToCsv)
  if (!file.exists(folder)) {
    dir.create(folder, recursive = TRUE)
  }
  write.csv(snapshot, pathToCsv, row.names = FALSE)
}

#' Restore environment stored in package
#'
#' @details
#' This function restores all packages (and package versions) described in the environment snapshot stored
#' in the package currently being developed. The default location is
#' \code{inst/settings/rEnvironmentSnapshot.csv}.
#'
#' @param pathToCsv             The path for saving the snapshot (as CSV file).
#' @param stopOnWrongRVersion   Should the function stop when the wrong version of R is installed? Else
#'                              just a warning will be thrown when the version doesn't match.
#' @param strict                If TRUE, the exact version of each package will installed. If FALSE, a
#'                              package will only be installed if (a) a newer version is required than
#'                              currently installed, or (b) the major version number is different.
#' @param skipLast              Skip last entry in snapshot? This is usually the study package that needs
#'                              to be installed manualy.
#'
#' @examples
#' \dontrun{
#' restoreEnvironmentFromPackage()
#' }
#'
#' @export
restoreEnvironmentFromPackage <- function(pathToCsv = "inst/settings/rEnvironmentSnapshot.csv", 
                                          stopOnWrongRVersion = FALSE, 
                                          strict = FALSE,
                                          skipLast = TRUE) {
  snapshot <- read.csv(pathToCsv)
  restoreEnvironment(snapshot = snapshot,
                     stopOnWrongRVersion = stopOnWrongRVersion,
                     strict = strict,
                     skipLast = skipLast)
  
}

#' Restore environment stored in package
#'
#' @details
#' This function restores all packages (and package versions) described in the environment snapshot stored
#' in the package currently being developed. The default location is
#' \code{inst/settings/rEnvironmentSnapshot.csv}.
#'
#' @param githubPath            The path for the GitHub repo containing the package (e.g. 'OHDSI/StudyProtocols/AlendronateVsRaloxifene').
#' @param pathToCsv             The path for the snapshot inside the package.
#' @param stopOnWrongRVersion   Should the function stop when the wrong version of R is installed? Else
#'                              just a warning will be thrown when the version doesn't match.
#' @param strict                If TRUE, the exact version of each package will installed. If FALSE, a
#'                              package will only be installed if (a) a newer version is required than
#'                              currently installed, or (b) the major version number is different.
#' @param skipLast              Skip last entry in snapshot? This is usually the study package that needs
#'                              to be installed manualy.
#'
#' @examples
#' \dontrun{
#' restoreEnvironmentFromPackageOnGithub("OHDSI/StudyProtocols/AlendronateVsRaloxifene")
#' }
#'
#' @export
restoreEnvironmentFromPackageOnGithub <- function(githubPath, 
                                                  pathToCsv = "inst/settings/rEnvironmentSnapshot.csv",
                                                  stopOnWrongRVersion = FALSE, 
                                                  strict = FALSE,
                                                  skipLast = TRUE) {
  parts <- strsplit(githubPath, "/")[[1]]
  if (length(parts) > 2) {
    githubPath <- paste(c(parts[1:2], "master", parts[3:length(parts)]), collapse = "/")
  } else {
    githubPath <- paste(c(parts[1:2], "master"), collapse = "/")
  }
  url <- paste(c("https://raw.githubusercontent.com", githubPath, pathToCsv), collapse = "/")
  snapshot <- read.csv(url)
  restoreEnvironment(snapshot = snapshot,
                     stopOnWrongRVersion = stopOnWrongRVersion,
                     strict = strict,
                     skipLast = skipLast)
}

