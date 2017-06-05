# dirtsimple/php-server

### Overview

This is a docker image for an alpine nginx + php-fpm combo container, with support for:

* Cloning a git repo at container start (and running `composer install` if applicable)
* Running cron jobs or other supervisord-controlled tasks
* Build arguments to allow adding extra packages and PHP extensions
* Environment-based templating of any configuration file in the container at startup
* Running any user-supplied startup scripts
* 100% automated HTTPS certificate management via certbot and Let's Encrypt

Inspired by (and implemented as a backward-compatible wrapper over) [ngineered/nginx-php-fpm](https://github.com/ngineered/nginx-php-fpm), this image supports all of that image's [configuration flags](https://github.com/ngineered/nginx-php-fpm/blob/master/docs/config_flags.md), plus the following enhancements and bug fixes:

* Configuration files are generated using [dockerize templates](https://github.com/jwilder/dockerize#using-templates) instead of `sed`, and boolean environment variables can be set to `true` or `false` , not just `1` or `0`
* Your code can provide additional configuration files to be processed w/dockerize at container start time (or you can mount replacements for this image's configuration templates under `/tpl`)
* Ready-to-use support for most PHP "front controllers" (as used by Wordpress, Laravel, Drupal, Symfony, etc.): just set `PHP_CONTROLLER` to `true` and `PUBLIC_DIR` to the subdirectory that contains the relevant `index.php` (if any).  (`PATH_INFO` support is also available, for e.g. Moodle.)
* HTTPS is as simple as setting a `DOMAIN` and `LETS_ENCRYPT=my@email`: registration and renewals are immediate, painless, and 100% automatic.  The certs are saved in a volume by default, and renewals happen on container restart, as well as monthly if you enable cron.
* cron jobs are supported by setting `USE_CRON=true` and putting the job data in `/etc/crontabs/nginx`, or an executable file in one of the `/etc/periodic/` subdirectories (via volume mount, startup script, or template files)
* You can add `.ini` files to `/etc/supervisor.d/` to add additional processes to the base supervisor configuration, or to override the default supervisor configurations for nginx, php-fpm, etc.
* `php-fpm` pool parameters can be set with environment vars (`FPM_PM`, `FPM_MAX_CHILDREN`, `FPM_START_SERVERS`, `FPM_MIN_SPARE_SERVERS`, `FPM_MAX_SPARE_SERVERS`, `FPM_MAX_REQUESTS`)
* nginx's `set_real_ip_from` is recursive, and supports Cloudflare (via `REAL_IP_CLOUDFLARE=true`) as well as your own load balancers/proxies (via `REAL_IP_FROM`)
* Additional alpine APKs, PHP core extensions, and pecl extensions can be installed using the `EXTRA_APKS`, `EXTRA_EXTS`, and `EXTRA_PECL` build-time arguments, respectively.
* `sendfile` is turned on for optimal static file performance, unless you set `VIRTUALBOX_DEV=true`
* Configuration files don't grow on each container restart
* Developer and server priviliges are kept separate: git and composer are run as a `developer` user rather than as root, and files are owned by that user.  To be written to by PHP and the web server, files or directories must be explicitly listed in `NGINX_WRITABLE`.  The whole codebase is `NGINX_READABLE` by default, but can be made more restrictive by listing specific directories.
* You can mount your code anywhere, not just `/var/www/html` (just set `CODE_BASE` to whatever directory you like)

### Adding Your Code

This image assumes your primary application code will be found in the directory given by `CODE_BASE` (which defaults to `/var/www/html`).  You can place it there via a volume mount, installation in a derived image, or by specifying a `GIT_REPO` environment variable targeting your code.

If a `GIT_REPO` is specified, the given repository will be cloned to the `CODE_BASE` directory at container startup, unless a `.git` subdirectory is already present  (e.g. in the case of a restart, or a mounted checkout).  If `GIT_BRANCH` is set, the specified branch will be used.  You can also supply a base64-encoded `SSH_KEY` to access protected repositories (including any checkouts done by `composer`).

(Important: do *not* both mount your code as a volume *and* provide a `GIT_REPO`: your code will be **erased** unless it's already a git checkout, or you set `REMOVE_FILES=false` in your environment.)

Whether you're using a `GIT_REPO` or not, this image checks for the following things in the `CODE_BASE` directory during startup:

* a `composer.lock` file (triggering an automatic `composer install` run if found)
* Any configuration template directories specified in `DOCKERIZE_TEMPLATES` (see "Configuration Templating" below for details)
* A startup scripts directory (specified by `RUN_SCRIPTS`) containing scripts that will be **run as root** in glob-sorted order during container startup, just before `supervisord` is launched.  (The directory name defaults to `scripts` if `RUN_SCRIPTS` is set to `1`,  `true`, `TRUE`, `T`, or `t`.)  These scripts **must not** be writable by the nginx user; the container will refuse to start if any of them are.

Note: if you are using a framework that exposes a subdirectory (like `web` or `public`) as the actual directory to be served by nginx, you must set the `PUBLIC_DIR` environment variable to that subdirectory (e.g. `public`).  (Assuming you don't override the default web server configuration; see more below.)

#### Pulling Updates and Pushing Changes

You can pull updates from `GIT_REPO` to `CODE_BASE` by running the `pull` command via `docker exec` or `docker-compose exec`, as appropriate.  If the pull is successful, the container will immediately shutdown so that it will reflect any changed configuration upon restart.  If you're using a docker-compose container with `restart: always`, the container should automatically restart.  Otherwise you will need to explicitly start the container again.

(Note that you must set `GIT_NAME` to a commiter name, and `GIT_EMAIL` to a committer email, in order for pull operations to work correctly.)

For compatibility with ngineered/nginx-php-fpm, there is also a `push` command that adds all non-gitignored files, commits them with a generic message, and pushes them to the origin.  (You're probably better off looking at the script as a guide to implementing your own, unless those are your exact requirements.)

#### Permissions and the `developer` User

If you use any of the `git` or `composer` features of this image, they will be run using a special `developer` user that's created on-demand.  This user is created inside the container, but you can set `DEVELOPER_UID` and/or `DEVELOPER_GID` so that the created user will have the right permissions to access or update files mounted from outside the container.  Once the user is created, ownership of the `CODE_BASE` root directory is changed to `developer`.  (Any existing contents retain their existing ownership and permissions.)

If you need to run tasks inside the container as the developer user, you can use the `as-developer` script, e.g. `as-developer composer install`.  (The `push` and `pull` commands and the container start script already use `as-developer` internally to run git and composer.)


### Configuration Templating

This image uses [dockerize templates](https://github.com/jwilder/dockerize#using-templates) to generate arbitrary configuration files from templates.  Templates are loaded first from the image's  bundled`/tpl` directory, and then from the subdirectories of  `CODE_BASE` identified by the `DOCKERIZE_TEMPLATES` environment variable.

If used, `DOCKERIZE_TEMPLATES` should be a space-separated series of `source:destination` directory name pairs.  For example, if it were set to this:

````
.tpl:/ .nginx:/etc/nginx .supervisor:/etc/supervisor.d .periodic:/etc/periodic
````

it would mean that your project could contain a `.tpl` directory, whose contents would be recursively expanded to the root directory,  an `.nginx` subdirectory expanded into `/etc/nginx`, and so on.  Source and destination can both be absolute or relative; relative paths are interpreted relative to `CODE_BASE`.

The path of an output configuration file is derived from its relative path.  So, for example, the default template for `/etc/supervisord.conf` can be found in `/tpl/etc/supervisord.conf`, and with the above `DOCKERIZE_TEMPLATES` setting it could be overrridden by a template in `$CODE_BASE/.tpl/etc/supervisord.conf`.

Templates found in the image-supplied `/tpl` are applied at the very beginning of container startup, before code is cloned or startup scripts are run.  Templates in `DOCKERIZE_TEMPLATES` directories are applied just after the code checkout (if any), and just before `composer install` (if applicable).

Template files are just plain text, except that they can contain Go template code like `{{.Env.DOMAIN}}` to insert environment variables.  Please see the [dockerize documentation](https://github.com/jwilder/dockerize#using-templates) and [Go Text Template](https://golang.org/pkg/text/template/#hdr-Text_and_spaces) language reference for more details, and this project's  [`tpl`](https://github.com/dirtsimple/php-server/tree/master/tpl) subdirectory for examples.

(Note: for improved security, template files are not processed if they are writable by the `nginx` user.  If even *one* template file is writable by the web server or php-fpm, the container will refuse to start.)

### Nginx Configuration

#### Config Files

This image generates and uses the following configuration files in `/etc/nginx`, any or all of which can be replaced using mounts or template files:

* `app.conf` -- the main app configuration for running PHP and serving files under the document root.  In general, if you need to change your nginx configuration, this is the first place to look.  Its contents are included *inside* of the `server {}` blocks for both the http and https servers, so they can both be configured from one file.
* `http.conf` -- extra configuration for the `http {}` block, empty by default.  (Use this to define maps, caches, additional servers, etc.)
* `nginx.conf` -- the main server configuration, with an `http` block that includes `http.conf` and any server configs listed in the `sites-enabled/` subdirectory
* `sites-available/default.conf` -- the default `server` block for the HTTP protocol; includes `app.conf` to specify locations and server-level settings other than the listening port/protocol.  (This file is symlinked from `sites-enabled` by default.)
* `sites-available/default-ssl.conf` -- the default `server` block for the HTTPS protocol; includes `app.conf` to specify locations and server-level settings other than the listening port/protocol/certs.  (This file is symlinked into `sites-enabled` by default, but does nothing unless `$DOMAIN` is set and a private key is available in `/etc/letsencrypt/live/$DOMAIN`.)
* `cloudflare.conf` -- the settings needed for correct IP detection/logging when serving via cloudflare; this file is automatically included by `nginx.conf` if `REAL_IP_CLOUDFLARE`is set to `1`.

For backwards compatibility with `ngineered/nginx-php-fpm`, you can include a `conf/nginx/nginx-site.conf` and/or `conf/nginx/nginx-site-ssl.conf` in your `CODE_BASE` directory.  Doing this will, however, disable any features of `app.conf` that you don't copy into them.  It's recommended that you use `.nginx/app.conf` instead, going forward.

#### Environment

In addition, the following environment variables control how the above configuration files behave:

* `PUBLIC_DIR` -- the subdirectory of `CODE_BASE` that should be used as the server's default document root.  If not specified, `CODE_BASE` is used as the default document root.
* `FORCE_HTTPS` -- boolean: redirect all http requests to https; if `REAL_IP_CLOUDFLARE` is in effect, X-Forwarded-Proto is used to determine whether the request is https
* `NGINX_IPV6` -- boolean: enables IPV6 in the http and/or https server blocks.  (Otherwise, only IPV4 is used.)
* `STATIC_EXPIRES` -- expiration time to use for static files; if not set, use nginx defaults
* `VIRTUALBOX_DEV` -- boolean: disables the `sendfile` option (use this when doing development with Docker Toolbox or boot2docker with a volume synced to OS X or Windows)

If you want extreme backward compatibility with the default settings of `ngineered/nginx-php-fpm`, you can use the following settings:

* `NGD_404=true` (use the ngineered-branded 404 handler from `ngineered/nginx-php-fpm` instead of nginx's default 404 handling)
* `NGINX_IPV6=true`
* `STATIC_EXPIRES=5d`
* `VIRTUALBOX_DEV=true` (not really needed unless you're actually using virtualbox)
* `NGINX_READABLE=.` and `NGINX_WRITABLE=.`, to make the entire codebase readable and writable by nginx+php

#### PHP Front Controllers and `PATH_INFO`

Many PHP frameworks use a central entry point like `index.php` to process all dynamic paths in the application.  If your app is like this, you can set `PHP_CONTROLLER` to `true` to get a default front controller of `/index.php?$args` -- a value that works for correctly a wide variety of PHP applications and frameworks.  If your front controller isn't `index.php` or needs different parameters, you can specify the exact URI to be used instead of `true`.  (If the document root isn't the root of your code, you need to set `PUBLIC_DIR` as well.

For example, if you are deploying a Laravel application, you need to set `PUBLIC_DIR` to `public`, and `PHP_CONTROLLER` to `true`.  Then, any URLs that don't resolve to static files in `public` will be routed through `/index.php` instead of producing nginx 404 errors.

By default, `PATH_INFO` is disabled, meaning that you cannot add trailing paths after .php files.  If you need this (e.g. for Moodle), you can set `USE_PATH_INFO` to `true`, and then you can access urls like `/some/file.php/other/stuff`.  As long as `/some/file.php` exists, then it will be run with `$_SERVER['PATH_INFO']` set to `/other/stuff`.  If you also enable `PHP_CONTROLLER`, then the default `PHP_CONTROLLER` will be `/index.php$uri?$args`, so that the front controller gets `PATH_INFO` set as well.  (You can override this by explicitly setting `PHP_CONTROLLER` to the exact expression desired.)

#### File Permissions

For security, you must specifically make files readable or writable by nginx and php, using the `NGINX_READABLE` and `NGINX_WRITABLE` variables.  Each is a space-separated lists of files or directories which will be recursively `chgrp`'d to nginx and made group-readable or group-writable, respectively.  Paths are interpreted relative to `CODE_BASE`, and the default `NGINX_READABLE` is `.`, meaning the entire code base is readable by default.  If you are using a web framework that writes to the code base, you must add the affected directories and/or files to `NGINX_WRITABLE`.

Note: file permissions are applied prior to processing template files and running startup scripts, so if you make your entire codebase writable you will not be able to use configuration templates or startup scripts.  You will need to explicitly list subdirectories of your code that do not include your templates or startup scripts, to preserve separation of privileges within the container.

#### HTTPS and Let's Encrypt Support

HTTPS is automatically enabled if you set a `DOMAIN` and there's a private key in `/etc/letsencrypt/live/$DOMAIN/`.

If you want the key and certificate to be automatically generated, just set `LETS_ENCRYPT` to your desired registration email address, and `certbot` will automatically run at container start, either to perform the initial registration or renew the existing certificate.  (You may want to make `/etc/letsencrpt` a named or local volume in order to ensure the certificate persists across container rebuilds.)

If your container isn't restarted often enough to ensure timely certificate renewals, you can set `USE_CRON=true`, and an automatic renewal attempt will also happen on the first of each month at approximately 5am UTC.

(Note: certbot uses the "webroot" method of authentication, so the document root of `DOMAIN` **must** be the server's default document root (i.e. `$CODE_BASE/$PUBLIC_DIR`), or else certificate authentication will fail.  Once a certificate has been requested, the default document root directory must remain the same for all future renewals.)

### Adding Extensions

Additional alpine APKs, PHP core extensions, and pecl extensions can be installed using the `EXTRA_APKS`, `EXTRA_EXTS`, and `EXTRA_PECL` build-time arguments, respectively.  For example, one might use this in a `docker-compose.yml` to build a server for Moodle:

```yaml
version: '2'

services:
  moodle:
    build:
      context: https://github.com/dirtsimple/php-server.git
      args:
        - EXTRA_APKS=ghostscript graphviz aspell-dev libmemcached-dev cyrus-sasl-dev openldap-dev
        - EXTRA_EXTS=xmlrpc pspell ldap
        - EXTRA_PECL=memcached
    environment:
      - GIT_REPO=https://github.com/moodle/moodle.git
      - GIT_BRANCH=MOODLE_33_STABLE
      - NGINX_WRITABLE=/moodledata
      - USE_PATH_INFO=true
```

For performance's sake, it's generally better to specify extras at build-time, but as a development convenience you can also pass them to the container as environment variables to be installed or built during container startup.  (Which, of course, will be slower as a result.)

### Cron and Other Supervised Tasks

Any files named `/etc/supervisor.d/*.ini` are included as part of the supervisord configuration, so that you can add your own supervised tasks.  (For example, if you wanted to add a mysql or openssh server.)  This image's own tasks are there as well, and can be overridden by your own substitutions in `/tpl/etc/supervisor.d` or a `DOCKERIZE_TEMPLATES` directory:

* `nginx.ini`
* `php-fpm.ini`
* `certbot.ini` -- run registration or renewal if `LETS_ENCRYPT` and `DOMAIN` are set
* `cron.ini` -- run crond if `USE_CRON=true`

You can override any of these with an empty file to disable the relevant functionality.

If you want to add cron jobs, you have two options:

* Generate a `/etc/crontabs/nginx` crontab file
* Add scripts to a subdirectory of `/etc/periodic`.  Scripts must be in a subdirectory named `15min`, `hourly`, `daily`, `weekly`, or `monthly`  (e.g.  a script placed in `/etc/periodic/daily` would be run daily)

Cron jobs listed in the  `/etc/crontabs/nginx` file will run as the `nginx` user; scripts in `/etc/periodic/` dirs run as root.  You can preface commands in those scripts with `as-nginx` to run them as the nginx user, or `as-developer` to run them with developer privileges.  (Note: the templates for scripts to be placed in `/etc/periodic` *must* have their executable bit set in order to run!)

As always, these configuration files can be generated by mounting templates in `/tpl` or via a `DOCKERIZE_TEMPLATES ` directory inside your codebase.