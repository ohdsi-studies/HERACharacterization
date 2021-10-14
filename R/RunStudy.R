#' @export
runStudy <- function(connectionDetails = NULL,
                     connection = NULL,
                     cdmDatabaseSchema,
                     oracleTempSchema = NULL,
                     cohortDatabaseSchema,
                     cohortTable = "cohort",
                     featureSummaryTable = "cohort_smry",
                     cohortIdsToExcludeFromExecution = c(),
                     cohortIdsToExcludeFromResultsExport = NULL,
                     cohortGroups = getUserSelectableCohortGroups(),
                     exportFolder,
                     databaseId,
                     databaseName = databaseId,
                     databaseDescription = "",
                     minCellCount = 5,
                     incremental = TRUE,
                     incrementalFolder = file.path(exportFolder, "RecordKeeping")) {

  start <- Sys.time()

  if (!file.exists(exportFolder)) {
    dir.create(exportFolder, recursive = TRUE)
  }

  ParallelLogger::addDefaultFileLogger(file.path(exportFolder, "HERACharacterization.txt"))
  ParallelLogger::addDefaultErrorReportLogger(file.path(outputFolder, "HERACharacterizationErrorReportR.txt"))
  on.exit(ParallelLogger::unregisterLogger("DEFAULT_FILE_LOGGER", silent = TRUE))
  on.exit(ParallelLogger::unregisterLogger("DEFAULT_ERRORREPORT_LOGGER", silent = TRUE), add = TRUE)
  
  # Write out the system information
  ParallelLogger::logInfo(.systemInfo())

  if (incremental) {
    if (is.null(incrementalFolder)) {
      stop("Must specify incrementalFolder when incremental = TRUE")
    }
    if (!file.exists(incrementalFolder)) {
      dir.create(incrementalFolder, recursive = TRUE)
    }
  }

  if (!is.null(getOption("andromedaTempFolder")) && !file.exists(getOption("andromedaTempFolder"))) {
    warning("andromedaTempFolder '", getOption("andromedaTempFolder"), "' not found. Attempting to create folder")
    dir.create(getOption("andromedaTempFolder"), recursive = TRUE)
  }

  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
  }

  # Instantiate cohorts -----------------------------------------------------------------------
  cohorts <- getCohortsToCreate()
  # Remove any cohorts that are to be excluded
  cohorts <- cohorts[!(cohorts$cohortId %in% cohortIdsToExcludeFromExecution), ]
  targetCohortIds <- cohorts[cohorts$cohortType %in% cohortGroups, "cohortId"][[1]]
  subgroupCohortIds <- cohorts[cohorts$cohortType == "subgroup", "cohortId"][[1]]
  featureCohortIds <- cohorts[cohorts$cohortType == "feature", "cohortId"][[1]]

  # Start with the target cohorts
  if (length(targetCohortIds) > 0) {
    ParallelLogger::logInfo("**********************************************************")
    ParallelLogger::logInfo("  ---- Creating target cohorts ---- ")
    ParallelLogger::logInfo("**********************************************************")
    instantiateCohortSet(connectionDetails = connectionDetails,
                         connection = connection,
                         cdmDatabaseSchema = cdmDatabaseSchema,
                         oracleTempSchema = oracleTempSchema,
                         cohortDatabaseSchema = cohortDatabaseSchema,
                         cohortTable = cohortTable,
                         cohortIds = targetCohortIds,
                         createCohortTable = TRUE,
                         generateInclusionStats = FALSE,
                         incremental = incremental,
                         incrementalFolder = incrementalFolder,
                         inclusionStatisticsFolder = exportFolder)
  }

  # Next do the subgroup cohorts
  if (length(subgroupCohortIds) > 0) {
    ParallelLogger::logInfo("******************************************")
    ParallelLogger::logInfo("  ---- Creating subgroup cohorts  ---- ")
    ParallelLogger::logInfo("******************************************")
    instantiateCohortSet(connectionDetails = connectionDetails,
                         connection = connection,
                         cdmDatabaseSchema = cdmDatabaseSchema,
                         oracleTempSchema = oracleTempSchema,
                         cohortDatabaseSchema = cohortDatabaseSchema,
                         cohortTable = cohortTable,
                         cohortIds = subgroupCohortIds,
                         createCohortTable = FALSE,
                         generateInclusionStats = FALSE,
                         incremental = incremental,
                         incrementalFolder = incrementalFolder,
                         inclusionStatisticsFolder = exportFolder)
  }

  if (length(featureCohortIds) > 0) {
    # Create the feature cohorts
    ParallelLogger::logInfo("**********************************************************")
    ParallelLogger::logInfo(" ---- Creating feature cohorts ---- ")
    ParallelLogger::logInfo("**********************************************************")
    instantiateCohortSet(connectionDetails = connectionDetails,
                         connection = connection,
                         cdmDatabaseSchema = cdmDatabaseSchema,
                         oracleTempSchema = oracleTempSchema,
                         cohortDatabaseSchema = cohortDatabaseSchema,
                         cohortTable = cohortTable,
                         cohortIds = featureCohortIds,
                         createCohortTable = FALSE,
                         generateInclusionStats = FALSE,
                         incremental = incremental,
                         incrementalFolder = incrementalFolder,
                         inclusionStatisticsFolder = exportFolder)
  }

  # Create the derived target cohorts
  ParallelLogger::logInfo("**********************************************************")
  ParallelLogger::logInfo(" ---- Creating derived target cohorts ---- ")
  ParallelLogger::logInfo("**********************************************************")
  createDerivedCohorts(connection = connection,
                       cdmDatabaseSchema = cdmDatabaseSchema,
                       cohortDatabaseSchema = cohortDatabaseSchema,
                       cohortTable = cohortTable,
                       oracleTempSchema = oracleTempSchema)

  # At this point, the derived target cohorts are created
  # add them to the list of targetCohortIds so that they are
  # part of the subgrouping below
  targetCohortIds <- c(targetCohortIds, as.numeric(unlist(HERACharacterization::getCohortsToDeriveTarget()[,c("cohortId")])))

  # Create the subgrouped cohorts
  ParallelLogger::logInfo("**********************************************************")
  ParallelLogger::logInfo(" ---- Creating subgrouped target cohorts ---- ")
  ParallelLogger::logInfo("**********************************************************")
  createBulkSubgroup(connection = connection,
                   cdmDatabaseSchema = cdmDatabaseSchema,
                   cohortDatabaseSchema = cohortDatabaseSchema,
                   cohortTable = cohortTable,
                   targetIds = targetCohortIds,
                   oracleTempSchema = oracleTempSchema)

  # Compute the features
  ParallelLogger::logInfo("**********************************************************")
  ParallelLogger::logInfo(" ---- Create feature proportions ---- ")
  ParallelLogger::logInfo("**********************************************************")
  createFeatureProportions(connection = connection,
                           cohortDatabaseSchema = cohortDatabaseSchema,
                           cohortTable = cohortTable,
                           featureSummaryTable = featureSummaryTable,
                           oracleTempSchema = oracleTempSchema)

  # Save database metadata ---------------------------------------------------------------
  ParallelLogger::logInfo("Saving database metadata")
  op <- getObservationPeriodDateRange(connection,
                                      cdmDatabaseSchema = cdmDatabaseSchema,
                                      oracleTempSchema = oracleTempSchema)
  database <- data.frame(databaseId = databaseId,
                         databaseName = databaseName,
                         description = databaseDescription,
                         vocabularyVersion = getVocabularyInfo(connection = connection,
                                                               cdmDatabaseSchema = cdmDatabaseSchema,
                                                               oracleTempSchema = oracleTempSchema),
                         minObsPeriodDate = op$minObsPeriodDate,
                         maxObsPeriodDate = op$maxObsPeriodDate,
                         isMetaAnalysis = 0)
  writeToCsv(database, file.path(exportFolder, "database.csv"))

  # Counting cohorts -----------------------------------------------------------------------
  ParallelLogger::logInfo("Counting cohorts")
  counts <- getCohortCounts(connection = connection,
                            cohortDatabaseSchema = cohortDatabaseSchema,
                            cohortTable = cohortTable)
  if (nrow(counts) > 0) {
    counts$databaseId <- databaseId
    counts <- enforceMinCellValue(counts, "cohortEntries", minCellCount)
    counts <- enforceMinCellValue(counts, "cohortSubjects", minCellCount)
  }
  writeToCsv(counts, file.path(exportFolder, "cohort_count.csv"))

  # Read in the cohort counts
  counts <- readr::read_csv(file.path(exportFolder, "cohort_count.csv"), col_types = readr::cols())
  colnames(counts) <- SqlRender::snakeCaseToCamelCase(colnames(counts))

  # Export the cohorts from the study
  cohortsForExport <- loadCohortsForExportFromPackage(cohortIds = counts$cohortId)
  writeToCsv(cohortsForExport, file.path(exportFolder, "cohort.csv"))

  # Extract feature counts -----------------------------------------------------------------------
  ParallelLogger::logInfo("Extract feature counts")
  featureProportions <- exportFeatureProportions(connection = connection,
                                                 cohortDatabaseSchema = cohortDatabaseSchema,
                                                 cohortTable = cohortTable,
                                                 featureSummaryTable = featureSummaryTable)
  if (nrow(featureProportions) > 0) {
    featureProportions$databaseId <- databaseId
    featureProportions <- enforceMinCellValue(featureProportions, "featureCount", minCellCount)
    featureProportions <- featureProportions[featureProportions$totalCount >= getMinimumSubjectCountForCharacterization(), ]
  }
  features <- formatCovariates(featureProportions)
  writeToCsv(features, file.path(exportFolder, "covariate.csv"))
  featureValues <- formatCovariateValues(featureProportions, counts, minCellCount, databaseId)
  featureValues <- featureValues[,c("cohortId", "covariateId", "mean", "sd", "databaseId", "featureCount")]
  names(featureValues) <- c("cohortId", "covariateId", "mean", "sd", "databaseId", "sumValue")
  writeToCsv(featureValues, file.path(exportFolder, "covariate_value.csv"))
  # Also keeping a raw output for debugging
  writeToCsv(featureProportions, file.path(exportFolder, "feature_proportions.csv"))

  # Cohort characterization ---------------------------------------------------------------
  # Subset the cohorts to the target/subgroup for running feature extraction
  # that are >= 140 per protocol
  featureExtractionCohorts <-  counts[counts$cohortSubjects >= getMinimumSubjectCountForCharacterization(), c("cohortId")]$cohortId
  ParallelLogger::logInfo("********************************************************************************************")
  ParallelLogger::logInfo("Bulk characterization of all cohorts for all time windows")
  ParallelLogger::logInfo("********************************************************************************************")
  createBulkCharacteristics(connection,
                            oracleTempSchema,
                            cohortIds = featureExtractionCohorts,
                            cdmDatabaseSchema,
                            cohortDatabaseSchema,
                            cohortTable)
  writeBulkCharacteristics(connection, oracleTempSchema, counts, minCellCount, databaseId, exportFolder)


  # Save package metadata ---------------------------------------------------------------
  ParallelLogger::logInfo("Saving package metadata")
  packageVersionNumber <- packageVersion(getThisPackageName())
  packageMetadata <- data.frame(packageId = getThisPackageName(),
                                packageVersion = packageVersionNumber,
                                executionDate = start,
                                params = as.character(jsonlite::toJSON(list(minCellCount = minCellCount,
                                                                            cohortIdsToExcludeFromExecution = cohortIdsToExcludeFromExecution,
                                                                            cohortIdsToExcludeFromResultsExport = cohortIdsToExcludeFromResultsExport,
                                                                            cohortGroups = cohortGroups))))
  writeToCsv(packageMetadata, file.path(exportFolder, "package.csv"))


  # Export to zip file -------------------------------------------------------------------------------
  exportResults(exportFolder, databaseId, cohortIdsToExcludeFromResultsExport)
  delta <- Sys.time() - start
  ParallelLogger::logInfo(paste("Running study took",
                                signif(delta, 3),
                                attr(delta, "units")))
}

