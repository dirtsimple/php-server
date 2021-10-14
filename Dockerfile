# -------- Copy stuff from base images
ARG PHP_VER=8.0.7
ARG OS_VER=3.12
FROM php:$PHP_VER-fpm-alpine$OS_VER

# -------- Add packages and build/install tools

COPY --from=mlocati/php-extension-installer:1.2.50 /usr/bin/install-php-extensions /usr/bin/
ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php
RUN apk --no-cache add \
		--repository http://dl-3.alpinelinux.org/alpine/edge/community \
		gnu-libiconv \
	&& \
	apk --update add \
		bash nginx nginx-mod-http-lua nginx-mod-http-lua-upstream \
		supervisor ncurses certbot git wget curl openssh-client ca-certificates \
		dialog \
	&& \
	install-php-extensions mcrypt pdo_mysql mysqli gd exif intl zip opcache

# -------- Setup composer and runtime environment

ADD https://getcomposer.org/download/2.1.5/composer.phar /usr/bin/composer
ADD https://curl.se/ca/cacert.pem /etc/cacert.pem
RUN chmod ugo+rx /usr/bin/composer && \
    chmod ugo+r /etc/supervisord.conf && \
	mkdir -p /run/nginx /etc/nginx/sites-enabled && \
	ln -s ../sites-available/default.conf /etc/nginx/sites-enabled/default.conf

# -------- Add our stuff, process build args, and initialize composer globals

ENV CODE_BASE /var/www/html
ENV GIT_SSH /usr/bin/git-ssh
ENV COMPOSER_OPTIONS --no-dev --optimize-autoloader

ENV WEBHOOK_PATH hooks
ENV WEBHOOK_PORT 9000
ENV WEBHOOK_USER nginx
ENV WEBHOOK_OPTS "-hotreload -verbose"

VOLUME /etc/letsencrypt
EXPOSE 443 80
CMD ["/usr/bin/start-container"]

COPY --from=bashitup/alpine-tools:latest \
     /bin/dockerize /bin/yaml2json /bin/modd /bin/jq /bin/webhook /usr/bin/
COPY scripts/install-extras scripts/composer-global /usr/bin/

ARG EXTRA_APKS
ARG EXTRA_EXTS
ARG EXTRA_PECL
RUN /usr/bin/install-extras

ARG GLOBAL_REQUIRE=
ENV COMPOSER_HOME /composer
RUN { [[ -z "$GLOBAL_REQUIRE" ]] || composer-global $GLOBAL_REQUIRE; } \
    && mkdir -p /var/www/html \
    && echo '<?php echo phpinfo();' >/var/www/html/index.php

COPY scripts/ /usr/bin/
COPY tpl /tpl
