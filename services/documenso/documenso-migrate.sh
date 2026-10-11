#!/bin/sh
# Railway pre-deploy command: apply Prisma migrations before the new deployment starts.
# Retries while Postgres is still starting (services boot in parallel on a fresh deploy).
set -u

export NEXT_PRIVATE_DIRECT_DATABASE_URL="${NEXT_PRIVATE_DIRECT_DATABASE_URL:-${NEXT_PRIVATE_DATABASE_URL:-}}"
if [ -z "${NEXT_PRIVATE_DIRECT_DATABASE_URL}" ]; then
    echo "[documenso-migrate] NEXT_PRIVATE_DATABASE_URL is not set" >&2
    exit 1
fi

cd /app/apps/remix
attempts="${MIGRATE_MAX_ATTEMPTS:-60}"
i=1
while :; do
    echo "[documenso-migrate] prisma migrate deploy (attempt ${i}/${attempts})"
    if npx prisma migrate deploy --schema ../../packages/prisma/schema.prisma; then
        echo "[documenso-migrate] database is up to date"
        exit 0
    fi
    if [ "$i" -ge "$attempts" ]; then
        echo "[documenso-migrate] giving up: migrations failed ${attempts} times" >&2
        exit 1
    fi
    i=$((i + 1))
    sleep 5
done
