FROM richarvey/nginx-php-fpm:1.2.0
ARG EXTRA_APKS
RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community/" >> /etc/apk/repositories && \
    apk update && apk add --no-cache gomplate $EXTRA_APKS
ADD tpl /tpl
ADD start.sh /start.sh
ARG EXTRA_EXTS
RUN if [ ! -z "$EXTRA_EXTS" ] ; then docker-php-ext-install $EXTRA_EXTS ; fi
