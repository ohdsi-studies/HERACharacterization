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

#' Create cohort table(s)
#'
#' @description
#' This function creates an empty cohort table. Optionally, additional empty tables are created to
#' store statistics on the various inclusion criteria.
#'
#' @template Connection
#'
#' @template CohortTable
#'
#' @param createInclusionStatsTables   Create the four additional tables for storing inclusion rule
#'                                     statistics?
#' @param resultsDatabaseSchema        Schema name where the statistics tables reside. Note that for
#'                                     SQL Server, this should include both the database and schema
#'                                     name, for example 'scratch.dbo'.
#' @param cohortInclusionTable         Name of the inclusion table, one of the tables for storing
#'                                     inclusion rule statistics.
#' @param cohortInclusionResultTable   Name of the inclusion result table, one of the tables for
#'                                     storing inclusion rule statistics.
#' @param cohortInclusionStatsTable    Name of the inclusion stats table, one of the tables for storing
#'                                     inclusion rule statistics.
#' @param cohortSummaryStatsTable      Name of the summary stats table, one of the tables for storing
#'                                     inclusion rule statistics.
#'
#' @export
createCohortTable <- function(connectionDetails = NULL,
                              connection = NULL,
                              cohortDatabaseSchema,
                              cohortTable = "cohort",
                              createInclusionStatsTables = FALSE,
                              resultsDatabaseSchema = cohortDatabaseSchema,
                              cohortInclusionTable = paste0(cohortTable, "_inclusion"),
                              cohortInclusionResultTable = paste0(cohortTable, "_inclusion_result"),
                              cohortInclusionStatsTable = paste0(cohortTable, "_inclusion_stats"),
                              cohortSummaryStatsTable = paste0(cohortTable, "_summary_stats")) {
  start <- Sys.time()
  ParallelLogger::logInfo("Creating cohort table")
  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
  }
  sql <- SqlRender::loadRenderTranslateSql("CreateCohortTable.sql",
                                           packageName = getThisPackageName(),
                                           dbms = connection@dbms,
                                           cohort_database_schema = cohortDatabaseSchema,
                                           cohort_table = cohortTable)
  DatabaseConnector::executeSql(connection, sql, progressBar = FALSE, reportOverallTime = FALSE)
  ParallelLogger::logDebug("- Created table ", cohortDatabaseSchema, ".", cohortTable)
  
  if (createInclusionStatsTables) {
    ParallelLogger::logInfo("Creating inclusion rule statistics tables")
    sql <- SqlRender::loadRenderTranslateSql("CreateInclusionStatsTables.sql",
                                             packageName = getThisPackageName(),
                                             dbms = connectionDetails$dbms,
                                             cohort_database_schema = resultsDatabaseSchema,
                                             cohort_inclusion_table = cohortInclusionTable,
                                             cohort_inclusion_result_table = cohortInclusionResultTable,
                                             cohort_inclusion_stats_table = cohortInclusionStatsTable,
                                             cohort_summary_stats_table = cohortSummaryStatsTable)
    DatabaseConnector::executeSql(connection, sql, progressBar = FALSE, reportOverallTime = FALSE)
    ParallelLogger::logDebug("- Created table ", cohortDatabaseSchema, ".", cohortInclusionTable)
    ParallelLogger::logDebug("- Created table ",
                             cohortDatabaseSchema,
                             ".",
                             cohortInclusionResultTable)
    ParallelLogger::logDebug("- Created table ",
                             cohortDatabaseSchema,
                             ".",
                             cohortInclusionStatsTable)
    ParallelLogger::logDebug("- Created table ", cohortDatabaseSchema, ".", cohortSummaryStatsTable)
  }
  delta <- Sys.time() - start
  writeLines(paste("Creating cohort table took", signif(delta, 3), attr(delta, "units")))
}



