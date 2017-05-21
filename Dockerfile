FROM richarvey/nginx-php-fpm:1.2.0
LABEL traefik.port=80

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

ADD tpl /tpl
ADD start.sh /start.sh
