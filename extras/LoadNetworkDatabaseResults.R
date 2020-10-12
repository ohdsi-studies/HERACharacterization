# Remove scientific notation
options(scipen=999)

# Connect to the network database
networkDbConnectionDetails <-
  DatabaseConnector::createConnectionDetails(
    dbms = Sys.getenv("NETWORK_DBMS"),
    server = Sys.getenv("NETWORK_DB_SERVER"),
    user = Sys.getenv("NETWORK_DB_USER"),
    password = Sys.getenv("NETWORK_DB_PASSWORD"),
    port = Sys.getenv("NETWORK_DB_PORT")
  )
networkSchema <- Sys.getenv("NETWORK_SCHEMA")

networkDbConnection <- DatabaseConnector::connect(networkDbConnectionDetails)
#on.exit(DatabaseConnector::disconnect(networkDbConnection))

#Initialize the network results schema
initNetworkResultsSchemaSql <- SqlRender::loadRenderTranslateSql(dbms = attr(networkDbConnection, "dbms"),
                                                                 sqlFilename = "networkResultsSchema.sql",
                                                                 packageName = "HERACharacterization",
                                                                 warnOnMissingParameters = TRUE,
                                                                 network_results_schema = networkSchema)
DatabaseConnector::executeSql(networkDbConnection, 
                              initNetworkResultsSchemaSql)


# Insert the results ------------------
insertResultsTable <- function(conn, networkSchema, tblName, obj) {
  fullyQualifiedTableName <- paste(networkSchema, tblName, sep=".")
  print(paste0("Inserting ", fullyQualifiedTableName))
  #names(obj) <- SqlRender::camelCaseToSnakeCase(names(obj))
  DatabaseConnector::insertTable(connection = conn,
                                 tableName = fullyQualifiedTableName,
                                 data = obj,
                                 dropTableIfExists = FALSE,
                                 createTable = FALSE,
                                 tempTable = FALSE,
                                 useMppBulkLoad = FALSE,
                                 camelCaseToSnakeCase = FALSE)
}

# Get the cohortXref.csv and load that into the database
cohortXref <- read.csv(system.file("shiny/ResultsExplorer/cohortXref.csv", package = "HERACharacterization"), header = TRUE)
names(cohortXref) <- SqlRender::camelCaseToSnakeCase(names(cohortXref))
insertResultsTable(networkDbConnection, networkSchema, "cohort", cohortXref)

# Load in the results
library(readr)
zipDirRoot <- "E:/HERACharacterization/Results"
zipFiles <- list.files(zipDirRoot, pattern="zip")
for (z in 1:length(zipFiles))
{
  # Extract the contents of the file to a directory
  zipFile <- zipFiles[z]
  zipFileDir <- file.path(zipDirRoot, tools::file_path_sans_ext(zipFile))
  if (!file.exists(zipFileDir)) {
    dir.create(zipFileDir)
  }
  writeLines(paste0("Unzipping to: ", zipFileDir))
  utils::unzip(zipfile = file.path(zipDirRoot, zipFile), exdir = zipFileDir)
  
  tablePrefix <- ""# "TMP_"
  filesToLoadToDb <- c("cohort_count.csv", "covariate.csv", "covariate_value.csv", "database.csv")
  csvFiles <- list.files(zipFileDir, pattern="*.csv")
  for (i in 1:length(csvFiles)) {
    file <- csvFiles[i]
    if (file %in% filesToLoadToDb) {
      writeLines(paste0("Loading ", file))
      tableName <- tools::file_path_sans_ext(file)
      tableName <- paste0(tablePrefix, tableName)
      obj <- read.csv(file.path(zipFileDir, file), header = TRUE)
      insertResultsTable(networkDbConnection, networkSchema, tableName, obj)
    }
  }
  
  # Cleanup the zip directory
  unlink(zipFileDir, recursive = T)
}

# Remove the duplicates
removeDupeCovariatesSql <- SqlRender::loadRenderTranslateSql(dbms = attr(networkDbConnection, "dbms"),
                                                             sqlFilename = "removeDuplicateCovariates.sql",
                                                             packageName = "HERACharacterization",
                                                             warnOnMissingParameters = TRUE,
                                                             network_results_schema = networkSchema)
DatabaseConnector::executeSql(networkDbConnection, 
                              removeDupeCovariatesSql)