#' @export
exportResults <- function(exportFolder, databaseId, cohortIdsToExcludeFromResultsExport = NULL) {
  filesWithCohortIds <- c("covariate_value.csv","cohort_count.csv")
  tempFolder <- NULL
  ParallelLogger::logInfo("Adding results to zip file")
  if (!is.null(cohortIdsToExcludeFromResultsExport)) {
    ParallelLogger::logInfo("Exclude cohort ids: ", paste(cohortIdsToExcludeFromResultsExport, collapse = ", "))
    # Copy files to temp location to remove the cohorts to remove
    tempFolder <- file.path(exportFolder, "temp")
    files <- list.files(exportFolder, pattern = ".*\\.csv$")
    if (!file.exists(tempFolder)) {
      dir.create(tempFolder)
    }
    file.copy(file.path(exportFolder, files), tempFolder)

    # Censor out the cohorts based on the IDs passed in
    for(i in 1:length(filesWithCohortIds)) {
      fileName <- file.path(tempFolder, filesWithCohortIds[i])
      fileContents <- readr::read_csv(fileName, col_types = readr::cols())
      fileContents <- fileContents[!(fileContents$cohort_id %in% cohortIdsToExcludeFromResultsExport),]
      readr::write_csv(fileContents, fileName)
    }
    
    # Zip the results and copy to the main export folder
    zipName <- zipResults(tempFolder, databaseId)
    file.copy(zipName, exportFolder)
    unlink(tempFolder, recursive = TRUE)
    zipName <- file.path(exportFolder, basename(zipName))
  } else {
    zipName <- zipResults(exportFolder, databaseId)
  }
  ParallelLogger::logInfo("Results are ready for sharing at:", zipName)
}

