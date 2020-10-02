#' Create bulk subgroup cohorts
#'
#' @description
#' This function wraps together 2 calls: @insertRef{createBulkSubgroupFromFile} and @insertRef{createBulkSubgroupFromCohorts}.
#' This function assumes that cohorts are already generated and located in the cohortDatabaseSchema.cohortStagingTable
#'
#' @template Connection
#' 
#' @template CdmDatabaseSchema
#'
#' @template cohortTable
#' 
#' @param targetIds                    A vector containing the target IDs to subgroup
#' 
#' @template OracleTempSchema
#'
#' @export
createBulkSubgroup <- function(connection,
                             cdmDatabaseSchema,
                             cohortDatabaseSchema,
                             cohortTable,
                             targetIds, 
                             oracleTempSchema) {
  
  # Create the bulk subgroup from the CSV
  createBulkSubgroupFromFile(connection,
                           cdmDatabaseSchema,
                           cohortDatabaseSchema,
                           cohortStagingTable = cohortTable,
                           targetIds, 
                           oracleTempSchema)
  
  # Create the bulk subgroup from the cohorts of interest
  createBulkSubgroupFromCohorts(connection,
                               cohortDatabaseSchema,
                               cohortStagingTable = cohortTable,
                               targetIds, 
                               oracleTempSchema)
  
}

#' Create bulk subgroups from settings file
#'
#' @description
#' This function creates subgroups of the target cohorts based on the settings file
#' located in inst/settings/BulkSubgroup.csv
#' 
#' This function assumes that cohorts are already generated and located in the cohortDatabaseSchema.cohortStagingTable
#'
#' @template Connection
#' 
#' @template CdmDatabaseSchema
#'
#' @template CohortStagingTable
#' 
#' @param targetIds                    A vector containing the target cohort IDs to subgroup
#' 
#' @template OracleTempSchema
#'
#' @export
createBulkSubgroupFromFile <- function(connection,
                                     cdmDatabaseSchema,
                                     cohortDatabaseSchema,
                                     cohortStagingTable,
                                     targetIds, 
                                     oracleTempSchema) {
  packageName <- getThisPackageName()
  bulkSubgroupToCreate <- getBulkSubgroup()
  targetSubgroupXref <- getTargetSubgroupXref()
  
  if (nrow(bulkSubgroupToCreate) > 0) {
    for (i in 1:nrow(bulkSubgroupToCreate)) {
      subgroupId <- bulkSubgroupToCreate$cohortId[i]
      # Get the subgroup to create for the targets selected
      tsXrefSubset <- targetSubgroupXref[targetSubgroupXref$targetId %in% targetIds & targetSubgroupXref$subgroupId == subgroupId, ]
      # Create the SQL for the temp table to hold the cohorts to be stratified
      tsXrefTempTableSql <- cohortSubgroupXrefTempTableSql(connection, tsXrefSubset, oracleTempSchema)
      # Execute the SQL to create the stratified cohorts
      ParallelLogger::logInfo(paste0("Subgroup by ", bulkSubgroupToCreate$name[i]))
      sql <- SqlRender::loadRenderTranslateSql(dbms = attr(connection, "dbms"),
                                               sqlFilename = bulkSubgroupToCreate$generationScript[i], 
                                               packageName = packageName,
                                               warnOnMissingParameters = FALSE,
                                               oracleTempSchema = oracleTempSchema,
                                               cdm_database_schema = cdmDatabaseSchema,
                                               cohort_database_schema = cohortDatabaseSchema,
                                               cohort_staging_table = cohortStagingTable,
                                               lb_operator = bulkSubgroupToCreate$lbOperator[i],
                                               lb_subgroup_value = bulkSubgroupToCreate$lbSubgroupValue[i],
                                               ub_operator = bulkSubgroupToCreate$ubOperator[i],
                                               ub_subgroup_value = bulkSubgroupToCreate$ubSubgroupValue[i],
                                               target_subgroup_xref_table_create = tsXrefTempTableSql$create,
                                               target_subgroup_xref_table_drop = tsXrefTempTableSql$drop)
      DatabaseConnector::executeSql(connection, sql)
      #write(sql,paste0(i, ".sql"))
    }    
  }

}