#' Get statistics on cohort inclusion criteria
#'
#' @template Connection
#'
#' @param cohortTable                  Name of the cohort table. Used only to conveniently derive names
#'                                     of the four rule statistics tables.
#' @param cohortId                     The cohort definition ID used to reference the cohort in the
#'                                     cohort table.
#' @param simplify                     Simply output the attrition table?
#' @param resultsDatabaseSchema        Schema name where the statistics tables reside. Note that for
#'                                     SQL Server, this should include both the database and schema
#'                                     name, for example 'scratch.dbo'.
#' @param cohortInclusionTable         Name of the inclusion table, one of the tables for storing
#'                                     inclusion rule statistics.
#' @param cohortInclusionResultTable   Name of the inclusion result table, one of the tables for
#'                                     storing inclusion rule statistics.
#' @param cohortInclusionStatsTable    Name of the inclusion stats table, one of the tables for storing
#'                                     inclusion rule statistics.
#' @param cohortSummaryStatsTable      Name of the summary stats table, one of the tables for storing
#'                                     inclusion rule statistics.
#'
#' @return
#' If `simplify = TRUE`, this function returns a single data frame. Else a list of data frames is
#' returned.
#'
#' @export
getInclusionStatistics <- function(connectionDetails = NULL,
                                   connection = NULL,
                                   resultsDatabaseSchema,
                                   cohortId,
                                   simplify = TRUE,
                                   cohortTable = "cohort",
                                   cohortInclusionTable = paste0(cohortTable, "_inclusion"),
                                   cohortInclusionResultTable = paste0(cohortTable,
                                                                       "_inclusion_result"),
                                   cohortInclusionStatsTable = paste0(cohortTable,
                                                                      "_inclusion_stats"),
                                   cohortSummaryStatsTable = paste0(cohortTable,
                                                                    "_summary_stats")) {
  start <- Sys.time()
  ParallelLogger::logInfo("Fetching inclusion statistics for cohort with cohort_definition_id = ",
                          cohortId)
  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
  }
  fetchStats <- function(table) {
    ParallelLogger::logDebug("- Fetching data from ", table)
    sql <- "SELECT * FROM @database_schema.@table WHERE cohort_definition_id = @cohort_id"
    DatabaseConnector::renderTranslateQuerySql(sql = sql,
                                               connection = connection,
                                               snakeCaseToCamelCase = TRUE,
                                               database_schema = resultsDatabaseSchema,
                                               table = table,
                                               cohort_id = cohortId)
  }
  inclusion <- fetchStats(cohortInclusionTable)
  summaryStats <- fetchStats(cohortSummaryStatsTable)
  inclusionStats <- fetchStats(cohortInclusionStatsTable)
  inclusionResults <- fetchStats(cohortInclusionResultTable)
  result <- processInclusionStats(inclusion = inclusion,
                                  inclusionResults = inclusionResults,
                                  inclusionStats = inclusionStats,
                                  summaryStats = summaryStats,
                                  simplify = simplify)
  delta <- Sys.time() - start
  writeLines(paste("Fetching inclusion statistics took", signif(delta, 3), attr(delta, "units")))
  return(result)
}

#' Get inclusion criteria statistics from files
#'
#' @description
#' Gets inclusion criteria statistics from files, as stored when using the
#' \code{ROhdsiWebApi::insertCohortDefinitionSetInPackage} function with \code{generateStats = TRUE}.
#'
#' @param cohortId                    The cohort definition ID used to reference the cohort in the
#'                                    cohort table.
#' @param simplify                    Simply output the attrition table?
#' @param folder                      The path to the folder where the inclusion statistics are stored.
#' @param cohortInclusionFile         Name of the inclusion table, one of the tables for storing
#'                                    inclusion rule statistics.
#' @param cohortInclusionResultFile   Name of the inclusion result table, one of the tables for storing
#'                                    inclusion rule statistics.
#' @param cohortInclusionStatsFile    Name of the inclusion stats table, one of the tables for storing
#'                                    inclusion rule statistics.
#' @param cohortSummaryStatsFile      Name of the summary stats table, one of the tables for storing
#'                                    inclusion rule statistics.
#'
#' @return
#' If `simplify = TRUE`, this function returns a single data frame. Else a list of data frames is
#' returned.
#'
#' @export
getInclusionStatisticsFromFiles <- function(cohortId,
                                            folder,
                                            cohortInclusionFile = file.path(folder,
                                                                            "cohortInclusion.csv"),
                                            cohortInclusionResultFile = file.path(folder,
                                                                                  "cohortIncResult.csv"),
                                            cohortInclusionStatsFile = file.path(folder,
                                                                                 "cohortIncStats.csv"),
                                            cohortSummaryStatsFile = file.path(folder,
                                                                               "cohortSummaryStats.csv"),
                                            simplify = TRUE) {
  start <- Sys.time()
  ParallelLogger::logInfo("Fetching inclusion statistics for cohort with cohort_definition_id = ",
                          cohortId)
  
  fetchStats <- function(file) {
    ParallelLogger::logDebug("- Fetching data from ", file)
    stats <- readr::read_csv(file, col_types = readr::cols())
    stats <- stats[stats$cohortDefinitionId == cohortId, ]
    return(stats)
  }
  inclusion <- fetchStats(cohortInclusionFile)
  summaryStats <- fetchStats(cohortSummaryStatsFile)
  inclusionStats <- fetchStats(cohortInclusionStatsFile)
  inclusionResults <- fetchStats(cohortInclusionResultFile)
  result <- processInclusionStats(inclusion = inclusion,
                                  inclusionResults = inclusionResults,
                                  inclusionStats = inclusionStats,
                                  summaryStats = summaryStats,
                                  simplify = simplify)
  delta <- Sys.time() - start
  writeLines(paste("Fetching inclusion statistics took", signif(delta, 3), attr(delta, "units")))
  return(result)
}