zipResults <- function(exportFolder, databaseId) {
  zipName <- file.path(exportFolder, paste0("Results_", databaseId, ".zip"))
  files <- list.files(exportFolder, pattern = ".*\\.csv$")
  oldWd <- setwd(exportFolder)
  on.exit(setwd(oldWd), add = TRUE)
  DatabaseConnector::createZipFile(zipFile = zipName, files = files)
  return(zipName)
}

# Per protocol, we will only characterize cohorts with
# >= 140 subjects to improve efficency
getMinimumSubjectCountForCharacterization <- function() {
  return(140)
}

getVocabularyInfo <- function(connection, cdmDatabaseSchema, oracleTempSchema) {
  sql <- "SELECT vocabulary_version FROM @cdm_database_schema.vocabulary WHERE vocabulary_id = 'None';"
  sql <- SqlRender::render(sql, cdm_database_schema = cdmDatabaseSchema)
  sql <- SqlRender::translate(sql, targetDialect = attr(connection, "dbms"), oracleTempSchema = oracleTempSchema)
  vocabInfo <- DatabaseConnector::querySql(connection, sql)
  return(vocabInfo[[1]])
}

getObservationPeriodDateRange <- function(connection, cdmDatabaseSchema, oracleTempSchema) {
  sql <- "SELECT MIN(observation_period_start_date) min_obs_period_date, MAX(observation_period_end_date) max_obs_period_date FROM @cdm_database_schema.observation_period;"
  sql <- SqlRender::render(sql, cdm_database_schema = cdmDatabaseSchema)
  sql <- SqlRender::translate(sql, targetDialect = attr(connection, "dbms"), oracleTempSchema = oracleTempSchema)
  op <- DatabaseConnector::querySql(connection, sql)
  names(op) <- SqlRender::snakeCaseToCamelCase(names(op))
  return(op)
}

