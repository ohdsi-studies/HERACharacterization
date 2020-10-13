# Copyright 2020 Observational Health Data Sciences and Informatics
#
# This file is part of HERACharacterization
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

# Format and check code ---------------------------------------------------
OhdsiRTools::formatRFolder()
OhdsiRTools::checkUsagePackage("HERACharacterization")
OhdsiRTools::updateCopyrightYearFolder()
devtools::document()
Sys.setenv(JAVA_HOME = "")
devtools::check()

# Create manual -----------------------------------------------------------
unlink("extras/HERACharacterization.pdf")
shell("R CMD Rd2pdf ./ --output=extras/HERACharacterization.pdf")

pkgdown::build_site()


# AGS: Had to copy these functions from OhdsiRWebAPI since we're using the cohortId for the SQL file
# names Insert cohort definitions from ATLAS into package -----------------------
insertCohortDefinitionSetInPackage <- function(fileName = "inst/settings/CohortsToCreate.csv",
                                               baseUrl,
                                               jsonFolder = "inst/cohorts",
                                               sqlFolder = "inst/sql/sql_server",
                                               rFileName = "R/CreateCohorts.R",
                                               insertTableSql = TRUE,
                                               insertCohortCreationR = TRUE,
                                               generateStats = FALSE,
                                               packageName) {
  errorMessage <- checkmate::makeAssertCollection()
  checkmate::assertLogical(insertTableSql, add = errorMessage)
  checkmate::assertLogical(insertCohortCreationR, add = errorMessage)
  checkmate::assertLogical(generateStats, add = errorMessage)
  checkmate::assertScalar(packageName, add = errorMessage)
  checkmate::assertCharacter(packageName, add = errorMessage)
  checkmate::reportAssertions(errorMessage)

  if (insertCohortCreationR && !insertTableSql)
    stop("Need to insert table SQL in order to generate R code")
  if (insertCohortCreationR && generateStats && jsonFolder != "inst/cohorts")
    stop("When generating R code and generating stats, the jsonFolder must be 'inst/cohorts'")
  if (insertCohortCreationR && sqlFolder != "inst/sql/sql_server")
    stop("When generating R code, the sqlFolder must be 'inst/sql/sql_server'")
  if (insertCohortCreationR && !grepl("inst", fileName))
    stop("When generating R code, the input CSV file must be in the inst folder.")

  cohortsToCreate <- readr::read_csv(fileName, col_types = readr::cols())
  cohortsToCreate <- cohortsToCreate[cohortsToCreate$atlasId > 0, ]

  # Inserting cohort JSON and SQL
  for (i in 1:nrow(cohortsToCreate)) {
    writeLines(paste("Inserting cohort:", cohortsToCreate$name[i]))
    insertCohortDefinitionInPackage(cohortId = cohortsToCreate$atlasId[i],
                                    localCohortId = cohortsToCreate$cohortId[i],
                                    name = cohortsToCreate$name[i],
                                    baseUrl = baseUrl,
                                    jsonFolder = jsonFolder,
                                    sqlFolder = sqlFolder,
                                    generateStats = generateStats)
  }

  # Insert SQL to create empty cohort table
  if (insertTableSql) {
    writeLines("Creating SQL to create empty cohort table")
    .insertSqlForCohortTableInPackage(statsTables = generateStats, sqlFolder = sqlFolder)
  }

  # Store information on inclusion rules
  if (generateStats) {
    writeLines("Storing information on inclusion rules")
    rules <- .getCohortInclusionRules(jsonFolder)
    rules <- merge(rules, data.frame(cohortId = cohortsToCreate$cohortId,
                                     cohortName = cohortsToCreate$name))
    csvFileName <- file.path(jsonFolder, "InclusionRules.csv")
    write.csv(rules, csvFileName, row.names = FALSE)
    writeLines(paste("- Created CSV file:", csvFileName))
  }

  # Generate R code to create cohorts
  if (insertCohortCreationR) {
    writeLines("Generating R code to create cohorts")
    templateFileName <- system.file("CreateCohorts.R", package = "ROhdsiWebApi", mustWork = TRUE)
    rCode <- readChar(templateFileName, file.info(templateFileName)$size)
    rCode <- gsub("#CopyrightYear#", format(Sys.Date(), "%Y"), rCode)
    rCode <- gsub("#packageName#", packageName, rCode)
    libPath <- gsub(".*inst[/\\]", "", fileName)
    libPath <- gsub("/|\\\\", "\", \"", libPath)
    rCode <- gsub("#fileName#", libPath, rCode)
    if (generateStats) {
      rCode <- gsub("#stats_start#", "", rCode)
      rCode <- gsub("#stats_end#", "", rCode)
    } else {
      rCode <- gsub("#stats_start#.*?#stats_end#", "", rCode)
    }
    fileConn <- file(rFileName)
    writeChar(rCode, fileConn, eos = NULL)
    close(fileConn)
    writeLines(paste("- Created R file:", rFileName))
  }
}

