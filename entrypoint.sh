#!/bin/bash
set -e

echo "==> Starting entrypoint.sh..."

export APP_ENV="${APP_ENV:-prod}"
export APP_DEBUG="${APP_DEBUG:-0}"

if [ -z "${DATABASE_URL:-}" ]; then
  if [ -n "${MYSQL_URL:-}" ]; then
    export DATABASE_URL="$MYSQL_URL"
  elif [ -n "${MYSQL_PUBLIC_URL:-}" ]; then
    export DATABASE_URL="$MYSQL_PUBLIC_URL"
  elif [ -n "${MYSQLHOST:-}" ] && [ -n "${MYSQLUSER:-}" ] && [ -n "${MYSQLDATABASE:-}" ]; then
    MYSQLPORT="${MYSQLPORT:-3306}"
    export DATABASE_URL="mysql://${MYSQLUSER}:${MYSQLPASSWORD:-}@${MYSQLHOST}:${MYSQLPORT}/${MYSQLDATABASE}?serverVersion=8.0&charset=utf8mb4"
  elif [ -n "${MYSQL_HOST:-}" ] && [ -n "${MYSQL_USER:-}" ] && [ -n "${MYSQL_DATABASE:-}" ]; then
    MYSQL_PORT="${MYSQL_PORT:-3306}"
    export DATABASE_URL="mysql://${MYSQLUSER}:${MYSQLPASSWORD:-}@${MYSQLHOST}:${MYSQLPORT}/${MYSQLDATABASE}?serverVersion=9.4.0&charset=utf8mb4"
  fi
fi

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: DATABASE_URL is not set. Configure your Railway database variables."
  exit 1
fi

if ! command -v mysqladmin >/dev/null 2>&1; then
  echo "ERROR: mysqladmin is not installed. Ensure the image installs a MySQL client."
  exit 1
fi

DB_HOST=$(php -r '$u=parse_url(getenv("DATABASE_URL")); echo isset($u["host"]) ? rawurldecode($u["host"]) : "";')
DB_PORT=$(php -r '$u=parse_url(getenv("DATABASE_URL")); echo $u["port"] ?? "3306";')
DB_USER=$(php -r '$u=parse_url(getenv("DATABASE_URL")); echo isset($u["user"]) ? rawurldecode($u["user"]) : "";')
DB_PASS=$(php -r '$u=parse_url(getenv("DATABASE_URL")); echo isset($u["pass"]) ? rawurldecode($u["pass"]) : "";')

if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ]; then
  echo "ERROR: Could not parse DATABASE_URL for database connection."
  exit 1
fi

MYSQLADMIN_AUTH=(-u"$DB_USER")
if [ -n "$DB_PASS" ]; then
  MYSQLADMIN_AUTH+=(-p"$DB_PASS")
fi

echo "==> Waiting for database connection..."
MAX_RETRIES="${DB_WAIT_MAX_RETRIES:-60}"
SLEEP_SECONDS="${DB_WAIT_SLEEP_SECONDS:-3}"
DB_READY=0
LAST_DB_ERROR=""


echo "==> Waiting for database connection via Doctrine..."
MAX_RETRIES="${DB_WAIT_MAX_RETRIES:-60}"
SLEEP_SECONDS="${DB_WAIT_SLEEP_SECONDS:-3}"
DB_READY=0

for i in $(seq 1 "$MAX_RETRIES"); do
  # Use Symfony's built-in command to test if the DB is reachable
  if php bin/console doctrine:database:create --if-not-exists --no-interaction >/dev/null 2>&1 || php bin/console doctrine:query:sql "SELECT 1" >/dev/null 2>&1; then
    DB_READY=1
    break
  fi
  echo "  Database not ready yet, retrying in ${SLEEP_SECONDS}s... (${i}/${MAX_RETRIES})" 
  sleep "$SLEEP_SECONDS" 
done

if [ "$DB_READY" -ne 1 ]; then
  echo "ERROR: Database not reachable after ${MAX_RETRIES} attempts."
  if [ -n "$LAST_DB_ERROR" ]; then
    echo "ERROR: Last database check: $LAST_DB_ERROR"
  fi
  exit 1
fi
echo "==> Database is ready."

# Run database migrations
echo "==> Running database migrations..."
php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration

# Clear and warm up the Symfony cache (production)
echo "==> Warming up cache..."
php bin/console cache:clear --env=prod --no-debug
php bin/console cache:warmup --env=prod --no-debug

# Fix permissions on var/ after cache warmup
chown -R www-data:www-data /var/www/html/var

echo "==> Entrypoint complete. Starting services..."

# Hand off to CMD (supervisord)
exec "$@"
