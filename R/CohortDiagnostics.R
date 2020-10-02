#' @export
runCohortDiagnostics <- function(connectionDetails = NULL,
                                 connection = NULL,
                                 cdmDatabaseSchema,
                                 cohortDatabaseSchema = cdmDatabaseSchema,
                                 cohortTable = "cohort",
                                 oracleTempSchema = cohortDatabaseSchema,
                                 cohortIdsToExcludeFromExecution = c(),
                                 exportFolder,
                                 databaseId = "Unknown",
                                 databaseName = "Unknown",
                                 databaseDescription = "Unknown",
                                 incrementalFolder = file.path(exportFolder, "RecordKeeping"),
                                 minCellCount = 5) {
  # NOTE: The exportFolder is the root folder where the
  # study results will live. The diagnostics will be written
  # to a subfolder called "diagnostics". Both the diagnostics
  # and main study code (RunStudy.R) will share the same
  # RecordKeeping folder so that we can ensure that cohorts
  # are only created one time.
  diagnosticOutputFolder <- file.path(exportFolder, "diagnostics")
  if (!file.exists(diagnosticOutputFolder)) {
    dir.create(diagnosticOutputFolder, recursive = TRUE)
  }

  if (!is.null(getOption("andromedaTempFolder")) && !file.exists(getOption("andromedaTempFolder"))) {
    warning("andromedaTempFolder '", getOption("andromedaTempFolder"), "' not found. Attempting to create folder")
    dir.create(getOption("andromedaTempFolder"), recursive = TRUE)
  }
  
  ParallelLogger::addDefaultFileLogger(file.path(diagnosticOutputFolder, "cohortDiagnosticsLog.txt"))
  ParallelLogger::addDefaultErrorReportLogger(file.path(diagnosticOutputFolder, "HERACharacterizationErrorReportR.txt"))
  on.exit(ParallelLogger::unregisterLogger("DEFAULT_FILE_LOGGER", silent = TRUE))
  on.exit(ParallelLogger::unregisterLogger("DEFAULT_ERRORREPORT_LOGGER", silent = TRUE), add = TRUE)
  
  # Write out the system information
  ParallelLogger::logInfo(.systemInfo())
  
  if (is.null(connection)) {
    connection <- DatabaseConnector::connect(connectionDetails)
    on.exit(DatabaseConnector::disconnect(connection))
  }

  # Create cohorts -----------------------------
  cohorts <- getCohortsToCreate()
  cohorts <- cohorts[!(cohorts$cohortId %in% cohortIdsToExcludeFromExecution) & cohorts$atlasId > 0, ] # cohorts$atlasId > 0 is used to avoid those cohorts that use custom SQL identified with an atlasId == -1
  ParallelLogger::logInfo("Creating cohorts in incremental mode")
  instantiateCohortSet(connectionDetails = connectionDetails,
                       connection = connection,
                       cdmDatabaseSchema = cdmDatabaseSchema,
                       oracleTempSchema = oracleTempSchema,
                       cohortDatabaseSchema = cohortDatabaseSchema,
                       cohortTable = cohortTable,
                       cohortIds = cohorts$cohortId,
                       createCohortTable = TRUE,
                       generateInclusionStats = FALSE,
                       incremental = TRUE,
                       incrementalFolder = incrementalFolder,
                       inclusionStatisticsFolder = diagnosticOutputFolder)

  # Run diagnostics -----------------------------
  ParallelLogger::logInfo("Running cohort diagnostics")
  CohortDiagnostics::runCohortDiagnostics(packageName = getThisPackageName(),
                                          cohortToCreateFile = "settings/diagnostics/CohortsToCreate.csv",
                                          connection = connection,
                                          connectionDetails = connectionDetails,
                                          cdmDatabaseSchema = cdmDatabaseSchema,
                                          oracleTempSchema = oracleTempSchema,
                                          cohortDatabaseSchema = cohortDatabaseSchema,
                                          cohortTable = cohortTable,
                                          cohortIds = cohorts$cohortId,
                                          inclusionStatisticsFolder = diagnosticOutputFolder,
                                          exportFolder = diagnosticOutputFolder,
                                          databaseId = databaseId,
                                          databaseName = databaseName,
                                          databaseDescription = databaseDescription,
                                          runInclusionStatistics = FALSE,
                                          runIncludedSourceConcepts = TRUE,
                                          runOrphanConcepts = TRUE,
                                          runTimeDistributions = TRUE,
                                          runBreakdownIndexEvents = TRUE,
                                          runIncidenceRate = TRUE,
                                          runCohortOverlap = FALSE,
                                          runCohortCharacterization = FALSE,
                                          runTemporalCohortCharacterization = FALSE,
                                          minCellCount = minCellCount,
                                          incremental = TRUE,
                                          incrementalFolder = incrementalFolder)

  # Rename the file with diagnostics results from "Results_*.zip" to "Results_diagnostics_*.zip"
  diagnosticsZipFileList <- list.files(diagnosticOutputFolder, "^Results_.*.zip$", full.names = TRUE, recursive = TRUE)
  if (length(diagnosticsZipFileList) != 1) {
    stop("Cannot find diagnostics results file.")
  }
  diagnosticsZipFile <- diagnosticsZipFileList[1]
  baseDiagFileName <- basename(diagnosticsZipFile)
  newDiagFileName <- stringr::str_replace(baseDiagFileName, "Results_", "Results_diagnostics_")
  bundledResultsLocation <- file.path(diagnosticOutputFolder, newDiagFileName)
  file.rename(diagnosticsZipFile, bundledResultsLocation)
  ParallelLogger::logInfo(paste("Cohort diagnostics are bundled for sharing at: ", bundledResultsLocation))
}

