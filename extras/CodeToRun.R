library(HERACharacterization)

# Specify where the temporary files (used by the Andromeda package) will be created:
andromedaTempFolder <- if (Sys.getenv("ANDROMEDA_TEMP_FOLDER") == "") "~/andromedaTemp" else Sys.getenv("ANDROMEDA_TEMP_FOLDER")
options(andromedaTempFolder = andromedaTempFolder)

# Details for connecting to the server:
dbms <- Sys.getenv("DBMS")
user <- if (Sys.getenv("DB_USER") == "") NULL else Sys.getenv("DB_USER")
password <- if (Sys.getenv("DB_PASSWORD") == "") NULL else Sys.getenv("DB_PASSWORD")
server <- Sys.getenv("DB_SERVER")
extraSettings <- if (Sys.getenv("DB_EXTRA_SETTINGS") == "") NULL else Sys.getenv("DB_EXTRA_SETTINGS")
port <- Sys.getenv("DB_PORT")

# For Oracle: define a schema that can be used to emulate temp tables:
oracleTempSchema <- NULL

connectionDetails <- DatabaseConnector::createConnectionDetails(dbms = dbms,
                                                                server = server,
                                                                extraSettings = extraSettings,
                                                                user = user,
                                                                password = password,
                                                                port = port)


# Details specific to the database:
databaseId <- "MDCR"
databaseName <- "CDM_IBM_MDCD_V1703"
databaseDescription <- "The IBM(R) MarketScan(R) Medicare Supplemental Database (MDCR) represents the health services of approximately 10 million retirees in the United States with Medicare supplemental coverage through employer-sponsored plans. This database contains primarily fee-for-service plans and includes health insurance claims across the continuum of care (e.g. inpatient, outpatient and outpatient pharmacy)."

# Details for connecting to the CDM and storing the results
cdmDatabaseSchema <- "cdm_truven_mdcr_v1703"
cohortDatabaseSchema <- "scratch_asena5"
cohortTable <- paste0("AS_HERACharacterization_", databaseId)
featureSummaryTable <- paste0(cohortTable, "_smry")
minCellCount <- 5

# Set the folder for holding the study output
projectRootFolder <- "E:/HERACharacterization/Runs"
outputFolder <- file.path(projectRootFolder, databaseId)
if (!dir.exists(outputFolder)) {
  dir.create(outputFolder, recursive = TRUE)
}
setwd(outputFolder)

# Details for running the study.
cohortIdsToExcludeFromExecution <- c()
cohortIdsToExcludeFromResultsExport <- NULL

# Use this to run the study. The results will be stored in a zip file called
# 'Results_<databaseId>.zip in the outputFolder.
runStudy(connectionDetails = connectionDetails,
         cdmDatabaseSchema = cdmDatabaseSchema,
         cohortDatabaseSchema = cohortDatabaseSchema,
         cohortTable = cohortTable,
         featureSummaryTable = featureSummaryTable,
         oracleTempSchema = cohortDatabaseSchema,
         exportFolder = outputFolder,
         databaseId = databaseId,
         databaseName = databaseName,
         databaseDescription = databaseDescription,
         cohortIdsToExcludeFromExecution = cohortIdsToExcludeFromExecution,
         cohortIdsToExcludeFromResultsExport = cohortIdsToExcludeFromResultsExport,
         incremental = TRUE,
         minCellCount = minCellCount)


# Use the next set of commands to compress results and view the output.
# preMergeResultsFiles(outputFolder) 
# launchShinyApp(outputFolder)

# For uploading the results. You should have received the key file from the study coordinator:
keyFileName <- "E:/HERACharacterization/study-data-site-covid19.dat"
userName <- "study-data-site-covid19"

# When finished with reviewing the results, use the next command upload study results to OHDSI SFTP
# server: 
# uploadStudyResults(outputFolder, keyFileName, userName)
