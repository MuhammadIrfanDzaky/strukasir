# Image produksi API: FrankenPHP (PHP 8.4 + Caddy) — HTTPS Let's Encrypt otomatis.
# Build dari root repo:  docker compose -f deploy/docker-compose.prod.yml build
FROM composer:2 AS vendor
WORKDIR /app
COPY backend/composer.json backend/composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction --ignore-platform-req=ext-*
COPY backend/ ./
RUN composer dump-autoload --optimize --classmap-authoritative --no-dev \
    && rm -rf tests .env .env.* storage/logs/* bootstrap/cache/*.php

FROM dunglas/frankenphp:1-php8.4
RUN install-php-extensions pdo_pgsql pgsql bcmath opcache zip pcntl \
    && cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY deploy/php-prod.ini $PHP_INI_DIR/conf.d/zz-prod.ini
COPY deploy/Caddyfile /etc/caddy/Caddyfile
COPY deploy/entrypoint.sh /usr/local/bin/pos-entrypoint
COPY --from=vendor /app /app
WORKDIR /app
RUN chmod +x /usr/local/bin/pos-entrypoint
ENTRYPOINT ["pos-entrypoint"]
CMD ["frankenphp", "run", "--config", "/etc/caddy/Caddyfile"]
