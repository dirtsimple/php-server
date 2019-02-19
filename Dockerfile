FROM jwilder/dockerize:0.6.0 AS dockerize
FROM bashitup/alpine-tools:latest AS tools

FROM richarvey/nginx-php-fpm:1.3.10
COPY --from=dockerize /usr/local/bin/dockerize /usr/bin/
COPY --from=tools     /bin/yaml2json        /usr/bin/
COPY --from=tools     /bin/modd             /usr/bin/
COPY --from=tools     /bin/jq               /usr/bin/

RUN easy_install supervisor==3.3.4  # suppress include-file warnings in supervisord

ENV CODE_BASE /var/www/html
ENV GIT_SSH /usr/bin/git-ssh
ENV COMPOSER_OPTIONS --no-dev

VOLUME /etc/letsencrypt

CMD ["/usr/bin/start-container"]

COPY scripts/install-extras /usr/bin/

ARG EXTRA_APKS
ARG EXTRA_EXTS
ARG EXTRA_PECL
RUN EXTRA_APKS="ncurses $EXTRA_APKS" /usr/bin/install-extras

COPY scripts/ /usr/bin/
COPY tpl /tpl

ARG GLOBAL_REQUIRE=hirak/prestissimo:^0.3.7
ENV COMPOSER_HOME /composer
RUN [[ -z "$GLOBAL_REQUIRE" ]] || composer-global $GLOBAL_REQUIRE
