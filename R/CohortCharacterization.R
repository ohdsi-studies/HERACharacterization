# Copyright 2020 Observational Health Data Sciences and Informatics
#
# This file is part of ScyllaCharacterization
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

#' Create characterization of a cohort
#'
#' @description
#' Computes features using all drugs, conditions, procedures, etc. observed on or prior to the cohort
#' index date.
#'
#' @template Connection
#'
#' @template CdmDatabaseSchema
#'
#' @template OracleTempSchema
#'
#' @template CohortTable
#'
#' @param cohortId            The cohort definition ID used to reference the cohort in the cohort
#'                            table.
#' @param covariateSettings   Either an object of type \code{covariateSettings} as created using one of
#'                            the createCovariate functions in the FeatureExtraction package, or a list
#'                            of such objects.
#'
#' @return
#' A data frame with cohort characteristics.
#'
#' @export
getCohortCharacteristics <- function(connectionDetails = NULL,
                                     connection = NULL,
                                     cdmDatabaseSchema,
                                     oracleTempSchema = NULL,
                                     cohortDatabaseSchema = cdmDatabaseSchema,
                                     cohortTable = "cohort",
                                     cohortId,
                                     covariateSettings = FeatureExtraction::createDefaultCovariateSettings()) {
  if (!file.exists(getOption("andromedaTempFolder"))) {
    stop("This function uses Andromeda, but the andromedaTempFolder '",
         getOption("andromedaTempFolder"),
         "' does not exist. Either create it, or set andromedaTempFolder to another location using options(andromedaTempFolder = \"<path>\")")
  }

  start <- Sys.time()

  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
  }

  if (!checkIfCohortInstantiated(connection = connection,
                                 cohortDatabaseSchema = cohortDatabaseSchema,
                                 cohortTable = cohortTable,
                                 cohortId = cohortId)) {
    warning("Cohort with ID ", cohortId, " appears to be empty. Was it instantiated?")
    delta <- Sys.time() - start
    ParallelLogger::logInfo(paste("Cohort characterization took",
                                  signif(delta, 3),
                                  attr(delta, "units")))
    return(data.frame())
  }

  data <- FeatureExtraction::getDbCovariateData(connection = connection,
                                                oracleTempSchema = oracleTempSchema,
                                                cdmDatabaseSchema = cdmDatabaseSchema,
                                                cohortDatabaseSchema = cohortDatabaseSchema,
                                                cohortTable = cohortTable,
                                                cohortId = cohortId,
                                                covariateSettings = covariateSettings,
                                                aggregated = TRUE)
  result <- data.frame()
  if (!is.null(data$covariates)) {
    counts <- data$covariates %>% dplyr::select(.data$sumValue) %>% dplyr::pull()
    n <- attr(data, "metaData")$populationSize
    binaryCovs <- data$covariates %>% 
      dplyr::select(.data$covariateId, .data$averageValue, .data$sumValue) %>% 
      dplyr::rename(mean = .data$averageValue) %>% 
      dplyr::collect()
    binaryCovs$sd <- sqrt((n * counts + counts)/(n^2))
    result <- rbind(result, binaryCovs)
  }
  if (!is.null(data$covariatesContinuous)) {
    continuousCovs <- data$covariatesContinuous %>% 
      dplyr::select(.data$covariateId, .data$averageValue, .data$standardDeviation) %>% 
      dplyr::rename(mean = .data$averageValue, sd = .data$standardDeviation) %>% 
      dplyr::collect()
    result <- rbind(result, continuousCovs)
  }
  if (nrow(result) > 0) {
    result <- merge(result, data$covariateRef %>% dplyr::collect())
    result$conceptId <- NULL
  }
  attr(result, "cohortSize") <- attr(data, "metaData")$populationSize
  delta <- Sys.time() - start
  ParallelLogger::logInfo(paste("Cohort characterization took",
                                signif(delta, 3),
                                attr(delta, "units")))
  return(result)
}

checkIfCohortInstantiated <- function(connection, cohortDatabaseSchema, cohortTable, cohortId) {
  sql <- "SELECT COUNT(*) FROM @cohort_database_schema.@cohort_table WHERE cohort_definition_id = @cohort_id;"
  count <- DatabaseConnector::renderTranslateQuerySql(connection = connection,
                                                      sql,
                                                      cohort_database_schema = cohortDatabaseSchema,
                                                      cohort_table = cohortTable,
                                                      cohort_id = cohortId)
  return(count > 0)
}


