#!/usr/bin/env bash
set -euo pipefail

# ------- Parámetros (heredables por env) -------
PGHOST=${PGHOST:-omop54}
PGPORT=${PGPORT:-5432}
PGDATABASE=${PGDATABASE:-omop54}
PGUSER=${PGUSER:-postgres}
PGPASSWORD=${PGPASSWORD:-password}
WEBAPI_SCHEMA=${WEBAPI_SCHEMA:-webapi}
CDM_SCHEMA=${CDM_SCHEMA:-cdm}
RESULTS_SCHEMA=${RESULTS_SCHEMA:-results}

SOURCE_KEY=${SOURCE_KEY:-OMOP54}
SOURCE_NAME=${SOURCE_NAME:-"OMOP54 (Postgres)"}
SOURCE_DIALECT=${SOURCE_DIALECT:-postgresql}

export PGPASSWORD

echo "Seeding WebAPI sources…"

# ------- Función para ejecutar psql con formato fácil de parsear -------
psqlq() {
  psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -qtAX -v ON_ERROR_STOP=1 -c "$1"
}

# ------- Esperar a que exista la tabla webapi.source -------
echo "Esperando a que exista ${WEBAPI_SCHEMA}.source (migraciones Flyway)…"
while true; do
  status=$(psqlq "SELECT CASE
    WHEN to_regclass('${WEBAPI_SCHEMA}.source') IS NULL THEN -1
    WHEN EXISTS (SELECT 1 FROM ${WEBAPI_SCHEMA}.source) THEN 1
    ELSE 0
  END;") || true

  # status puede venir con espacios/nueva línea
  status=$(echo "$status" | tr -d '[:space:]')

  if [[ "$status" == "-1" ]]; then
    # Tabla aún no creada por WebAPI → esperar
    sleep 2
  else
    break
  fi
done

if [[ "$status" == "1" ]]; then
  echo "Ya hay fuentes en ${WEBAPI_SCHEMA}.source. No se realiza seeding."
  exit 0
fi

echo "No hay fuentes; insertando fuente y daemons…"

psql -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM ${WEBAPI_SCHEMA}.source WHERE source_key = 'OMOP54') THEN
    INSERT INTO ${WEBAPI_SCHEMA}.source (source_name, source_key, source_connection, source_dialect)
    VALUES (
      'OMOP54 (Postgres)',
      'OMOP54',
      'jdbc:postgresql://${PGHOST}:${PGPORT}/${PGDATABASE}?user=${OHDSI_DB_USER}&password=${OHDSI_DB_PASS}',
      'postgresql'
    );
  END IF;
END\$\$;
SQL

# 2) Upsert DAIMONS using WHERE NOT EXISTS (no ON CONFLICT)
# CDM (type 0)
psql -v ON_ERROR_STOP=1 <<SQL
WITH s AS (
  SELECT source_id FROM ${WEBAPI_SCHEMA}.source WHERE source_key = 'OMOP54'
)
INSERT INTO ${WEBAPI_SCHEMA}.source_daimon (source_id, daimon_type, table_qualifier, priority)
SELECT s.source_id, 0, '${CDM_SCHEMA}', 0
FROM s
WHERE NOT EXISTS (
  SELECT 1 FROM ${WEBAPI_SCHEMA}.source_daimon d
  WHERE d.source_id = s.source_id AND d.daimon_type = 0
);
SQL

# VOCAB (type 1) — same schema as CDM here
psql -v ON_ERROR_STOP=1 <<SQL
WITH s AS (
  SELECT source_id FROM ${WEBAPI_SCHEMA}.source WHERE source_key = 'OMOP54'
)
INSERT INTO ${WEBAPI_SCHEMA}.source_daimon (source_id, daimon_type, table_qualifier, priority)
SELECT s.source_id, 1, '${CDM_SCHEMA}', 0
FROM s
WHERE NOT EXISTS (
  SELECT 1 FROM ${WEBAPI_SCHEMA}.source_daimon d
  WHERE d.source_id = s.source_id AND d.daimon_type = 1
);
SQL

# RESULTS (type 2)
psql -v ON_ERROR_STOP=1 <<SQL
WITH s AS (
  SELECT source_id FROM ${WEBAPI_SCHEMA}.source WHERE source_key = 'OMOP54'
)
INSERT INTO ${WEBAPI_SCHEMA}.source_daimon (source_id, daimon_type, table_qualifier, priority)
SELECT s.source_id, 2, '${RESULTS_SCHEMA}', 0
FROM s
WHERE NOT EXISTS (
  SELECT 1 FROM ${WEBAPI_SCHEMA}.source_daimon d
  WHERE d.source_id = s.source_id AND d.daimon_type = 2
);
SQL

echo "✅ WebAPI source/daimons seeded successfully."
