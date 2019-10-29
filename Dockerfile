# -------- Copy stuff from base images

FROM jwilder/dockerize:0.6.0 AS dockerize
FROM bashitup/alpine-tools:latest AS tools
FROM php:7.1.33-fpm-alpine3.9

COPY --from=dockerize /usr/local/bin/dockerize /usr/bin/

COPY --from=tools     /bin/yaml2json        /usr/bin/
COPY --from=tools     /bin/modd             /usr/bin/
COPY --from=tools     /bin/jq               /usr/bin/

# -------- Add packages and build/install tools

ENV LD_PRELOAD /usr/lib/preloadable_libiconv.so php
RUN apk --no-cache add \
		--repository http://dl-3.alpinelinux.org/alpine/edge/community \
		gnu-libiconv \
	&& \
	apk --update add \
		bash nginx nginx-mod-http-lua nginx-mod-http-lua-upstream \
		supervisor ncurses certbot \
		git wget curl libcurl openssh-client ca-certificates \
		dialog libpq icu-libs \
		libmcrypt libxslt libpng freetype libjpeg-turbo \
	&& \
    apk add --virtual .build-deps \
		autoconf gcc make musl-dev linux-headers libffi-dev \
		augeas-dev python-dev icu-dev sqlite-dev openssl-dev \
		libmcrypt-dev libxslt-dev libpng-dev freetype-dev libjpeg-turbo-dev \
	&& \
	docker-php-ext-configure gd \
		--with-gd \
		--with-freetype-dir=/usr/include/ --with-png-dir=/usr/include/ \
		--with-jpeg-dir=/usr/include/ \
	&& \
	docker-php-ext-install \
		pdo_mysql pdo_sqlite mysqli \
		mcrypt gd exif intl xsl json soap dom zip opcache && \
	pecl install xdebug && \
	docker-php-source delete && \
	apk del .build-deps

# -------- Setup composer and runtime environment

ADD https://getcomposer.org/download/1.9.0/composer.phar /usr/bin/composer
RUN chmod ugo+rx /usr/bin/composer && \
	mkdir -p /run/nginx /etc/nginx/sites-enabled && \
	ln -s ../sites-available/default.conf /etc/nginx/sites-enabled/default.conf

# -------- Add our stuff, process build args, and initialize composer globals

ENV CODE_BASE /var/www/html
ENV GIT_SSH /usr/bin/git-ssh
ENV COMPOSER_OPTIONS --no-dev

VOLUME /etc/letsencrypt
EXPOSE 443 80
CMD ["/usr/bin/start-container"]

COPY scripts/install-extras /usr/bin/

ARG EXTRA_APKS
ARG EXTRA_EXTS
ARG EXTRA_PECL
RUN /usr/bin/install-extras

COPY scripts/ /usr/bin/
COPY tpl /tpl

ARG GLOBAL_REQUIRE=hirak/prestissimo:^0.3.7
ENV COMPOSER_HOME /composer
RUN { [[ -z "$GLOBAL_REQUIRE" ]] || composer-global $GLOBAL_REQUIRE; } \
    && mkdir -p /var/www/html \
    && echo '<?php echo phpinfo();' >/var/www/html/index.php