#' @export
getUserSelectableCohortGroups <- function() {
  cohortGroups <- getCohortGroups()
  return(unlist(cohortGroups[cohortGroups$userCanSelect == TRUE, c("cohortGroup")], use.names = FALSE))
}

formatCovariates <- function(data) {
  # Drop covariates with mean = 0 after rounding to 4 digits:
  if (nrow(data) > 0) {
    data <- data[round(data$mean, 4) != 0, ]
    covariates <- unique(data[, c("covariateId", "covariateName", "analysisId")])
    colnames(covariates)[[3]] <- "covariateAnalysisId"
  } else {
    covariates <- list("covariateId" = "", "covariateName" = "", "covariateAnalysisId" = "")
  }
  return(covariates)
}

formatCovariateValues <- function(data, counts, minCellCount, databaseId) {
  data$covariateName <- NULL
  data$analysisId <- NULL
  if (nrow(data) > 0) {
    data$databaseId <- databaseId
    data <- merge(data, counts[, c("cohortId", "cohortEntries")])
    data <- enforceMinCellValue(data, "mean", minCellCount/data$cohortEntries)
    if (names(data) %in% c("sumValue")) {
      data <- enforceMinCellValue(data, "sumValue", minCellCount/data$cohortEntries)
    }
    if (names(data) %in% c("featureCount")) {
      data <- enforceMinCellValue(data, "featureCount", minCellCount/data$cohortEntries)
    }
    data$sd[data$mean < 0] <- NA
    data$cohortEntries <- NULL
    data$mean <- round(data$mean, 3)
    data$sd <- round(data$sd, 3)
  }
  return(data)  
}

