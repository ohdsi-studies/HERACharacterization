#' Get the bulk subgroups from the resource file
#'
#' @description
#' Reads the settings in /inst/settings/BulkSubgroup.csv
#'
#' @export
getBulkSubgroup <- function() {
  resourceFile <- file.path(getPathToResource(), "BulkSubgroup.csv")
  return(readCsv(resourceFile))
}

#' Get the cohorts to derive from the resource file
#'
#' @description
#' Reads the settings in /inst/settings/CohortsToDeriveTarget.csv
#'
#' @export
getCohortsToDeriveTarget <- function() {
  resourceFile <- file.path(getPathToResource(), "CohortsToDeriveTarget.csv")
  return(readCsv(resourceFile))
}

#' Get the cohort groups from the resource file
#'
#' @description
#' Reads the settings in /inst/settings/CohortGroups.csv
#'
#' @export
getCohortGroups <- function () {
  resourceFile <- file.path(getPathToResource(), "CohortGroups.csv")
  return(readCsv(resourceFile))
}

#' Get the cohort subgroups from the resource file
#'
#' @description
#' Reads the settings in /inst/settings/CohortsToCreateSubgroup.csv
#'
#' @export
getCohortBasedSubgroup <- function() {
  resourceFile <- file.path(getPathToResource(), "CohortsToCreateSubgroup.csv")
  return(readCsv(resourceFile))
}

#' Get the cohort used for features from the resorce file
#'
#' @description
#' Reads the settings in /inst/settings/CohortsToCreateFeature.csv
#'
#' @export
getFeatures <- function() {
  resourceFile <- file.path(getPathToResource(), "CohortsToCreateFeature.csv")
  return(readCsv(resourceFile))
}

getFeatureTimeWindows <- function() {
  resourceFile <- file.path(getPathToResource(), "featureTimeWindows.csv")
  return(readCsv(resourceFile))
}

#' Get the list of sub-grouped target cohorts
#'
#' @description
#' Reads the settings in /inst/settings/targetSubgroupXref.csv
#'
#' @export
getTargetSubgroupXref <- function() {
  resourceFile <- file.path(getPathToResource(), "targetSubgroupXref.csv")
  return(readCsv(resourceFile))
}

#' Get the full list of cohorts to create for the study
#'
#' @description
#' Reads inst/settings/CohortGroups.csv and creates a list of all cohorts
#' from the indvidual resource files. Returns a concatenated list of cohorts
#'
#' @export
getCohortsToCreate <- function(cohortGroups = getCohortGroups()) {
  packageName <- getThisPackageName()
  cohorts <- data.frame()
  for(i in 1:nrow(cohortGroups)) {
    c <- readr::read_csv(system.file(cohortGroups$fileName[i], package = packageName, mustWork = TRUE), col_types = readr::cols())
    c$cohortType <- cohortGroups$cohortGroup[i]
    cohorts <- rbind(cohorts, c)
  }
  return(cohorts)  
}

getAllSubgroup <- function() {
  colNames <- c("name", "cohortId", "generationScript") # Use this to subset to the columns of interest
  bulkSubgroup <- getBulkSubgroup()
  bulkSubgroup <- bulkSubgroup[, match(colNames, names(bulkSubgroup))]
  atlasCohortSubgroup <- getCohortBasedSubgroup()
  atlasCohortSubgroup$generationScript <- paste0(atlasCohortSubgroup$cohortId, ".sql")
  atlasCohortSubgroup <- atlasCohortSubgroup[, match(colNames, names(atlasCohortSubgroup))]
  subgroup <- rbind(bulkSubgroup, atlasCohortSubgroup)
  return(subgroup)  
}

getAllStudyCohorts <- function() {
  cohortsToCreate <- getCohortsToCreate()
  targetSubgroupXref <- getTargetSubgroupXref()
  colNames <- c("name", "cohortId")
  cohortsToCreate <- cohortsToCreate[, match(colNames, names(cohortsToCreate))]
  targetSubgroupXref <- targetSubgroupXref[, match(colNames, names(targetSubgroupXref))]
  allCohorts <- rbind(cohortsToCreate, targetSubgroupXref)
  return(allCohorts)
}

#' @export
getAllStudyCohortsWithDetails <- function() {
  cohortsToCreate <- getCohortsToCreate()
  targetSubgroupXref <- getTargetSubgroupXref()
  allSubgroup <- getAllSubgroup()
  colNames <- c("cohortId", "cohortName", "targetCohortId", "targetCohortName", "subgroupCohortId", "subgroupCohortName", "cohortType")
  # Format - cohortsToCreate
  cohortsToCreate$targetCohortId <- cohortsToCreate$cohortId
  cohortsToCreate$targetCohortName <- cohortsToCreate$name
  cohortsToCreate$subgroupCohortId <- 0
  cohortsToCreate$subgroupCohortName <- "All"
  cohortsToCreate <- dplyr::rename(cohortsToCreate, cohortName = "name")
  cohortsToCreate <- cohortsToCreate[, match(colNames, names(cohortsToCreate))]
  # Format - targetSubgroupXref
  stratifiedCohorts <- dplyr::inner_join(targetSubgroupXref, cohortsToCreate[,c("targetCohortId", "targetCohortName")], by = c("targetId" = "targetCohortId"))
  stratifiedCohorts <- dplyr::inner_join(stratifiedCohorts, allSubgroup[,c("cohortId", "name")], by=c("subgroupId" = "cohortId"))
  stratifiedCohorts <- dplyr::rename(stratifiedCohorts, targetCohortId="targetId",subgroupCohortId="subgroupId",cohortName="name.x",subgroupCohortName="name.y")
  stratifiedCohorts <- stratifiedCohorts[,match(colNames, names(stratifiedCohorts))]
  # Bind
  allCohorts <- rbind(cohortsToCreate, stratifiedCohorts)
  return(allCohorts)
}

getThisPackageName <- function() {
  return("HERACharacterization")
}

#' @export
readCsv <- function(resourceFile, packageName = getThisPackageName()) {
  packageName <- getThisPackageName()
  pathToCsv <- system.file(resourceFile, package = packageName, mustWork = TRUE)
  fileContents <- readr::read_csv(pathToCsv, col_types = readr::cols())
  return(fileContents)
}

getPathToResource <- function() {
  return("settings")
}
