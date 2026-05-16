#!/bin/bash
set -e

echo "==> Starting entrypoint.sh..."

# Wait for MySQL to be ready
echo "==> Waiting for database connection..."
until php bin/console doctrine:query:sql "SELECT 1" > /dev/null 2>&1; do
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
