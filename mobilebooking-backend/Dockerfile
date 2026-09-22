# Laravel API for Render (PHP 8.4 + Apache). Place this file in mobilebooking-backend/.
FROM php:8.4-apache

# PHP extensions this app needs. pdo_pgsql/pgsql are for the Supabase Postgres connection.
# (mbstring, curl, fileinfo, tokenizer, xml, ctype, openssl already ship with the base image.)
RUN apt-get update \
 && apt-get install -y --no-install-recommends git unzip libpq-dev \
 && docker-php-ext-install pdo_pgsql pgsql bcmath \
 && a2enmod rewrite headers \
 && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Install PHP dependencies first so Docker can cache this layer.
COPY composer.json composer.lock* ./
RUN composer install --no-dev --no-interaction --no-progress --no-scripts --prefer-dist

# Application code.
COPY . .
RUN composer dump-autoload --no-dev --optimize --no-scripts \
 && mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs bootstrap/cache \
 && chown -R www-data:www-data storage bootstrap/cache

# Serve Laravel's /public folder, allow its .htaccess (routing + Authorization header),
# and listen on the port Render gives us ($PORT).
ENV APACHE_DOCUMENT_ROOT=/var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
 && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf \
 && sed -ri -e 's/Listen 80/Listen ${PORT}/' /etc/apache2/ports.conf \
 && sed -ri -e 's/<VirtualHost \*:80>/<VirtualHost *:${PORT}>/' /etc/apache2/sites-available/000-default.conf \
 && printf '<Directory /var/www/html/public>\n    AllowOverride All\n    Require all granted\n</Directory>\n' > /etc/apache2/conf-available/laravel.conf \
 && printf 'ServerName localhost\n' > /etc/apache2/conf-available/servername.conf \
 && a2enconf laravel servername

ENV PORT=10000
EXPOSE 10000

# Caches config/routes at start-up (when Render's environment variables exist), then runs Apache.
CMD ["sh", "-c", "php artisan package:discover --ansi && php artisan config:cache && php artisan route:cache && apache2-foreground"]