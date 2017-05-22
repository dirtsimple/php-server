# dirtsimple/nginx-php-fpm

This is a docker image for an alpine nginx + php-fpm combo container, with support for:

* Cloning a git repo at container start (and running `composer install` if applicable)
* Running cron jobs or other supervisord-controlled tasks
* Build arguments to allow adding extra packages and PHP extensions
* Environment-based templating of any configuration file in the container at startup
* Running any user-supplied startup scripts

Inspired by (and implemented as a wrapper over) [ngineered/nginx-php-fpm](https://github.com/ngineered/nginx-php-fpm), this image supports all of that image's [configuration flags](https://github.com/ngineered/nginx-php-fpm/blob/master/docs/config_flags.md), plus the following enhancements and bug fixes:

* Configuration files are generated using [gomplate](https://github.com/hairyhenderson/gomplate) templates instead of `sed`, and boolean environment variables can be set to `true` or `false` , not just `1` or `0`
* Your code can provide a `conf-tpl` directory with additional configuration files to be processed w/gomplate at container start time (or you can mount replacements for this image's configuration templates under `/tpl`)
* Ready-to-use support for most PHP "front controllers" (as used by Laravel, Drupal, Symfony, etc.): just set `PHP_CONTROLLER` to `/index.php` and `WEBROOT` to the directory containing it.
* HTTPS is as simple as setting a `DOMAIN`, `GIT_EMAIL`, and `LETS_ENCRYPT=true`: registration is immediate and automatic, the certs are saved in a volume by default, and renewal can be accomplished with a cron job either inside or outside the container.
* You can set `SUPERVISOR_INCLUDES` to a space-separated list of supervisord .conf files to be included in the supervisor configuration
* cron jobs are supported by setting `USE_CRON=true` and putting the job data in `/etc/crontabs/root` , `/etc/crontabs/nginx`, or a file in one of the `/etc/periodic/` subdirectories (via volume mount, startup script, `conf-tpl` or `/tpl` files)
* `php-fpm` pool parameters can be set with environment vars (`FPM_PM`, `FPM_MAX_CHILDREN`, `FPM_START_SERVERS`, `FPM_MIN_SPARE_SERVERS`, `FPM_MAX_SPARE_SERVERS`, `FPM_MAX_REQUESTS`)
* nginx's `set_real_ip_from` is recursive, and supports Cloudflare (via `REAL_IP_CLOUDFLARE=true`) as well as your own load balancers/proxies (via `REAL_IP_FROM`)
* Additional alpine APKs, PHP core extensions, and pecl extensions can be installed using the `EXTRA_APKS`, `EXTRA_EXTS`, and `EXTRA_PECL` build-time arguments, respectively.
* composer-installed files are properly chowned, and cloned files are chowned to the correct `PUID`/`PGID` instead of the default `nginx` uid/gid
* `sendfile` is turned on for optimal static file performance, unless you set `VIRTUALBOX_DEV=true`
* Configuration files don't grow on each container restart
* nginx and composer are run as the nginx/`PUID` user, not root

### Adding Your Code

This image assumes your primary application code will be found in `/var/www/html`.  You can place it there via a volume mount, installation in a derived image, or by specifying a `GIT_REPO` environment variable targeting your code.

If a `GIT_REPO` is specified, the given repository will be cloned to `/var/www/html` at container startup, unless a `/var/www/html/.git` directory is already present  (e.g. in the case of a restart, or a mounted checkout).

(Important: do *not* both mount your code as a volume *and* provide a `GIT_REPO`: your code will be **erased** unless it's a git checkout, or you set `REMOVE_FILES=false` in your environment.)

Whether you're using a `GIT_REPO` or not, this image checks for the following things in the code directory (i.e., `/var/www/html`) during startup:

* a `composer.lock` file (triggering an automatic `composer install` run if found)
* a `conf-tpl/` subdirectory (triggering configuration file updates from any supplied templates; see next section for details)
* a `scripts/` subdirectory (containing startup scripts that will be run in alphanumeric order, if the `RUN_SCRIPTS` variable is set to `1` or `true`)

Note: if you are using a framework that exposes a subdirectory (like `web` or `public`) as the actual directory to be served by nginx, you must set the `WEBROOT` environment variable to that subdirectory (e.g. `/var/www/html/public`).  (Assuming you don't override the web server configuration; see more below.)

### Configuration Templating

This image uses [gomplate](https://github.com/hairyhenderson/gomplate) to generate arbitrary configuration files from templates.  Templates are loaded from two locations:

* The `/tpl` directory (created at build-time and supplied by this image)
* The `/var/www/html/conf-tpl` directory, found in your code checkout, volume mount, or derived image

The path of an output configuration file is derived from its relative path.  So, for example, the default template for `/etc/supervisord.conf` can be found in `/tpl/etc/supervisord.conf`, and can be overrridden by a template in `/var/www/html/conf-tpl/etc/supervisord.conf`.

Templates found in `/tpl` are applied at the very beginning of container startup, before code is cloned or startup scripts are run.  Templates in `conf-tpl/` are applied just after the code checkout (if any), and just before `composer install` (if applicable).

Template files are just plain text, except that they can contain Go template code like `{{getenv "WEBROOT"}}` to insert environment variables.  Please see the [gomplate](https://github.com/hairyhenderson/gomplate) documentation and [Go Text Template](https://golang.org/pkg/text/template/#hdr-Text_and_spaces) language reference for more details, and this project's  [`tpl`](https://github.com/dirtsimple/nginx-php-fpm/tree/master/tpl) subdirectory for examples.

### Nginx Configuration

#### Config Files

This image generates and uses the following configuration files in `/etc/nginx`, any or all of which can be replaced using template files under your code's `conf-tpl/etc/nginx` subdirectory:

* `nginx.conf` -- the main server configuration, with an `http` block that includes any server configs listed in the `sites-enabled/` subdirectory
* `sites-available/default.conf` -- the default `server` block for the HTTP protocol; includes `app.conf` to specify locations and server-level settings other than the listening port/protocol.  (This file is symlinked from `sites-enabled` by default.)
* `sites-available/default-ssl.conf` -- the default `server` block for the HTTPS protocol; includes `app.conf` to specify locations and server-level settings other than the listening port/protocol/certs.  (This file is symlinked into `sites-enabled` if and only if a private key is available in `/etc/letsencrypt/live/$DOMAIN`.)
* `app.conf` -- the main app configuration for running PHP and serving files under `WEBROOT`
* `cloudflare` -- the settings needed for correct IP detection/logging when serving via cloudflare; this file is automatically included by `nginx.conf` if `REAL_IP_CLOUDFLARE`is set to `1`.

#### Environment

In addition, the following environment variables control how the above configuration files behave:

* `WEBROOT` -- used by `app.conf` to set the server's document root
* `VIRTUALBOX_DEV` -- if set to `1`, the `sendfile` option will be disabled (use this when doing development with Docker Toolbox or boot2docker with a volume synced to OS X or Windows)
* `NGINX_IPV6` -- if set to `1`, IPV6 is enabled in the http and/or https server blocks.  (Otherwise, only IPV4 is used.)

#### PHP Front Controllers

Many PHP frameworks use a central entry point like `index.php` to process all dynamic paths in the application.  If your app is like this, you need to set `PHP_CONTROLLER` to the path of this php file, relative to the document root and beginning with a `/`.  In addition, if the document root isn't the root of your code, you need to set `WEBROOT` as well.

For example, if you are deploying a Laravel application, you need to set `WEBROOT` to `/var/www/html/public`, and `PHP_CONTROLLER` to `/index.php`.  Then, any URLs that don't resolve to static files in `public` will be routed through `/index.php` instead of producing nginx 404 errors.

#### HTTPS and Let's Encrypt Support

HTTPS is automatically enabled if you set a `DOMAIN` and there's a private key in `/etc/letsencrypt/live/$DOMAIN/`.

If you also set `LETS_ENCRYPT=true` and provide a `GIT_EMAIL` address, then certbot will be automatically run at container start to obtain the necessary cert and keys.  (You may want to make `/etc/letsencrpt` a named or local volume in order to persist the certificate across container rebuilds.)

Certificate renewal can be done by running `/usr/bin/letsencrypt-renew` inside the container.  This can be done externally via `docker exec` or `docker-compose exec`, or by setting `USE_CRON=true` and adding an appropriate line to `/etc/crontabs/root`.

### Adding Extensions

Additional alpine APKs, PHP core extensions, and pecl extensions can be installed using the `EXTRA_APKS`, `EXTRA_EXTS`, and `EXTRA_PECL` build-time arguments, respectively.  For example, one might use this in a `docker-compose.yml` to build a server for Moodle:

```yaml
version: '2'

services:
  moodle:
    build:
      context: https://github.com/dirtsimple/nginx-php-fpm.git
      args:
        - EXTRA_APKS=ghostscript graphviz aspell-dev libmemcached-dev cyrus-sasl-dev
        - EXTRA_EXTS=xmlrpc pspell
        - EXTRA_PECL=memcached
    environment:
      - GIT_REPO=https://github.com/moodle/moodle.git
      - GIT_BRANCH=MOODLE_33_STABLE
```