processInclusionStats <- function(inclusion,
                                  inclusionResults,
                                  inclusionStats,
                                  summaryStats,
                                  simplify) {
  if (simplify) {
    if (nrow(inclusion) == 0 || nrow(inclusionStats) == 0) {
      return(data.frame())
    }
    result <- merge(unique(inclusion[, c("ruleSequence", "name")]),
                    inclusionStats[inclusionStats$modeId ==
                                     0, c("ruleSequence", "personCount", "gainCount", "personTotal")], )
    
    result$remain <- rep(0, nrow(result))
    inclusionResults <- inclusionResults[inclusionResults$modeId == 0, ]
    mask <- 0
    for (ruleId in 0:(nrow(result) - 1)) {
      mask <- bitwOr(mask, 2^ruleId)
      idx <- bitwAnd(inclusionResults$inclusionRuleMask, mask) == mask
      result$remain[result$ruleSequence == ruleId] <- sum(inclusionResults$personCount[idx])
    }
    colnames(result) <- c("ruleSequenceId",
                          "ruleName",
                          "meetSubjects",
                          "gainSubjects",
                          "totalSubjects",
                          "remainSubjects")
  } else {
    if (nrow(inclusion) == 0) {
      return(list())
    }
    result <- list(inclusion = inclusion,
                   inclusionResults = inclusionResults,
                   inclusionStats = inclusionStats,
                   summaryStats = summaryStats)
  }
  return(result)
}

