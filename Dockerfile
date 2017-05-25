FROM richarvey/nginx-php-fpm:1.2.0

ENV CODE_BASE /var/www/html
ENV GIT_SSH /usr/bin/git-ssh

VOLUME /etc/letsencrypt

CMD ["/usr/bin/start-container"]

COPY scripts/install-extras /usr/bin/

ARG EXTRA_APKS
ARG EXTRA_EXTS
ARG EXTRA_PECL

RUN echo "http://dl-cdn.alpinelinux.org/alpine/edge/community/" >> /etc/apk/repositories && \
    apk update && apk add --no-cache gomplate && /usr/bin/install-extras
RUN easy_install supervisor==3.3.1  # suppress include file warnings

COPY scripts/ /usr/bin/
COPY tpl /tpl

