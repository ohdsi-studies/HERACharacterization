Health Equity Research Assessment (HERA) Characterization
=============

<img src="https://img.shields.io/badge/Study%20Status-Started-blue.svg" alt="Study Status: Started">

- Analytics use case(s): **Characterization**
- Study type: **Clinical Application**
- Tags: **OHDSI, Health Equity**
- Study lead: **Noemie Elhadad**
- Study lead forums tag: **[noemie](https://forums.ohdsi.org/u/noemie)**
- Study start date: **-**
- Study end date: **-**
- Protocol: **-**
- Publications: **-**
- Results explorer: **-**

Health Equity Research Assessment (HERA): a large scale characterization of gender and racial disparities

Requirements
============

- A database in [Common Data Model version 5](https://github.com/OHDSI/CommonDataModel) in one of these platforms: SQL Server, Oracle, PostgreSQL, IBM Netezza, Apache Impala, Amazon RedShift, Google BigQuery, or Microsoft APS.
- R version 4.0.0 or newer
- On Windows: [RTools](http://cran.r-project.org/bin/windows/Rtools/)
- [Java](http://java.com)
- 25 GB of free disk space

How to run
==========
1. Follow [these instructions](https://ohdsi.github.io/Hades/rSetup.html) for setting up your R environment, including RTools and Java. 

2. Download the study package by cloning this repository using the following command:

  ```
  git clone https://github.com/ohdsi-studies/HERACharacterization.git
  ```

3. Open the study package project (HERACharacterization.Rproj) in RStudio. Use the following code to install all the dependencies:

	```r
	install.packages("renv")
	renv::restore()
	```

4. In RStudio, select 'Build' then 'Install and Restart' to build the study package.

5. Once installed, you can execute the study by modifying and using the code below. For your convenience, this code is also provided under `extras/CodeToRun.R`:

	```r
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
	```

6. Review the results by using the Shiny application included in the study package:
	```r
    # Use the next set of commands to compress results and view the output.
    preMergeResultsFiles(outputFolder) 
    launchShinyApp(outputFolder)
  ```

7. Upload the file ```export/Results_<DatabaseId>.zip``` in the output folder to the study coordinator:

	```r
    # For uploading the results. You should have received the key file from the study coordinator:
    keyFileName <- "E:/HERACharacterization/study-data-site-covid19.dat"
    userName <- "study-data-site-covid19"
    
    # When finished with reviewing the results, use the next command upload study results to OHDSI SFTP
    # server: 
    # uploadStudyResults(outputFolder, keyFileName, userName)
	```
	
License
=======
The HERACharacterization package is licensed under Apache License 2.0

Development
===========
HERACharacterization was developed in ATLAS and R Studio.