insertCohortDefinitionInPackage <- function(cohortId,
                                            localCohortId,
                                            name = NULL,
                                            jsonFolder = "inst/cohorts",
                                            sqlFolder = "inst/sql/sql_server",
                                            baseUrl,
                                            generateStats = FALSE) {
  errorMessage <- checkmate::makeAssertCollection()
  checkmate::assertInt(cohortId, add = errorMessage)
  checkmate::assertLogical(generateStats, add = errorMessage)
  checkmate::reportAssertions(errorMessage)

  object <- ROhdsiWebApi::getCohortDefinition(cohortId = cohortId, baseUrl = baseUrl)
  if (is.null(name)) {
    name <- object$name
  }
  if (!file.exists(jsonFolder)) {
    dir.create(jsonFolder, recursive = TRUE)
  }
  jsonFileName <- file.path(jsonFolder, paste(localCohortId, "json", sep = "."))
  json <- RJSONIO::toJSON(object$expression,
                          digits = 23,
                          pretty = TRUE)  # Use the work-around here vs what is returned from ROhdsiWebApi
  SqlRender::writeSql(sql = json, targetFile = jsonFileName)
  writeLines(paste("- Created JSON file:", jsonFileName))

  # Fetch SQL
  sql <- ROhdsiWebApi::getCohortSql(baseUrl = baseUrl,
                                    cohortDefinition = object,
                                    generateStats = generateStats)
  if (!file.exists(sqlFolder)) {
    dir.create(sqlFolder, recursive = TRUE)
  }
  sqlFileName <- file.path(sqlFolder, paste(localCohortId, "sql", sep = "."))
  SqlRender::writeSql(sql = sql, targetFile = sqlFileName)
  writeLines(paste("- Created SQL file:", sqlFileName))
}

cohortGroups <- readr::read_csv("inst/settings/CohortGroups.csv", col_types = readr::cols())
# Import only the features for now
cohortGroupSubset <- cohortGroups[cohortGroups$cohortGroup == 'feature',]
for (i in 1:nrow(cohortGroupSubset)) {
  ParallelLogger::logInfo("* Importing cohorts in group: ", cohortGroupSubset$cohortGroup[i], " *")
  insertCohortDefinitionSetInPackage(fileName = file.path("inst/", cohortGroupSubset$fileName[i]),
                                     baseUrl = Sys.getenv("baseUrl"),
                                     insertTableSql = FALSE,
                                     insertCohortCreationR = FALSE,
                                     generateStats = FALSE,
                                     packageName = "HERACharacterization")
}
unlink("inst/cohorts/InclusionRules.csv")

# Create the file for use by CohortDiagnostics
cohortsToCreateFull <- data.frame()
for (i in 1:nrow(cohortGroups)) {
  cohortsToCreate <- readr::read_csv(file.path("inst/", cohortGroups$fileName[i]),
                                     col_types = readr::cols())
  cohortsToCreate$name <- cohortsToCreate$cohortId
  cohortsToCreateFull <- rbind(cohortsToCreateFull, cohortsToCreate)
}
readr::write_csv(cohortsToCreateFull, file.path("inst/settings/diagnostics/CohortsToCreate.csv"))


# Create the list of combinations of T, TwS, TwoS for the combinations of subgroups
# ----------------------------
settingsPath <- "inst/settings"
targetCohorts <- read.csv(file.path(settingsPath, "CohortsToCreateTarget.csv"))
bulkSubgroup <- read.csv(file.path(settingsPath, "BulkSubgroup.csv"))
derivedCohorts <- read.csv(file.path(settingsPath, "CohortsToDeriveTarget.csv"))
atlasCohortSubgroup <- read.csv(file.path(settingsPath, "CohortsToCreateSubgroup.csv"))
featureCohorts <- read.csv(file.path(settingsPath, "CohortsToCreateFeature.csv"))


# Ensure all of the IDs are unique
allCohortIds <- c(targetCohorts[,
                  match("cohortId", names(targetCohorts))],
                  bulkSubgroup[,
                  match("cohortId", names(bulkSubgroup))],
                  derivedCohorts[,
                  match("cohortId", names(derivedCohorts))],
                  atlasCohortSubgroup[,
                  match("cohortId", names(atlasCohortSubgroup))],
                  featureCohorts[,
                  match("cohortId", names(featureCohorts))])
allCohortIds <- sort(allCohortIds)

totalRows <- nrow(targetCohorts) +
             nrow(bulkSubgroup) +
             nrow(derivedCohorts) +
             nrow(atlasCohortSubgroup) +
             nrow(featureCohorts)
if (length(unique(allCohortIds)) != totalRows) {
  warning("There are duplicate cohort IDs in the settings files!")
}

# When necessary, use this to view the full list of cohorts in the study
fullCohortList <- rbind(targetCohorts[,
                        c("cohortId", "name")],
                        derivedCohorts[
                        c("cohortId","name")],
                        atlasCohortSubgroup[,
                        c("cohortId","name")],
                        featureCohorts[,
                        c("cohortId","name")])

