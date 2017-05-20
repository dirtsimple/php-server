FROM richarvey/nginx-php-fpm:1.2.0

LABEL traefik.port=80
ARG EXTRA_APKS
ARG EXTRA_EXTS

RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community/" >> /etc/apk/repositories && \
    apk update && apk add --no-cache gomplate $EXTRA_APKS
RUN if [ ! -z "$EXTRA_EXTS" ] ; then docker-php-ext-install $EXTRA_EXTS ; fi

ADD tpl /tpl
ADD start.sh /start.sh
