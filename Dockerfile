ARG BOOKSTACK_VERSION=23.098.3
ARG COMPOSER_VERSION=2.6.5
ARG BUILD_DATE
ARG VCS_REF

# Container used to get the bookstack code and extract it
FROM alpine:3 as bookstack
# Renew needed ARGS
ARG BOOKSTACK_VERSION
# Setup needed environment variables
ENV BOOKSTACK_VERSION=${BOOKSTACK_VERSION}
RUN apk add --no-cache curl tar
RUN set -x; \
    curl -SL -o bookstack.tar.gz https://github.com/BookStackApp/BookStack/archive/v${BOOKSTACK_VERSION}.tar.gz  \
    && mkdir -p /bookstack \
    && tar xvf bookstack.tar.gz -C /bookstack --strip-components=1 \
    && rm bookstack.tar.gz

# Actual container used for running bookstack
FROM php:8.2-apache-bookworm as final
# Renew our ARGS
ARG BOOKSTACK_VERSION
ARG COMPOSER_VERSION
ARG BUILD_DATE
ARG VCS_REF
# Setup our ENVS
ENV BOOKSTACK_VERSION=${BOOKSTACK_VERSION}
ENV COMPOSER_VERSION=${COMPOSER_VERSION}

RUN set -x; \
    apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        zlib1g-dev \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libmcrypt-dev \
        libpng-dev  \
        libldap2-dev  \
        libtidy-dev  \
        libxml2-dev  \
        fontconfig  \
        fonts-freefont-ttf   \
        tar \
        curl \
        wget \
        libzip-dev \
        unzip \
    \
   && wget -O /wkhtmltox.deb https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb  \
   && chmod a+x /wkhtmltox.deb \
   && apt-get install -y /wkhtmltox.deb \
   && rm /wkhtmltox.deb \
   && docker-php-ext-install -j$(nproc) dom pdo pdo_mysql zip tidy xml \
   && docker-php-ext-configure ldap \
   && docker-php-ext-install -j$(nproc) ldap \
   && docker-php-ext-configure gd --with-freetype=/usr/include/ --with-jpeg=/usr/include/ \
   && docker-php-ext-install -j$(nproc) gd

RUN a2enmod rewrite remoteip; \
    { \
    echo RemoteIPHeader X-Real-IP ; \
    echo RemoteIPTrustedProxy 10.0.0.0/8 ; \
    echo RemoteIPTrustedProxy 172.16.0.0/12 ; \
    echo RemoteIPTrustedProxy 192.168.0.0/16 ; \
    } > /etc/apache2/conf-available/remoteip.conf; \
    a2enconf remoteip

RUN set -ex; \
    sed -i "s/Listen 80/Listen 8080/" /etc/apache2/ports.conf; \
    sed -i "s/VirtualHost *:80/VirtualHost *:8080/" /etc/apache2/sites-available/*.conf

COPY bookstack.conf /etc/apache2/sites-available/000-default.conf

COPY --from=bookstack --chown=33:33 /bookstack/ /var/www/bookstack/

COPY php.ini /usr/local/etc/php/conf.d/docker-bookstack-default.ini

COPY docker-entrypoint.sh /bin/docker-entrypoint.sh

RUN cd /var/www/bookstack \
    && mkdir /var/www/.composer \
    && chown -R www-data:www-data /usr/local/etc/php/conf.d/ /var/www/bookstack /var/www/.composer \
    && mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && sed -i 's/memory_limit = 128M/memory_limit = 512M/g' "$PHP_INI_DIR/php.ini"

# Install composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php composer-setup.php \
    && mv composer.phar /usr/bin/composer \
    && chmod +x /usr/bin/composer \
    && php -r "unlink('composer-setup.php');" 

# www-data
USER 33

# Install deps
RUN cd /var/www/bookstack \
    && /usr/bin/composer install -v -d /var/www/bookstack/ 

WORKDIR /var/www/bookstack

VOLUME ["/var/www/bookstack/public/uploads","/var/www/bookstack/storage/uploads"]

ENV RUN_APACHE_USER=www-data \
    RUN_APACHE_GROUP=www-data

EXPOSE 8080

ENTRYPOINT ["/bin/docker-entrypoint.sh"]

LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.docker.dockerfile="/Dockerfile" \
      org.label-schema.license="MIT" \
      org.label-schema.name="bookstack" \
      org.label-schema.vendor="digitalmotion" \
      org.label-schema.url="https://github.com/DigitalMotionTech/docker-bookstack/" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/DigitalMotionTech/docker-bookstack.git" \
      org.label-schema.vcs-type="Git"
