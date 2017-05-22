FROM richarvey/nginx-php-fpm:1.2.0

VOLUME /etc/letsencrypt

ARG EXTRA_APKS
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community/" >> /etc/apk/repositories && \
    apk update && apk add --no-cache gomplate $EXTRA_APKS

ARG EXTRA_EXTS
RUN if [ ! -z "$EXTRA_EXTS" ] ; then docker-php-ext-install $EXTRA_EXTS ; fi

ARG EXTRA_PECL
RUN if [ ! -z "$EXTRA_PECL" ] ; then \
        docker-php-source extract && \
        apk add --no-cache --virtual .phpize-deps $PHPIZE_DEPS && \
        pecl install $EXTRA_PECL && \
        docker-php-ext-enable $EXTRA_PECL && \
        apk del .phpize-deps && \
        docker-php-source delete; \
    fi

COPY tpl /tpl
COPY start.sh /start.sh
COPY scripts/ /usr/bin/

ENV WEBROOT /var/www/html
