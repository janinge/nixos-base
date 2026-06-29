#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:=primary.postgres-cluster.service.consul}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${JUICEFS_DB_NAME:=juicefs_external}"
: "${JUICEFS_DB_USER:=juicefs_external}"
: "${JUICEFS_FS_NAME:=external-juicefs}"
: "${JUICEFS_STORAGE:=s3}"
: "${JUICEFS_SSLMODE:=disable}"
: "${JUICEFS_S3_ENV_FILE:=/run/secrets/juicefs_external_s3.env}"

if [[ -z "${PGPASSWORD:-}" ]]; then
  echo "PGPASSWORD (Patroni superuser password) must be set in the environment." >&2
  exit 1
fi

if [[ -z "${JUICEFS_DB_PASSWORD:-}" ]]; then
  read -r -s -p "JuiceFS DB password: " JUICEFS_DB_PASSWORD
  echo
fi

if [[ -f "$JUICEFS_S3_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$JUICEFS_S3_ENV_FILE"
  set +a
fi

: "${JUICEFS_BUCKET_URL:?JUICEFS_BUCKET_URL must be set directly or in $JUICEFS_S3_ENV_FILE}"
: "${ACCESS_KEY:?ACCESS_KEY must be set directly or in $JUICEFS_S3_ENV_FILE}"
: "${SECRET_KEY:?SECRET_KEY must be set directly or in $JUICEFS_S3_ENV_FILE}"

psql_args=(
  --no-psqlrc
  --set
  ON_ERROR_STOP=1
  --host
  "$PGHOST"
  --port
  "$PGPORT"
  --username
  "$PGUSER"
  --dbname
  postgres
)

psql "${psql_args[@]}" \
  --set=db_name="$JUICEFS_DB_NAME" \
  --set=db_user="$JUICEFS_DB_USER" \
  --set=db_password="$JUICEFS_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN', :'db_user')
WHERE NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = :'db_user')
\gexec

SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'db_user', :'db_password')
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'db_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'db_name')
\gexec

SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'db_user')
\gexec
SQL

meta_url="postgres://${JUICEFS_DB_USER}@${PGHOST}:${PGPORT}/${JUICEFS_DB_NAME}?sslmode=${JUICEFS_SSLMODE}"

format_args=(
  --storage
  "$JUICEFS_STORAGE"
  --bucket
  "$JUICEFS_BUCKET_URL"
)

if [[ -n "${SESSION_TOKEN:-}" ]]; then
  format_args+=(--session-token "$SESSION_TOKEN")
fi

if PGPASSWORD="$JUICEFS_DB_PASSWORD" juicefs status "$meta_url" >/dev/null 2>&1; then
  echo "JuiceFS metadata at '$meta_url' is already formatted."
else
  PGPASSWORD="$JUICEFS_DB_PASSWORD" juicefs format \
    "${format_args[@]}" \
    "$meta_url" \
    "$JUICEFS_FS_NAME"
fi

echo "JuiceFS bootstrap completed for filesystem '$JUICEFS_FS_NAME', database '$JUICEFS_DB_NAME', and role '$JUICEFS_DB_USER'."