#' Instantiate a set of cohort
#'
#' @description
#' This function instantiates a set of cohort in the cohort table, using definitions that are fetched from a WebApi interface.
#' Optionally, the inclusion rule statistics are computed and stored in the \code{inclusionStatisticsFolder}.
#'
#' @template Connection
#'
#' @template CohortTable
#'
#' @template OracleTempSchema
#'
#' @template CdmDatabaseSchema
#' 
#' @template CohortSetSpecs
#' 
#' @template CohortSetReference
#'
#' @param cohortIds                   Optionally, provide a subset of cohort IDs to restrict the
#'                                    construction to.
#' @param generateInclusionStats      Compute and store inclusion rule statistics?
#' @param inclusionStatisticsFolder   The folder where the inclusion rule statistics are stored. Can be
#'                                    left NULL if \code{generateInclusionStats = FALSE}.
#' @param createCohortTable           Create the cohort table? If \code{incremental = TRUE} and the table
#'                                    already exists this will be skipped.
#' @param incremental                 Create only cohorts that haven't been created before?
#' @param incrementalFolder           If \code{incremental = TRUE}, specify a folder where records are kept
#'                                    of which definition has been executed.
#'
#' @export
instantiateCohortSet <- function(connectionDetails = NULL,
                                 connection = NULL,
                                 cdmDatabaseSchema,
                                 oracleTempSchema = NULL,
                                 cohortDatabaseSchema = cdmDatabaseSchema,
                                 cohortTable = "cohort",
                                 cohortIds = NULL,
                                 generateInclusionStats = FALSE,
                                 inclusionStatisticsFolder = NULL,
                                 createCohortTable = FALSE,
                                 incremental = FALSE,
                                 incrementalFolder = NULL) {
  if (generateInclusionStats) {
    if (is.null(inclusionStatisticsFolder)) {
      stop("Must specify inclusionStatisticsFolder when generateInclusionStats = TRUE")
    }
    if (!file.exists(inclusionStatisticsFolder)) {
      dir.create(inclusionStatisticsFolder, recursive = TRUE)
    }
  }
  if (incremental) {
    if (is.null(incrementalFolder)) {
      stop("Must specify incrementalFolder when incremental = TRUE")
    }
    if (!file.exists(incrementalFolder)) {
      dir.create(incrementalFolder, recursive = TRUE)
    }
  }
  
  start <- Sys.time()
  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
  }
  if (createCohortTable) {
    needToCreate <- TRUE
    if (incremental) {
      tables <- DatabaseConnector::getTableNames(connection, cohortDatabaseSchema)
      if (toupper(cohortTable) %in% toupper(tables)) {
        ParallelLogger::logInfo("Cohort table already exists and in incremental mode, so not recreating table.")
        needToCreate <- FALSE
      }
    }
    if (needToCreate) {
      createCohortTable(connection = connection,
                        cohortDatabaseSchema = cohortDatabaseSchema,
                        cohortTable = cohortTable,
                        createInclusionStatsTables = FALSE)
    }
  }
  
  cohorts <- loadCohortsFromPackage(cohortIds = cohortIds)
  
  if (incremental) {
    cohorts$checksum <- computeChecksum(cohorts$sql)
    recordKeepingFile <- file.path(incrementalFolder, "InstantiatedCohorts.csv")
  }
  
  if (generateInclusionStats) {
    createTempInclusionStatsTables(connection, oracleTempSchema, cohorts) 
  }
  
  instantiatedCohortIds <- c() 
  for (i in 1:nrow(cohorts)) {
    if (!incremental || isTaskRequired(cohortId = cohorts$cohortId[i],
                                       checksum = cohorts$checksum[i],
                                       recordKeepingFile = recordKeepingFile)) {
      ParallelLogger::logInfo(i, "/", nrow(cohorts), ": Instantiation cohort ", cohorts$cohortFullName[i], "  (", cohorts$cohortId[i], ".sql)")
      sql <- cohorts$sql[i]
      
      if (generateInclusionStats) {
        sql <- SqlRender::render(sql,
                                 cdm_database_schema = cdmDatabaseSchema,
                                 vocabulary_database_schema = cdmDatabaseSchema,
                                 target_database_schema = cohortDatabaseSchema,
                                 target_cohort_table = cohortTable,
                                 target_cohort_id = cohorts$cohortId[i],
                                 results_database_schema.cohort_inclusion = "#cohort_inclusion",
                                 results_database_schema.cohort_inclusion_result = "#cohort_inc_result",
                                 results_database_schema.cohort_inclusion_stats = "#cohort_inc_stats",
                                 results_database_schema.cohort_summary_stats = "#cohort_summary_stats",
                                 warnOnMissingParameters = FALSE)
      } else {
        sql <- SqlRender::render(sql,
                                 cdm_database_schema = cdmDatabaseSchema,
                                 vocabulary_database_schema = cdmDatabaseSchema,
                                 target_database_schema = cohortDatabaseSchema,
                                 target_cohort_table = cohortTable,
                                 target_cohort_id = cohorts$cohortId[i],
                                 warnOnMissingParameters = FALSE)
      }
      sql <- SqlRender::translate(sql,
                                  targetDialect = connectionDetails$dbms,
                                  oracleTempSchema = oracleTempSchema)
      DatabaseConnector::executeSql(connection, sql)
      instantiatedCohortIds <- c(instantiatedCohortIds, cohorts$cohortId[i])
      if (incremental) {
        recordTasksDone(cohortId = cohorts$cohortId[i], checksum = cohorts$checksum[i], recordKeepingFile = recordKeepingFile)
      }
    }
  }
  
  if (generateInclusionStats) {
    saveAndDropTempInclusionStatsTables(connection = connection, 
                                        oracleTempSchema = oracleTempSchema, 
                                        inclusionStatisticsFolder = inclusionStatisticsFolder, 
                                        incremental = incremental, 
                                        cohortIds = instantiatedCohortIds)
  }
  
  delta <- Sys.time() - start
  writeLines(paste("Instantiating cohort set took", signif(delta, 3), attr(delta, "units")))
}

