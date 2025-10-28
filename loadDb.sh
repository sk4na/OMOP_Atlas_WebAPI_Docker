#!/bin/bash
set -euo pipefail

# ----- Safe defaults (override via compose) -----
: "${POSTGRES_USER:=postgres}"
: "${OMOP_DB:=omop54}"
: "${CDM_SCHEMA:=cdm}"
: "${RESULTS_SCHEMA:=results}"
: "${TEMP_SCHEMA:=temp}"
: "${OHDSI_DB_USER:=ohdsi}"
: "${OHDSI_DB_PASS:=ohdsi}"
: "${CONSTRAINTS:=false}"
: "${OMOP_ON_FHIR:=false}"

ERROR='\033[0;31m'; WARN='\033[1;33m'; INFO='\033[1;32m'; DEFAULT='\033[0m'
echo -e "${INFO}INFO  -- ${DEFAULT}Creating database ${OMOP_DB} and CDM tables..."
echo -e "${INFO}INFO  -- ${DEFAULT}Vars: OMOP_DB=${OMOP_DB} CDM=${CDM_SCHEMA} RESULTS=${RESULTS_SCHEMA} TEMP=${TEMP_SCHEMA} OHDSI_USER=${OHDSI_DB_USER}"

# ----- Create the database (idempotent, OUTSIDE a transaction) -----
DB_EXISTS=$(psql -At --username "$POSTGRES_USER" -d postgres \
  -c "SELECT 1 FROM pg_database WHERE datname='${OMOP_DB}'" || true)
if [[ "$DB_EXISTS" != "1" ]]; then
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" -d postgres -c "CREATE DATABASE ${OMOP_DB};"
fi

# ----- Create required schemas (idempotent) -----
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$OMOP_DB" <<-EOSQL
CREATE SCHEMA IF NOT EXISTS ${CDM_SCHEMA};
CREATE SCHEMA IF NOT EXISTS ${RESULTS_SCHEMA};
CREATE SCHEMA IF NOT EXISTS ${TEMP_SCHEMA};
EOSQL

# ----- Prepare DDL: rewrite "public." -> "${CDM_SCHEMA}." if present -----
DDL_ORIG="/scripts/OMOPCDM_postgresql_5.4_ddl.sql"
DDL_TMP="/tmp/OMOPCDM_postgresql_5.4_ddl.schemafix.sql"
if grep -qiE '\bpublic\.' "$DDL_ORIG"; then
  cp "$DDL_ORIG" "$DDL_TMP"
  sed -i "s/\bpublic\./${CDM_SCHEMA}./gI" "$DDL_TMP"
else
  DDL_TMP="$DDL_ORIG"
fi

# ----- Run CDM DDL -----
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$OMOP_DB" -f "$DDL_TMP"

# ----- Create OHDSI application user (idempotent) -----
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$OMOP_DB" <<-EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${OHDSI_DB_USER}') THEN
    CREATE ROLE ${OHDSI_DB_USER} LOGIN PASSWORD '${OHDSI_DB_PASS}';
  END IF;
END\$\$;
EOSQL