#' Create cohort characteristics in batches
#' 
#' @description 
#' In the case where creating bulk characteristics does not work,
#' we are providing a mechanism for generating the characteristics
#' in a batch manner
#' 
batchCreateCohortCharacteristics <- function(connection,
                                             oracleTempSchema,
                                             batchSize,
                                             cohortIds,
                                             cdmDatabaseSchema,
                                             cohortDatabaseSchema,
                                             cohortTable,
                                             counts,
                                             minCellCount,
                                             databaseId,
                                             exportFolder) {
  
  for (start in seq(1, length(cohortIds), by = batchSize)) {
    end <- min(start + batchSize - 1, length(cohortIds))
    if (length(cohortIds) > batchSize) {
      ParallelLogger::logInfo(sprintf("Batch characterization - processing cohorts %s through %s", start, end))
    }
    createBulkCharacteristics(connection = connection,
                              oracleTempSchema = oracleTempSchema,
                              cohortIds = cohortIds[start:end],
                              cdmDatabaseSchema = cdmDatabaseSchema,
                              cohortDatabaseSchema = cohortDatabaseSchema,
                              cohortTable = cohortTable)
    writeBulkCharacteristics(connection = connection, 
                             oracleTempSchema = oracleTempSchema, 
                             counts = counts, 
                             minCellCount = minCellCount, 
                             databaseId = databaseId, 
                             exportFolder = exportFolder)
  }
}

#' Create cohort characteristics in bulk
#'
#' @description
#' This function will perform the same actions as the main RunStudy.R::runStudy()
#' function but in a single SQL operation. 
#'
createBulkCharacteristics <- function(connection, 
                                      oracleTempSchema, 
                                      cohortIds, 
                                      cdmDatabaseSchema, 
                                      cohortDatabaseSchema, 
                                      cohortTable) {
  packageName <- getThisPackageName()

  # Subset to the cohorts selected
  cohortSubsetSql <- cohortSubsetTempTableSql(connection, cohortIds, oracleTempSchema)

  # Get the time windows
  featureTimeWindows <- getFeatureTimeWindows()
  featureTimeWindowTempTableSql <- featureWindowsTempTableSql(connection, featureTimeWindows, oracleTempSchema)
  
  # Generate the bulk creation script
  sql <- SqlRender::loadRenderTranslateSql(dbms = attr(connection, "dbms"),
                                           sqlFilename = "BulkFeatureExtraction.sql",
                                           packageName = packageName,
                                           oracleTempSchema = oracleTempSchema,
                                           warnOnMissingParameters = TRUE,
                                           cohort_subset_table_create = cohortSubsetSql$create,
                                           cohort_subset_table_drop = cohortSubsetSql$drop,
                                           feature_time_window_table_create = featureTimeWindowTempTableSql$create,
                                           feature_time_window_table_drop = featureTimeWindowTempTableSql$drop,
                                           cdm_database_schema = cdmDatabaseSchema,
                                           cohort_database_schema = cohortDatabaseSchema,
                                           cohort_table = cohortTable)
  DatabaseConnector::executeSql(connection = connection, sql = sql)  
}

#' Write cohort characteristics in bulk to the file system
#'
#' @description
#' This function will retrieve the results from the temp tables created
#' in createBulkCharacteristics
#'
writeBulkCharacteristics <- function(connection, oracleTempSchema, counts, minCellCount, databaseId, exportFolder) {
  sql <- "SELECT ar.cohort_id, ar.covariate_id, sum_value, ar.mean, ar.sd, cr.covariate_name, cr.analysis_id
          FROM #analysis_results ar
          INNER JOIN #cov_ref cr ON ar.covariate_id = cr.covariate_id
          ;"
  sql <- SqlRender::translate(sql = sql,
                              targetDialect = attr(connection, "dbms"), 
                              oracleTempSchema = oracleTempSchema)
  data <- DatabaseConnector::querySql(connection, sql = sql)
  names(data) <- SqlRender::snakeCaseToCamelCase(colnames(data))
  covariates <- formatCovariates(data)
  writeToCsv(covariates, file.path(exportFolder, "covariate.csv"), incremental = TRUE, covariateId = covariates$covariateId)
  data <- formatCovariateValues(data, counts, minCellCount, databaseId)
  writeToCsv(data, file.path(exportFolder, "covariate_value.csv"), incremental = TRUE, cohortId = data$cohortId, data$covariateId)
}

cohortSubsetTempTableSql <- function(connection, cohortIds, oracleTempSchema) {
  sql <- "WITH data AS (
            @unions
          ) 
          SELECT cohort_id
          INTO #cohort_subset
          FROM data;"
  unions <- "";
  unions <- "";
  for(i in 1:length(cohortIds)) {
    stmt <- paste0("SELECT ", cohortIds[i], " cohort_id")
    unions <- paste(unions, stmt, sep="\n")
    if (i < length(cohortIds)) {
      unions <- paste(unions, "UNION ALL", sep="\n")
    }
  }
  sql <- SqlRender::render(sql, unions = unions)
  sql <- SqlRender::translate(sql = sql, 
                              targetDialect = attr(connection, "dbms"),
                              oracleTempSchema = oracleTempSchema)
  
  dropSql <- "TRUNCATE TABLE #cohort_subset;\nDROP TABLE #cohort_subset;\n\n"
  dropSql <- SqlRender::translate(sql = dropSql, 
                                  targetDialect = attr(connection, "dbms"),
                                  oracleTempSchema = oracleTempSchema)
  return(list(create = sql, drop = dropSql))
}