loadCohortsFromPackage <- function(cohortIds) {
  packageName = getThisPackageName()
  cohorts <- getCohortsToCreate()
  cohorts$atlasId <- NULL
  if (!is.null(cohortIds)) {
    cohorts <- cohorts[cohorts$cohortId %in% cohortIds, ]
  }
  if ("atlasName" %in% colnames(cohorts)) {
    cohorts <- dplyr::rename(cohorts, cohortName = "name", cohortFullName = "name")
  } else {
    cohorts <- dplyr::rename(cohorts, cohortName = "name", cohortFullName = "fullName")
  }
  
  getSql <- function(name) {
    pathToSql <- system.file("sql", "sql_server", paste0(name, ".sql"), package = packageName, mustWork = TRUE)
    sql <- readChar(pathToSql, file.info(pathToSql)$size)
    return(sql)
  }
  cohorts$sql <- sapply(cohorts$cohortId, getSql)
  getJson <- function(name) {
    pathToJson <- system.file("cohorts", paste0(name, ".json"), package = packageName, mustWork = TRUE)
    json <- readChar(pathToJson, file.info(pathToJson)$size)
    return(json)
  }
  cohorts$json <- sapply(cohorts$cohortId, getJson)
  return(cohorts)
}

loadCohortsForExportFromPackage <- function(cohortIds) {
  cohorts <- getCohortsToCreate()
  cohorts$atlasId <- NULL
  if ("atlasName" %in% colnames(cohorts)) {
    cohorts$atlasName <- cohorts$name # Hack to always use the name field
    cohorts <- dplyr::rename(cohorts, cohortName = "name", cohortFullName = "atlasName")
  } else {
    cohorts <- dplyr::rename(cohorts, cohortName = "name", cohortFullName = "fullName")
  }
  
  # Get the stratified cohorts for the study
  # and join to the cohorts to create to get the names
  targetSubgroupXref <- getTargetSubgroupXref()
  targetSubgroupXref <- dplyr::rename(targetSubgroupXref, cohortName = "name")
  targetSubgroupXref$cohortFullName <- targetSubgroupXref$cohortName
  targetSubgroupXref$targetId <- NULL
  targetSubgroupXref$subgroupId <- NULL
  
  cols <- names(cohorts)
  cohorts <- rbind(cohorts, targetSubgroupXref[cols])
    
  if (!is.null(cohortIds)) {
    cohorts <- cohorts[cohorts$cohortId %in% cohortIds, ]
  }

  return(cohorts)
}