# ----- Grants: CDM read, results/temp write -----
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$OMOP_DB" <<-EOSQL
GRANT CONNECT ON DATABASE ${OMOP_DB} TO ${OHDSI_DB_USER};
GRANT CREATE  ON DATABASE ${OMOP_DB} TO ${OHDSI_DB_USER};
GRANT USAGE ON SCHEMA ${CDM_SCHEMA}, ${RESULTS_SCHEMA}, ${TEMP_SCHEMA} TO ${OHDSI_DB_USER};
GRANT SELECT ON ALL TABLES IN SCHEMA ${CDM_SCHEMA} TO ${OHDSI_DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA ${CDM_SCHEMA} GRANT SELECT ON TABLES TO ${OHDSI_DB_USER};
GRANT ALL ON SCHEMA ${RESULTS_SCHEMA} TO ${OHDSI_DB_USER};
GRANT INSERT, UPDATE, DELETE, SELECT ON ALL TABLES IN SCHEMA ${RESULTS_SCHEMA} TO ${OHDSI_DB_USER};
GRANT USAGE, CREATE ON SCHEMA ${TEMP_SCHEMA} TO ${OHDSI_DB_USER};
EOSQL

# ----- Vocabulary load (only if key table exists AND /VOCAB has files) -----
PATH_TO_VOCAB=/VOCAB
HAS_DRUG_STRENGTH=$(
  psql -At --username "$POSTGRES_USER" --dbname "$OMOP_DB" \
    -c "select count(*)>0 from information_schema.tables where table_schema='${CDM_SCHEMA}' and table_name='drug_strength'"
)
if [[ "$HAS_DRUG_STRENGTH" == "t" && -d $PATH_TO_VOCAB && "$(ls -A "$PATH_TO_VOCAB" 2>/dev/null)" ]]; then
  echo -e "${INFO}INFO  -- ${DEFAULT}Loading vocabulary..."
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$OMOP_DB" <<-EOSQL
    SET search_path TO ${CDM_SCHEMA};
    \i /scripts/load_vocabulary.sql
EOSQL
else
  echo -e "${WARN}WARN  -- ${DEFAULT}Skipping vocabulary (tables missing or /VOCAB empty)."
fi

if [[ "${CONSTRAINTS}" == "true" ]]; then
  echo -e "${INFO}INFO  -- ${DEFAULT}Applying constraints and indexes..."

  pk_src="/scripts/OMOPCDM_postgresql_5.4_primary_keys.sql"
  ix_src="/scripts/OMOPCDM_postgresql_5.4_indices.sql"
  fk_src="/scripts/OMOPCDM_postgresql_5.4_constraints.sql"

  pk_tmp="/tmp/OMOPCDM_postgresql_5.4_primary_keys.schemafix.sql"
  ix_tmp="/tmp/OMOPCDM_postgresql_5.4_indices.schemafix.sql"
  fk_tmp="/tmp/OMOPCDM_postgresql_5.4_constraints.schemafix.sql"

  for src in "$pk_src" "$ix_src" "$fk_src"; do
    [[ -f "$src" ]] || { echo -e "${WARN}WARN  -- ${DEFAULT}Missing $src, skipping."; continue; }
  done

  # rewrite public. -> ${CDM_SCHEMA}.
  cp "$pk_src" "$pk_tmp" && sed -i "s/\bpublic\./${CDM_SCHEMA}./gI" "$pk_tmp"
  cp "$ix_src" "$ix_tmp" && sed -i "s/\bpublic\./${CDM_SCHEMA}./gI" "$ix_tmp"
  cp "$fk_src" "$fk_tmp" && sed -i "s/\bpublic\./${CDM_SCHEMA}./gI" "$fk_tmp"

  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$OMOP_DB" -f "$pk_tmp"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$OMOP_DB" -f "$ix_tmp"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$OMOP_DB" -f "$fk_tmp"
else
  echo -e "${INFO}INFO  -- ${DEFAULT}Skipping constraints per CONSTRAINTS!=true."
fi

# ----- Optional: OMOP on FHIR helpers -----
if [[ "${OMOP_ON_FHIR}" == "true" ]]; then
  echo -e "${INFO}INFO  -- ${DEFAULT}Creating OMOP on FHIR helper objects..."
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$OMOP_DB" <<-EOSQL
    SET search_path TO ${CDM_SCHEMA};
    \i /omoponfhir/omoponfhir_f_person_ddl.txt
    \i /omoponfhir/omoponfhir_f_cache_ddl.txt
    \i /omoponfhir/omoponfhir_v5.2_f_immunization_view_ddl.txt
    \i /omoponfhir/omoponfhir_v5.4_f_observation_view_ddl.txt
EOSQL
fi

echo -e "${INFO}INFO  -- ${DEFAULT}Database prep complete."

