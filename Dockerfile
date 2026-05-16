FROM php:8.3-fpm

# Install system dependencies (including ICU for intl and libs for gd)
RUN apt-get update && apt-get install -y \
    git \
    curl \
    default-mysql-client \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    libicu-dev \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    zip \
    unzip \
    nginx \
    supervisor \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure intl \
    && docker-php-ext-install \
        pdo_mysql \
        mbstring \
        exif \
        pcntl \
        bcmath \
        gd \
        zip \
        intl \
        opcache

# Ensure PHP-FPM workers keep runtime env vars (DATABASE_URL, APP_SECRET, etc.)
RUN { \
      echo '[www]'; \
      echo 'clear_env = no'; \
    } > /usr/local/etc/php-fpm.d/zz-clear-env.conf

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Railway/Docker build runs as root; allow Composer plugins (Symfony Flex / symfony-cmd)
ENV COMPOSER_ALLOW_SUPERUSER=1

# Copy composer files first (layer caching)
COPY composer.json composer.lock symfony.lock ./

# Install PHP dependencies (no dev, optimize autoloader)
RUN composer install \
    --no-dev \
    --optimize-autoloader \
    --no-scripts \
    --no-interaction

# Copy the rest of the application
COPY . .

# Run post-install scripts (cache:clear, assets:install, importmap:install)
RUN composer run-script post-install-cmd --no-interaction

# Create Symfony var/ directory and set permissions
RUN mkdir -p /var/www/html/var \
    && chown -R www-data:www-data /var/www/html/var \
    && chmod -R 775 /var/www/html/var

# Copy Nginx configuration files
COPY nginx.conf /etc/nginx/nginx.conf
COPY nginx-main.conf /etc/nginx/conf.d/default.conf

# Copy Supervisor configuration
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy and set entrypoint
# Strip Windows CRLF line endings (\r\n -> \n) to prevent 'no such file or directory' on Linux
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

# Expose port 80
EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
