#!/usr/bin/env Rscript

library(DatabaseConnector)
library(SqlRender)
library(Achilles)
library(jsonlite)

# ---- Read env ----
dbms         <- Sys.getenv("DBMS", "postgresql")
host         <- Sys.getenv("DB_HOST", "omop54")
port         <- as.integer(Sys.getenv("DB_PORT", "5432"))
dbname       <- Sys.getenv("DB_NAME", "omop54")
user         <- Sys.getenv("DB_USER", "ohdsi")
password     <- Sys.getenv("DB_PASSWORD", "ohdsi")

cdmSchema    <- Sys.getenv("CDM_SCHEMA", "cdm")
vocabSchema  <- Sys.getenv("VOCAB_SCHEMA", cdmSchema)  # often same as CDM
resSchema    <- Sys.getenv("RESULTS_SCHEMA", "results")
tempSchema   <- Sys.getenv("TEMP_SCHEMA", "temp")

cdmVersion   <- Sys.getenv("CDM_VERSION", "5.4")
numThreads   <- as.integer(Sys.getenv("NUM_THREADS", "4"))
smallCell    <- as.integer(Sys.getenv("SMALL_CELL_COUNT", "5"))
createTables <- tolower(Sys.getenv("CREATE_TABLES", "true")) == "true"
exportJson   <- tolower(Sys.getenv("EXPORT_JSON", "true")) == "true"

outDir       <- "/output"
dir.create(outDir, showWarnings = FALSE, recursive = TRUE)

# ---- Connection ----
message("Connecting to Postgres @ ", host, ":", port, " db=", dbname)
cd <- createConnectionDetails(
  dbms     = dbms,
  server   = paste0(host, "/", dbname),
  user     = user,
  password = password,
  port     = port,
  sslmode  = "prefer"
)

conn <- connect(cd)

# ---- Run Achilles ----
message("Running Achilles into schema: ", resSchema, " (CDM=", cdmSchema, ", VOCAB=", vocabSchema, ")")

achilles(
  connectionDetails        = cd,
  cdmDatabaseSchema        = cdmSchema,
  resultsDatabaseSchema    = resSchema,
  vocabularyDatabaseSchema = vocabSchema,
  scratchDatabaseSchema    = tempSchema,
  numThreads               = numThreads,
  cdmVersion               = cdmVersion,
  optimizeAtlasCache       = TRUE,
  smallCellCount           = smallCell,
  createTable              = createTables,
  # You can restrict analyses here with analysisIds = c(...)
  # dataQualityCheck        = TRUE  # enable if you want DQD
)

if (exportJson) {
  message("Exporting Achilles JSON to ", outDir)
  exportToJson(
    connectionDetails     = cd,
    cdmDatabaseSchema     = cdmSchema,
    resultsDatabaseSchema = resSchema,
    outputPath            = outDir,
    organizeIntoSubfolders = TRUE
  )
}

disconnect(conn)
message("Achilles completed successfully.")

