#!/bin/bash
set -e

echo "==> Starting entrypoint.sh..."

# Parse DATABASE_URL to extract host, user, password, port
echo "==> Waiting for database connection..."
DB_HOST=$(echo $DATABASE_URL | sed -e 's/.*@\(.*\):.*/\1/' | cut -d'/' -f1 | cut -d':' -f1)
DB_PORT=$(echo $DATABASE_URL | sed -e 's/.*:\([0-9]*\)\/.*/\1/')
DB_USER=$(echo $DATABASE_URL | sed -e 's/mysql:\/\/\([^:]*\):.*/\1/')
DB_PASS=$(echo $DATABASE_URL | sed -e 's/mysql:\/\/[^:]*:\([^@]*\)@.*/\1/')

until mysqladmin ping -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" --silent 2>/dev/null; do
  echo "  Database not ready yet, retrying in 3s..."
  sleep 3
done
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