loadCohortsForExportWithChecksumFromPackage <- function(cohortIds) {
  packageName = getThisPackageName()
  subgroup <- getAllSubgroup()
  targetSubgroupXref <- getTargetSubgroupXref()
  cohorts <- loadCohortsForExportFromPackage(cohortIds)
  
  # Match up the cohorts in the study w/ the targetSubgroupXref and 
  # set the target/subgroup columns
  cohortsWithSubgroup <- dplyr::left_join(cohorts, targetSubgroupXref, by="cohortId")
  cohortsWithSubgroup <- dplyr::rename(cohortsWithSubgroup, cohortType = "cohortType.x")
  cohortsWithSubgroup$targetId <- ifelse(is.na(cohortsWithSubgroup$targetId), cohortsWithSubgroup$cohortId, cohortsWithSubgroup$targetId)
  cohortsWithSubgroup$subgroupId <- ifelse(is.na(cohortsWithSubgroup$subgroupId), 0, cohortsWithSubgroup$subgroupId)
  
  getChecksum <- function(targetId, subgroupId, cohortType) {
    pathToSql <- system.file("sql", "sql_server", paste0(targetId, ".sql"), package = packageName, mustWork = TRUE)
    sql <- readChar(pathToSql, file.info(pathToSql)$size)
    if (subgroupId > 0) {
      sqlFileName <- subgroup[subgroup$cohortId == subgroupId, c("generationScript")][[1]]
      if (is.na(sqlFileName)) {
        pathToSql <- system.file("sql", "sql_server", sqlFileName, package = packageName, mustWork = TRUE)
        subgroupSql <- readChar(pathToSql, file.info(pathToSql)$size)
        sql <- paste(sql, subgroupSql, cohortType)
      }
    }
    checksum <- computeChecksum(sql)
    return(checksum)
  }
  cohortsWithSubgroup$checksum <- mapply(getChecksum, 
                                       cohortsWithSubgroup$targetId, 
                                       subgroupId = cohortsWithSubgroup$subgroupId, 
                                       cohortType = cohortsWithSubgroup$cohortType)
  
  if (!is.null(cohortIds)) {
    cohortsWithSubgroup <- cohortsWithSubgroup[cohortsWithSubgroup$cohortId %in% cohortIds, ]
  }
  
  return(cohortsWithSubgroup)
}

writeToCsv <- function(data, fileName, incremental = FALSE, ...) {
  colnames(data) <- SqlRender::camelCaseToSnakeCase(colnames(data))
  if (incremental) {
    params <- list(...)
    names(params) <- SqlRender::camelCaseToSnakeCase(names(params))
    params$data = data
    params$fileName = fileName
    do.call(saveIncremental, params)
  } else {
    readr::write_csv(data, fileName)
  }
}

enforceMinCellValue <- function(data, fieldName, minValues, silent = FALSE) {
  toCensor <- !is.na(data[, fieldName]) & data[, fieldName] < minValues & data[, fieldName] != 0
  if (!silent) {
    percent <- round(100 * sum(toCensor)/nrow(data), 1)
    ParallelLogger::logInfo("   censoring ",
                            sum(toCensor),
                            " values (",
                            percent,
                            "%) from ",
                            fieldName,
                            " because value below minimum")
  }
  if (length(minValues) == 1) {
    data[toCensor, fieldName] <- -minValues
  } else {
    data[toCensor, fieldName] <- -minValues[toCensor]
  }
  return(data)
}

getCohortCounts <- function(connectionDetails = NULL,
                            connection = NULL,
                            cohortDatabaseSchema,
                            cohortTable = "cohort",
                            cohortIds = c()) {
  start <- Sys.time()
  
  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
  }
  sql <- SqlRender::loadRenderTranslateSql(sqlFilename = "CohortCounts.sql",
                                           packageName = getThisPackageName(),
                                           dbms = connection@dbms,
                                           cohort_database_schema = cohortDatabaseSchema,
                                           cohort_table = cohortTable,
                                           cohort_ids = cohortIds)
  counts <- DatabaseConnector::querySql(connection, sql, snakeCaseToCamelCase = TRUE)
  delta <- Sys.time() - start
  ParallelLogger::logInfo(paste("Counting cohorts took",
                                signif(delta, 3),
                                attr(delta, "units")))
  return(counts)
  
}

subsetToRequiredCohorts <- function(cohorts, task, incremental, recordKeepingFile) {
  if (incremental) {
    tasks <- getRequiredTasks(cohortId = cohorts$cohortId,
                              task = task,
                              checksum = cohorts$checksum,
                              recordKeepingFile = recordKeepingFile)
    return(cohorts[cohorts$cohortId %in% tasks$cohortId, ])
  } else {
    return(cohorts)
  }
}