createTempInclusionStatsTables <- function(connection, oracleTempSchema, cohorts) {
  ParallelLogger::logInfo("Creating temporary inclusion statistics tables")
  pathToSql <- system.file( "inclusionStatsTables.sql", package = "ROhdsiWebApi", mustWork = TRUE)
  sql <- SqlRender::readSql(pathToSql)
  sql <- SqlRender::translate(sql, targetDialect = connection@dbms, oracleTempSchema = oracleTempSchema)
  DatabaseConnector::executeSql(connection, sql)
  
  inclusionRules <- data.frame()
  for (i in 1:nrow(cohorts)) {
    cohortDefinition <- jsonlite::fromJSON(cohorts$json[i])
    if (!is.null(cohortDefinition$InclusionRules)) {
      nrOfRules <- length(cohortDefinition$InclusionRules)
      if (nrOfRules > 0) {
        for (j in 1:nrOfRules) {
          inclusionRules <- rbind(inclusionRules, data.frame(cohortId = cohorts$cohortId[i],
                                                             ruleSequence = j - 1,
                                                             ruleName = cohortDefinition$InclusionRules[[j]]$name))
        }
      }
    }
  }
  inclusionRules <- merge(inclusionRules, data.frame(cohortId = cohorts$cohortId,
                                                     cohortName = cohorts$cohortFullName))
  inclusionRules <- data.frame(cohort_definition_id = inclusionRules$cohortId,
                               rule_sequence = inclusionRules$ruleSequence,
                               name = inclusionRules$ruleName)
  DatabaseConnector::insertTable(connection = connection,
                                 tableName = "#cohort_inclusion",
                                 data = inclusionRules,
                                 dropTableIfExists = FALSE,
                                 createTable = FALSE,
                                 tempTable = TRUE,
                                 oracleTempSchema = oracleTempSchema)
  
}

saveAndDropTempInclusionStatsTables <- function(connection, 
                                                oracleTempSchema, 
                                                inclusionStatisticsFolder, 
                                                incremental,
                                                cohortIds) {
  fetchStats <- function(table, fileName) {
    ParallelLogger::logDebug("- Fetching data from ", table)
    sql <- "SELECT * FROM @table"
    data <- DatabaseConnector::renderTranslateQuerySql(sql = sql,
                                                       connection = connection,
                                                       oracleTempSchema = oracleTempSchema,
                                                       snakeCaseToCamelCase = TRUE,
                                                       table = table)
    fullFileName <- file.path(inclusionStatisticsFolder, fileName)
    if (incremental) {
      saveIncremental(data, fullFileName, cohortDefinitionId = cohortIds)
    } else {
      readr::write_csv(data, fullFileName)
    }
  }
  fetchStats("#cohort_inclusion", "cohortInclusion.csv")
  fetchStats("#cohort_inc_result", "cohortIncResult.csv")
  fetchStats("#cohort_inc_stats", "cohortIncStats.csv")
  fetchStats("#cohort_summary_stats", "cohortSummaryStats.csv")
  
  sql <- "TRUNCATE TABLE #cohort_inclusion; 
    DROP TABLE #cohort_inclusion;
    
    TRUNCATE TABLE #cohort_inc_result; 
    DROP TABLE #cohort_inc_result;
    
    TRUNCATE TABLE #cohort_inc_stats; 
    DROP TABLE #cohort_inc_stats;
    
    TRUNCATE TABLE #cohort_summary_stats; 
    DROP TABLE #cohort_summary_stats;"
  DatabaseConnector::renderTranslateExecuteSql(connection = connection,
                                               sql = sql,
                                               progressBar = FALSE,
                                               reportOverallTime = FALSE,
                                               oracleTempSchema = oracleTempSchema)
}

