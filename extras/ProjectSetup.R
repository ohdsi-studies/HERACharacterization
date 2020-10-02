#------------------------------------------------------------------
# INITIAL PROJECT SETUP ---------------------------------------
#------------------------------------------------------------------
# This initial setup will ensure that you have all required
# R packages installed for use with the package. If you are running 
# this in an environment where there is no access to the Internet 
# please see the sections below marked "offline setup step".
#------------------------------------------------------------------
#------------------------------------------------------------------
install.packages("renv")

projectRootFolder <- "E:/HERACharacterization"
setwd(projectRootFolder)

# Download the lock file:
download.file("https://raw.githubusercontent.com/ohdsi-studies/HERACharacterization/master/renv.lock", "renv.lock")
# Sys.setenv('BINPREF'='E:/R/Rtools/mingw_$(WIN)/bin/')

#------------------------------------------------------------------
# OPTIONAL: If you want to change where renv stores the R packages you can specify the
# RENV_PATHS_ROOT. Please refer to https://rstudio.github.io/renv/articles/renv.html#cache for more
# details
#------------------------------------------------------------------
# Sys.setenv('RENV_PATHS_ROOT'=projectRootFolder)

#------------------------------------------------------------------
# OFFLINE SETUP STEP: If you want to have the entire contents of the renv R packages local to your
# project so that you may copy it to another computer, please uncomment the line below and specify
# the RENV_PATHS_CACHE location which should be your project folder.
#------------------------------------------------------------------
# Sys.setenv('RENV_PATHS_CACHE'=projectRootFolder)

# Build the local library:
renv::init()

# When not in RStudio, you'll need to restart R now
library(HERACharacterization)

# ------------------------------------------------------------- END Initial Project Setup
# -------------------------------------------------------------
