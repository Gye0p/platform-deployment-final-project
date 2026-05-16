#!/bin/bash
set -e

echo "==> Starting entrypoint.sh..."

export APP_ENV="${APP_ENV:-prod}"
export APP_DEBUG="${APP_DEBUG:-0}"

if [ "$APP_ENV" = "prod" ] && [ -z "${APP_SECRET:-}" ]; then
  echo "ERROR: APP_SECRET is not set. Configure APP_SECRET in your deployment environment."
  exit 1
fi

if [ -z "${DATABASE_URL:-}" ]; then
  if [ -n "${MYSQL_URL:-}" ]; then
    export DATABASE_URL="${MYSQL_URL}"
  elif [ -n "${MYSQL_PUBLIC_URL:-}" ]; then
    export DATABASE_URL="${MYSQL_PUBLIC_URL}"
  else
    DB_HOST="${MYSQLHOST:-${MYSQL_HOST:-}}"
    DB_PORT="${MYSQLPORT:-${MYSQL_PORT:-3306}}"
    DB_USER="${MYSQLUSER:-${MYSQL_USER:-}}"
    DB_PASS="${MYSQLPASSWORD:-${MYSQL_PASSWORD:-}}"
    DB_NAME="${MYSQLDATABASE:-${MYSQL_DATABASE:-}}"
    DB_SERVER_VERSION="${DB_SERVER_VERSION:-8.0}"

    if [ -n "$DB_HOST" ] && [ -n "$DB_USER" ] && [ -n "$DB_NAME" ]; then
      export DATABASE_URL="mysql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}?serverVersion=${DB_SERVER_VERSION}&charset=utf8mb4"
    fi
  fi
fi

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: DATABASE_URL is not set. Configure DATABASE_URL or MySQL variables in deployment."
  exit 1
fi

# Append serverVersion and charset to DATABASE_URL if missing.
# Railway's MySQL plugin provides a bare URL (no ?serverVersion=...) which
# causes Doctrine DBAL to fail or warn. We append the defaults here safely.
if ! echo "${DATABASE_URL}" | grep -q "serverVersion"; then
  DB_SERVER_VERSION="${DB_SERVER_VERSION:-8.0}"
  if echo "${DATABASE_URL}" | grep -q "?"; then
    export DATABASE_URL="${DATABASE_URL}&serverVersion=${DB_SERVER_VERSION}&charset=utf8mb4"
  else
    export DATABASE_URL="${DATABASE_URL}?serverVersion=${DB_SERVER_VERSION}&charset=utf8mb4"
  fi
  echo "==> Appended serverVersion=${DB_SERVER_VERSION}&charset=utf8mb4 to DATABASE_URL"
fi

echo "==> Waiting for database connection via Doctrine..."
MAX_RETRIES="${DB_WAIT_MAX_RETRIES:-60}"
SLEEP_SECONDS="${DB_WAIT_SLEEP_SECONDS:-3}"
DB_READY=0
LAST_DB_ERROR=""

for i in $(seq 1 "$MAX_RETRIES"); do
  set +e
  DB_CHECK_OUTPUT=$(php bin/console doctrine:query:sql "SELECT 1" --no-interaction 2>&1)
  DB_CHECK_EXIT=$?
  set -e

  if [ "$DB_CHECK_EXIT" -eq 0 ]; then
    DB_READY=1
    break
  fi

  LAST_DB_ERROR="$DB_CHECK_OUTPUT"
  echo "$DB_CHECK_OUTPUT"
  echo "  Database not ready yet, retrying in ${SLEEP_SECONDS}s... (${i}/${MAX_RETRIES})"
  sleep "$SLEEP_SECONDS"
done

if [ "$DB_READY" -ne 1 ]; then
  echo "ERROR: Database not reachable after ${MAX_RETRIES} attempts."
  if [ -n "$LAST_DB_ERROR" ]; then
    echo "ERROR: Last database check:"
    echo "$LAST_DB_ERROR"
  fi
  exit 1
fi
echo "==> Database is ready."

echo "==> Running database migrations..."
php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration

echo "==> Warming up cache..."
php bin/console cache:clear --env=prod --no-debug
php bin/console cache:warmup --env=prod --no-debug

chown -R www-data:www-data /var/www/html/var

# Make Nginx listen on $PORT (Railway injects this; defaults to 80 for local Docker).
# Without this, Railway's proxy can't reach Nginx because it routes to $PORT, not 80.
export PORT="${PORT:-80}"
echo "==> Configuring Nginx to listen on port ${PORT}..."
sed -i "s/listen 80;/listen ${PORT};/" /etc/nginx/conf.d/default.conf

echo "==> Entrypoint complete. Starting services on port ${PORT}..."
exec "$@"