#' Copy the cohorts from the cohortStagingTable to the cohortTable and censor based on the minCellCount
#'
#' @description
#' This function will copy the cohorts from the cohortStagingTable to the cohortTable that have a count
#' of subjects greater than the minCellCount. 
#'
#' @template Connection
#'
#' @template CohortStagingTable
#'
#' @template CohortTable
#' 
#' @param targetIds                    A vector containing the target cohort IDs consider when copying to the main table
#'                                     This will copy over any subgroups associated with these target cohort IDs
#' @param minCellCount                 The minimum count of patients required when copying a cohor to the main table. Cohorts
#'                                     at or below this threshold are excluded
#' @template OracleTempSchema
#'
#' @export
copyAndCensorCohorts <- function(connection,
                                 cohortDatabaseSchema,
                                 cohortStagingTable,
                                 cohortTable,
                                 targetIds, 
                                 minCellCount,
                                 oracleTempSchema) {
  packageName = getThisPackageName()
  # Create the SQL for the temp table to hold the cohorts to be stratified
  targetSubgroupXref <- getTargetSubgroupXref()
  # Get the subgroup to create for the targets selected
  tsXrefSubset <- targetSubgroupXref[targetSubgroupXref$targetId %in% targetIds, ]
  # Create the SQL for the temp table to hold the cohorts to be stratified
  tsXrefTempTableSql <- cohortSubgroupXrefTempTableSql(connection, tsXrefSubset, oracleTempSchema)

  sql <- SqlRender::loadRenderTranslateSql(dbms = attr(connection, "dbms"),
                                           sqlFilename = "CopyAndCensorCohorts.sql",
                                           packageName = packageName,
                                           oracleTempSchema = oracleTempSchema,
                                           warnOnMissingParameters = TRUE,
                                           cohort_database_schema = cohortDatabaseSchema,
                                           cohort_staging_table = cohortStagingTable,
                                           cohort_table = cohortTable,
                                           min_cell_count = minCellCount,
                                           target_subgroup_xref_table_create = tsXrefTempTableSql$create,
                                           target_subgroup_xref_table_drop = tsXrefTempTableSql$drop)
  
  ParallelLogger::logInfo("Copy and censor cohorts to main analysis table")
  DatabaseConnector::executeSql(connection, sql)
}


createDerivedCohorts <- function(connection,
                                 cdmDatabaseSchema,
                                 cohortDatabaseSchema,
                                 cohortTable,
                                 oracleTempSchema) {
  
  packageName = getThisPackageName()
  # Create the SQL for the temp table to hold the derived cohort mapping
  deriveTargetXref <- getCohortsToDeriveTarget()
  # Create the SQL for the temp table to hold the cohorts to be stratified
  dtXrefTempTableSql <- deriveCohortTempTableSql(connection, deriveTargetXref, oracleTempSchema)
  
  sql <- SqlRender::loadRenderTranslateSql(dbms = attr(connection, "dbms"),
                                           sqlFilename = "CreateDerivedCohorts.sql",
                                           packageName = packageName,
                                           oracleTempSchema = oracleTempSchema,
                                           warnOnMissingParameters = TRUE,
                                           cdm_database_schema = cdmDatabaseSchema,
                                           cohort_database_schema = cohortDatabaseSchema,
                                           cohort_table = cohortTable,
                                           derived_cohort_table_create = dtXrefTempTableSql$create,
                                           derived_cohort_table_drop = dtXrefTempTableSql$drop)
  
  ParallelLogger::logInfo("Derive cohorts from targets")
  DatabaseConnector::executeSql(connection, sql)
}

deriveCohortTempTableSql <- function(connection, deriveTargetXref, oracleTempSchema) {
  sql <- "WITH data AS (
            @unions
          ) 
          SELECT target_id, cohort_id
          INTO #DERIVED_COHORT_XREF
          FROM data;"
  unions <- "";
  for(i in 1:nrow(deriveTargetXref)) {
    stmt <- paste0("SELECT ", deriveTargetXref$targetId[i], " target_id, ", 
                   deriveTargetXref$cohortId[i], " cohort_id")
    unions <- paste(unions, stmt, sep="\n")
    if (i < nrow(deriveTargetXref)) {
      unions <- paste(unions, "UNION ALL", sep="\n")
    }
  }
  
  sql <- SqlRender::render(sql, unions = unions)
  sql <- SqlRender::translate(sql = sql, 
                              targetDialect = attr(connection, "dbms"),
                              oracleTempSchema = oracleTempSchema)
  
  dropSql <- "TRUNCATE TABLE #DERIVED_COHORT_XREF;\nDROP TABLE #DERIVED_COHORT_XREF;\n\n"
  dropSql <- SqlRender::translate(sql = dropSql, 
                                  targetDialect = attr(connection, "dbms"),
                                  oracleTempSchema = oracleTempSchema)
  return(list(create = sql, drop = dropSql))
}