fullCohortList <- fullCohortList[order(fullCohortList$cohortId), ]

# Target cohorts - HERACharacterization SPECIFIC - using Targets + Features ==> All Targets
colNames <- c("name", "cohortId")  # Use this to subset to the columns of interest
heraTargetCohorts <- rbind(targetCohorts[, match(colNames, names(targetCohorts))],
                           derivedCohorts[, match(colNames, names(derivedCohorts))])
names(heraTargetCohorts) <- c("targetName", "targetId")
# Subgroup cohorts
if (nrow(bulkSubgroup) > 0) {
  bulkSubgroup <- bulkSubgroup[, match(colNames, names(bulkSubgroup))]
  bulkSubgroup$withSubgroupName <- paste("with", trimws(bulkSubgroup$name))
  bulkSubgroup$inverseName <- paste("without", trimws(bulkSubgroup$name))
}
atlasCohortSubgroup <- atlasCohortSubgroup[, match(colNames, names(atlasCohortSubgroup))]
atlasCohortSubgroup$withSubgroupName <- paste("with", trimws(atlasCohortSubgroup$name))
atlasCohortSubgroup$inverseName <- paste("without", trimws(atlasCohortSubgroup$name))
subgroup <- rbind(bulkSubgroup, atlasCohortSubgroup)
names(subgroup) <- c("name", "subgroupId", "subgroupName", "subgroupInverseName")
# Get all of the unique combinations of target + subgroup
targetsubgroupCP <- do.call(expand.grid,
                            lapply(list(heraTargetCohorts$targetId, subgroup$subgroupId), unique))
names(targetsubgroupCP) <- c("targetId", "subgroupId")
targetsubgroupCP <- merge(targetsubgroupCP, heraTargetCohorts)
targetsubgroupCP <- merge(targetsubgroupCP, subgroup)
targetsubgroupCP <- targetsubgroupCP[order(targetsubgroupCP$subgroupId,
                                           targetsubgroupCP$targetId), ]
targetsubgroupCP$cohortId <- (targetsubgroupCP$targetId * 1e+06) +
                             (targetsubgroupCP$subgroupId * 10)
tWithS <- targetsubgroupCP
tWithoutS <- targetsubgroupCP[targetsubgroupCP$subgroupId %in% atlasCohortSubgroup$cohortId, ]
tWithS$cohortId <- tWithS$cohortId + 1
tWithS$cohortType <- "TwS"
tWithS$name <- paste(tWithS$targetName, tWithS$subgroupName)
# tWithoutS$cohortId <- tWithoutS$cohortId + 2 tWithoutS$cohortType <- 'TwoS' tWithoutS$name <-
# paste(tWithoutS$targetName, tWithoutS$subgroupInverseName)
targetsubgroupXRef <- tWithS  #rbind(tWithS, tWithoutS)



# For shiny, construct a data frame to provide details on the original cohort names
xrefColumnNames <- c("cohortId",
                     "targetId",
                     "targetName",
                     "subgroupId",
                     "subgroupName",
                     "cohortType")
targetCohortsForShiny <- heraTargetCohorts
targetCohortsForShiny$cohortId <- targetCohortsForShiny$targetId
targetCohortsForShiny$subgroupId <- 0
targetCohortsForShiny$subgroupName <- "All"
targetCohortsForShiny$cohortType <- "Target"
inversesubgroup <- targetsubgroupXRef[targetsubgroupXRef$cohortType == "TwoS", ]
inversesubgroup$subgroupName <- inversesubgroup$subgroupInverseName

shinyCohortXref <- rbind(targetCohortsForShiny[,
                         xrefColumnNames],
                         inversesubgroup[,
                         xrefColumnNames],
                         targetsubgroupXRef[targetsubgroupXRef$cohortType == "TwS",
                         xrefColumnNames])

readr::write_csv(shinyCohortXref, file.path("inst/shiny/ResultsExplorer", "cohortXref.csv"))

# Write out the final targetsubgroupXRef
targetsubgroupXRef <- targetsubgroupXRef[, c("targetId",
                                             "subgroupId",
                                             "cohortId",
                                             "cohortType",
                                             "name")]
readr::write_csv(targetsubgroupXRef, file.path(settingsPath, "targetSubgroupXref.csv"))


# Store environment in which the study was executed -----------------------
OhdsiRTools::insertEnvironmentSnapshotInPackage("HERACharacterization")

# Check all files for UTF-8 Encoding and ensure there are no non-ASCII characters
OhdsiRTools::findNonAsciiStringsInFolder()

packageFiles <- list.files(path = ".", recursive = TRUE)
if (!all(utf8::utf8_valid(packageFiles))) {
  print("Found invalid UTF-8 encoded files")
}

# Create the Renv lock file
OhdsiRTools::createRenvLockFile("HERACharacterization")