#' Create subgroup cohorts by finding the intersection of target cohorts with subgroup cohorts
#'
#' @description
#' This function creates subgroups of the target cohorts based on combinations defined in
#' inst/settings/targetSubgroupXref.csv
#' 
#' This function assumes that cohorts are already generated and located in the cohortDatabaseSchema.cohortStagingTable
#'
#' @template Connection
#' 
#' @template CohortStagingTable
#' 
#' @param targetIds                    A vector containing the target IDs to subgroup
#' 
#' @template OracleTempSchema
#'
#' @export
createBulkSubgroupFromCohorts <- function(connection,
                                        cohortDatabaseSchema,
                                        cohortStagingTable,
                                        targetIds, 
                                        oracleTempSchema) {
  packageName <- getThisPackageName()
  subgroupCohorts <- getCohortBasedSubgroup()
  targetSubgroupXref <- getTargetSubgroupXref()
  
  # Get the subgroup to create for the targets selected
  tsXrefSubset <- targetSubgroupXref[targetSubgroupXref$targetId %in% targetIds & targetSubgroupXref$subgroupId %in% subgroupCohorts$cohortId, ]
  # Create the SQL for the temp table to hold the cohorts to be stratified
  tsXrefTempTableSql <- cohortSubgroupXrefTempTableSql(connection, tsXrefSubset, oracleTempSchema)
  
  
  sql <- SqlRender::loadRenderTranslateSql(dbms = attr(connection, "dbms"),
                                           sqlFilename = "subgroup/SubgroupByCohort.sql",
                                           packageName = packageName,
                                           oracleTempSchema = oracleTempSchema,
                                           warnOnMissingParameters = TRUE,
                                           cohort_database_schema = cohortDatabaseSchema,
                                           cohort_staging_table = cohortStagingTable,
                                           target_subgroup_xref_table_create = tsXrefTempTableSql$create,
                                           target_subgroup_xref_table_drop = tsXrefTempTableSql$drop)
  
  ParallelLogger::logInfo("Subgroup by cohorts")
  DatabaseConnector::executeSql(connection, sql)
}

cohortSubgroupXrefTempTableSql <- function(connection, targetSubgroupXref, oracleTempSchema) {
  sql <- "WITH data AS (
            @unions
          ) 
          SELECT target_id,subgroup_id,cohort_id,cohort_type
          INTO #TARGET_SUBGROUP_XREF 
          FROM data;"
  unions <- "";
  for(i in 1:nrow(targetSubgroupXref)) {
    stmt <- paste0("SELECT ", targetSubgroupXref$targetId[i], " target_id, ", 
                   targetSubgroupXref$subgroupId[i], " subgroup_id, ", 
                   targetSubgroupXref$cohortId[i], " cohort_id, ",
                   "'", targetSubgroupXref$cohortType[i], "' cohort_type")
    unions <- paste(unions, stmt, sep="\n")
    if (i < nrow(targetSubgroupXref)) {
      unions <- paste(unions, "UNION ALL", sep="\n")
    }
  }
  
  sql <- SqlRender::render(sql, unions = unions)
  sql <- SqlRender::translate(sql = sql, 
                              targetDialect = attr(connection, "dbms"),
                              oracleTempSchema = oracleTempSchema)
  
  dropSql <- "TRUNCATE TABLE #TARGET_SUBGROUP_XREF;\nDROP TABLE #TARGET_SUBGROUP_XREF;\n\n"
  dropSql <- SqlRender::translate(sql = dropSql, 
                                  targetDialect = attr(connection, "dbms"),
                                  oracleTempSchema = oracleTempSchema)
  return(list(create = sql, drop = dropSql))
}

serializeBulkSubgroupName <- function(bulkSubgroupToCreate) {
  return(paste(bulkSubgroupToCreate$generationScript, bulkSubgroupToCreate$name, bulkSubgroupToCreate$parameterValue, sep = "|"))
}

