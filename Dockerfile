FROM richarvey/nginx-php-fpm:1.3.10

ENV DOCKERIZE_VERSION v0.4.0
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && apk --no-cache add jq \
    && easy_install supervisor==3.3.1  # suppress include-file warnings in supervisord

ENV CODE_BASE /var/www/html
ENV GIT_SSH /usr/bin/git-ssh
ENV COMPOSER_OPTIONS --no-dev

VOLUME /etc/letsencrypt

CMD ["/usr/bin/start-container"]

COPY scripts/install-extras /usr/bin/

ARG EXTRA_APKS
ARG EXTRA_EXTS
ARG EXTRA_PECL
RUN /usr/bin/install-extras

COPY scripts/ /usr/bin/
COPY tpl /tpl

ARG GLOBAL_REQUIRE=hirak/prestissimo
ENV COMPOSER_HOME /composer
RUN [[ -z "$GLOBAL_REQUIRE" ]] || composer-global $GLOBAL_REQUIRE
