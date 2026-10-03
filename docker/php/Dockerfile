FROM php:8.4-cli
RUN apt-get update && apt-get install -y --no-install-recommends git unzip libpq-dev libzip-dev postgresql-client \
    && docker-php-ext-install pdo_pgsql pgsql zip bcmath pcntl opcache \
    && rm -rf /var/lib/apt/lists/*
# Mount folder Windows ke container lambat dibaca; opcache + realpath cache memangkas waktu boot per request.
# validate_timestamps tetap aktif, jadi perubahan kode langsung terbaca saat development.
RUN { echo 'opcache.enable=1'; echo 'opcache.enable_cli=1'; echo 'opcache.validate_timestamps=1'; \
      echo 'opcache.revalidate_freq=2'; echo 'opcache.memory_consumption=192'; echo 'opcache.max_accelerated_files=20000'; \
      echo 'realpath_cache_size=4096K'; echo 'realpath_cache_ttl=600'; } > /usr/local/etc/php/conf.d/dev-perf.ini
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
WORKDIR /app
