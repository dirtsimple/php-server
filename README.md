# dirtsimple/php-server

### Overview

This is a docker image for an alpine nginx + php-fpm combo container, with support for:

* Cloning a git repo at container start (and running `composer install` if applicable)
* Running scheduled jobs (cron), on-file-change jobs ([cortesi/modd](https://github.com/cortesi/modd)), webhooks ([adnanh/webhook](#webhooks-adnanhwebhook)), or other supervisord-controlled tasks
* Build arguments to allow adding extra packages and PHP extensions
* Environment-based templating of any configuration file in the container at startup
* Running any user-supplied startup scripts
* 100% automated HTTPS certificate management via certbot and Let's Encrypt
* Robust privilege separation and defense-in-depth for a variety of development and production use cases

Inspired by [richarvey/nginx-php-fpm](https://gitlab.com/ric_harvey/nginx-php-fpm), this image supports most of that image's [configuration flags](https://gitlab.com/ric_harvey/nginx-php-fpm/blob/1.5.7/docs/config_flags.md), plus many, many enhancements and bug fixes like these:

* Configuration files are generated using [dockerize templates](https://github.com/jwilder/dockerize#using-templates) instead of `sed`, and boolean environment variables can be set to `true` or `false` , not just `1` or `0`
* Your code can provide additional configuration files to be processed w/dockerize at container start time (or you can mount replacements for this image's configuration templates under `/tpl`)
* Ready-to-use support for most PHP "front controllers" (as used by Wordpress, Laravel, Drupal, Symfony, etc.): just set `PHP_CONTROLLER` to `true` and `PUBLIC_DIR` to the subdirectory that contains the relevant `index.php` (if any).  (`PATH_INFO` support is also available, for e.g. Moodle.)
* HTTPS is as simple as setting a `DOMAIN` and `LETS_ENCRYPT=my@email`: registration and renewals are immediate, painless, and 100% automatic.  The certs are saved in a volume by default, and renewals happen on container restart, as well as monthly if you enable cron.
* cron jobs are supported by setting `USE_CRON=true` and putting the job data in `/etc/crontabs/nginx`, or an executable file in one of the `/etc/periodic/` subdirectories (via volume mount, startup script, or template files)
* You can add `.ini` files to `/etc/supervisor.d/` to add additional processes to the base supervisor configuration, or to override the default supervisor configurations for nginx, php-fpm, etc.
* `php-fpm` pool parameters can be set with environment vars (`FPM_PM`, `FPM_MAX_CHILDREN`, `FPM_START_SERVERS`, `FPM_MIN_SPARE_SERVERS`, `FPM_MAX_SPARE_SERVERS`, `FPM_MAX_REQUESTS`)
* nginx's `set_real_ip_from` is recursive, and supports Cloudflare (via `REAL_IP_CLOUDFLARE=true`) as well as your own load balancers/proxies (via `REAL_IP_FROM` -- which can include multiple addresses, separated by spaces.)
* Additional alpine APKs, PHP core extensions, and pecl extensions can be installed by setting `EXTRA_APKS`, `EXTRA_EXTS`, and `EXTRA_PECL` as environment variables or build-time arguments.
* `sendfile` is turned on for optimal static file performance, unless you set `VIRTUALBOX_DEV=true`
* Configuration files don't grow on each container restart
* Developer and server priviliges are kept separate: git and composer are run as a `developer` user rather than as root, and files are owned by that user.  To be written to by PHP and the web server, files or directories must be explicitly listed in `NGINX_WRITABLE`.  (The whole codebase is `NGINX_READABLE` by default, but can be made more restrictive by listing specific directories.)
* You can mount your code anywhere, not just `/var/www/html` (just set `CODE_BASE` to whatever directory you like)
* If any supervised process (nginx, php-fpm, cron, etc.) enters a `FATAL` state, the entire container is shut down, so that configuration or other errors don't produce a silently unresponsive container.
* Command-line PHP scripts run with a file-based opcache under `/tmp`, speeding start times for large PHP command line tools such as `wp-cli`, `artisan`, etc.  (For compatibility reasons, this cache is disabled when `ENABLE_XDEBUG` is true.)  Command-line scripts run without a memory limit, unless you set `PHP_CLI_MEMORY` to a memory value like `512M`.

Note: there are a few configuration options that must be specified in a different way than the richarvey image, or which have different defaults: see [Backward-Compatibility Settings](#backward-compatibility-settings), below, for more info.

### Contents

<!-- toc -->

- [Adding Your Code](#adding-your-code)
  * [Pulling Updates and Pushing Changes](#pulling-updates-and-pushing-changes)
  * [Permissions and the `developer` User](#permissions-and-the-developer-user)
  * [Composer Configuration, `PATH`, and Tools](#composer-configuration-path--and-tools)
- [Configuration Templating](#configuration-templating)
- [Nginx Configuration](#nginx-configuration)
  * [Config Files](#config-files)
  * [Environment](#environment)
  * [Backward-Compatibility Settings](#backward-compatibility-settings)
  * [PHP Front Controllers and `PATH_INFO`](#php-front-controllers-and-path_info)
  * [File Permissions](#file-permissions)
  * [HTTPS and Let's Encrypt Support](#https-and-lets-encrypt-support)
- [Adding Extensions](#adding-extensions)
- [Supervised Tasks](#supervised-tasks)
  * [Scheduled Jobs (cron)](#scheduled-jobs-cron)
  * [Changed-File Jobs (modd)](#changed-file-jobs-modd)
  * [Webhooks (adnanh/webhook)](#webhooks-adnanhwebhook)
- [Version Info](#version-info)

<!-- tocstop -->

### Adding Your Code

This image assumes your primary application code will be found in the directory given by `CODE_BASE` (which defaults to `/var/www/html`).  You can place it there via a volume mount, installation in a derived image, or by specifying a `GIT_REPO` environment variable targeting your code.

If a `GIT_REPO` is specified, the given repository will be cloned to the `CODE_BASE` directory at container startup, unless a `.git` subdirectory is already present  (e.g. in the case of a restart, or a mounted checkout).  If `GIT_BRANCH` is set, the specified branch will be used.  You can also supply a base64-encoded `SSH_KEY` to access protected repositories (including any checkouts done by `composer`).

(Important: do *not* both mount your code as a volume *and* provide a `GIT_REPO`: your code will be **erased** unless it's already a git checkout, or you set `REMOVE_FILES=false` in your environment.)

Whether you're using a `GIT_REPO` or not, this image checks for the following things in the `CODE_BASE` directory during startup:

* a `composer.lock` file (triggering an automatic `composer install` run if found)
* Any configuration template directories specified in `DOCKERIZE_TEMPLATES` (see "Configuration Templating" below for details)
* A list of startup scripts (or globs thereof),  specified by `RUN_SCRIPTS` that will be **run as root** in glob-sorted order during container startup, just before `supervisord` is launched.  (The search pattern defaults to `scripts/*` if `RUN_SCRIPTS` is set to `1`,  `true`, `TRUE`, `T`, or `t`.)  These scripts **must not** be writable by the nginx user; the container will refuse to start if any of them are.  (`RUN_SCRIPTS` can be a space-separated list of individual scripts in order to force them to be run in that order; if they are globs then each group will be glob-sorted but the order of groups will be as defined by `RUN_SCRIPTS`.)

Note: if you are using a framework that exposes a subdirectory (like `web` or `public`) as the actual directory to be served by nginx, you must set the `PUBLIC_DIR` environment variable to that subdirectory (e.g. `public`).  (Assuming you don't override the default web server configuration; see more below.)

#### Pulling Updates and Pushing Changes

You can pull updates from `GIT_REPO` to `CODE_BASE` by running the `pull` command via `docker exec` or `docker-compose exec`, as appropriate.  If the pull is successful, the container will immediately shutdown so that it will reflect any changed configuration upon restart.  If you're using a docker-compose container with `restart: always`, the container should automatically restart.  Otherwise you will need to explicitly start the container again.

(Note that you must set `GIT_NAME` to a commiter name, and `GIT_EMAIL` to a committer email, in order for pull operations to work correctly.)

For compatibility with richarvey/nginx-php-fpm, there is also a `push` command that adds all non-gitignored files, commits them with a generic message, and pushes them to the origin.  (You're probably better off looking at the script as a guide to implementing your own, unless those are your exact requirements.)

#### Permissions and the `developer` User

If you use any of the `git` or `composer` features of this image, they will be run using a special `developer` user that's created on-demand.  This user is created inside the container, but you can set `DEVELOPER_UID` and/or `DEVELOPER_GID` so that the created user will have the right permissions to access or update files mounted from outside the container.  The developer user is also added to the `nginx` group inside the container, so that it can read and write files created by the app.  Once the user is created, ownership of the entire  `CODE_BASE` directory tree is changed to `developer`.

If you need to run tasks inside the container as the developer user, you can use the `as-developer` script, e.g. `as-developer composer install`.  (The `push` and `pull` commands and the container start script already use `as-developer` internally to run git and composer.)

#### Composer Configuration, `PATH`,  and Tools

When running a command under `as-developer`, the `PATH` is expanded to include `$COMPOSER_HOME/vendor/bin` and `$CODE_BASE/vendor/bin`.  This allows you to easily run project-specific tools, and *also* to override them with globally-installed tools using `GLOBAL_REQUIRE`.

Setting the `GLOBAL_REQUIRE` environment variable to a series of package specifiers causes them to be installed globally, just after templates are processed and before the project-level composer install.  For example setting  `GLOBAL_REQUIRE` to `"psy/psysh wp-cli/wp-cli"`  would install both Psysh and the Wordpress command line tools as part of the container.

(You can also use `GLOBAL_REQUIRE` as a build-time argument, to specify packages to be built into the container.)

The `COMPOSER_OPTIONS` variable can also be set to change the command line options used by the default `composer install` run.  It defaults to `--no-dev --optimize-autoloader`, but can be set to an empty string for a development environment.  If you need finer control over the installation process, you can also disable automatic installation by setting `SKIP_COMPOSER=true`, and then running your own installation scripts with `RUN_SCRIPTS` (which are run right after the composer-install step.

Last but not least, you can set `COMPOSER_CONFIG_JSON` to a string of JSON to be placed in `$COMPOSER_HOME/config.json`.  This can be useful for adding site-specific repository or authentication information to a project's `composer.json`.  (New in version 1.2)

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
* `*.app.conf` -- any files named with this pattern are loaded immediately after `app.conf`; by adding files named this way, you can extend the base configuration without needing to copy the default `app.conf`.
* `webhooks.app.conf` -- proxy configuration for the [webhooks tool](#webhooks-adnanhwebhook); you can override this to customize webhook routing or add extra authorization requirements for connections coming from outside the container.
* `static.conf` -- configuration for static files.  This is included in `app.conf` under any `EXCLUDE_PHP` locations.  With the exception of `expires`, any settings here should be wrapped in location sub-blocks.  The default version of this file includes settings for nginx's mp4 and flv modules, linked to the appropriate file types.
* `http.conf` -- extra configuration for the `http {}` block, empty by default.  (Use this to define maps, caches, additional servers, etc.)
* `nginx.conf` -- the main server configuration, with an `http` block that includes `http.conf` and any server configs listed in the `sites-enabled/` subdirectory
* `sites-available/default.conf` -- the `server` block for the HTTP and HTTPS protocol; includes `app.conf` to specify locations and server-level settings other than the listening port/protocol/certs/etc.  HTTPS is only enabled if `$DOMAIN` is set and a private key is available in `/etc/letsencrypt/live/$DOMAIN`.  (This file is symlinked from `sites-enabled` by default.)
* `cloudflare.conf` -- the settings needed for correct IP detection/logging when serving via cloudflare; this file is automatically included by `nginx.conf` if `REAL_IP_CLOUDFLARE` is true.

For backwards compatibility with `richarvey/nginx-php-fpm`, you can include `conf/nginx/nginx.conf`, `conf/nginx/nginx-site.conf`, and/or `conf/nginx/nginx-site-ssl.conf` file(s) in your `CODE_BASE` directory.  Doing this will, however, disable any features of `app.conf` that you don't copy into them.  It's recommended that you use `.nginx/app.conf` instead, going forward.

#### Environment

In addition, the following environment variables control how the above configuration files behave:

* `PUBLIC_DIR` -- the subdirectory of `CODE_BASE` that should be used as the server's default document root.  If not specified, `CODE_BASE` is used as the default document root.
* `EXCLUDE_PHP` -- a space-separated list of absolute location prefixes where PHP code should **not** be executed (e.g. `/wp-content/uploads` for Wordpress's file upload directory).  Within these locations, paths containing `.php` will return 404 errors, and everything else will be processed according to the rules in `static.conf`
* `FORCE_HTTPS` -- boolean: redirect all http requests to https; if `FORWARDED_SSL` is in effect, X-Forwarded-Proto is used to determine whether the request is https
* `REAL_IP_CLOUDFLARE` -- boolean: if true, trust Cloudflare to provide the true client IP, using the addresses listed in `cloudflare.conf`
* `REAL_IP_FROM` -- space-separated list of address/netmask values designating proxies to trust as to the identity of the real client's IP
* `FORWARDED_SSL` -- boolean: if true, trust Cloudflare or other proxies to say whether the connection is HTTPS or not, and override the `HTTPS`, `SERVER_NAME`, and `SERVER_PORT` fastcgi variables to match
* `PHP_ACCESS_LOG` and `STATIC_ACCESS_LOG` -- the `access_log` settings to be used for PHP and static files, defaulting to `/dev/stdout` and `off`, respectively.
* `PHP_LOG_ERRORS` -- boolean: if true, turns on PHP's `log_errors` setting.  True by default.
* `APP_URL_PREFIX` -- a prefix to put in front of the `SCRIPT_NAME`, `REQUEST_URI`, and `DOCUMENT_URI` passed to PHP.  This should only be used when behind a proxy that is removing this prefix, e.g. when using a traefik `PathPrefixStrip`  rule.  (Note that apps which assume a static relationship between URIs and `DOCUMENT_ROOT` will not work properly with this setting and may require patching.)
* `USE_FORWARDED_PREFIX` -- boolean: use traefik's `X-Forwarded-Prefix` header to determine the `APP_URL_PREFIX`.  Only takes effect if `APP_URL_PREFIX` isn't set, and you should not use this unless the app is behind a proxy that *always* sets this header (e.g. traefik 1.3+ with a `PathPrefixStrip` rule).
* `NGINX_IPV6` -- boolean: enables IPV6 in the http and/or https server blocks.  (Otherwise, only IPV4 is used.)
* `NGINX_WORKERS` -- number of nginx worker processes; defaults to 1
* `STATIC_EXPIRES` -- expiration time to use for static files; if not set, use nginx defaults
* `VIRTUALBOX_DEV` -- boolean: disables the `sendfile` option (use this when doing development with Docker Toolbox or boot2docker with a volume synced to OS X or Windows)

#### Backward-Compatibility Settings

If you want extreme backward compatibility with the default settings of `richarvey/nginx-php-fpm`, you can use the following settings:

* `NGINX_IPV6=true`
* `STATIC_EXPIRES=5d`
* `VIRTUALBOX_DEV=true` (not really needed unless you're actually using virtualbox)
* `NGINX_READABLE=.` and `NGINX_WRITABLE=.`, to make the entire codebase readable and writable by nginx+php (which is much less secure)
* `NGINX_WORKERS=auto`
* `PHP_LOG_ERRORS=false`
* `EXTRA_EXTS=pgsql pdo_pgsql redis xsl soap xdebug` (if you need any of these extensions)
* `EXTRA_APKS=nginx-mod-http-geoip nginx-mod-stream-geoip` (if you need nginx geoip modules)

The following features of `richarvey/nginx-php-fpm` are not directly supported by this image, and must be configured in a different way:

* `APPLICATION_ENV=development` -- set `COMPOSER_OPTIONS` to an empty string instead to disable the `--no-dev` flag
* `SKIP_CHOWN` -- this image doesn't chown the code tree except when doing a git checkout.  But it *does* chgrp the code tree to the nginx user and set everything group readable by default, unless you explicitly set a different `NGINX_READABLE` value.  So the equivalent to `SKIP_CHOWN` would be to explicitly set `NGINX_READABLE` to empty, and not set values for any of the other permission variables (described under [File Permissions](#file-permissions) below).
* `PHP_ERRORS_STDERR` -- this image always directs the PHP error log to stderr, and logs errors by default.  To disable error output, set `PHP_LOG_ERRORS=false`.
* If you want a custom 404 page, you need to configure it via a configuration file

#### PHP Front Controllers and `PATH_INFO`

Many PHP frameworks use a central entry point like `index.php` to process all dynamic paths in the application.  If your app is like this, you can set `PHP_CONTROLLER` to `true` to get a default front controller of `/index.php$is_args$args` -- a value that works for correctly a wide variety of PHP applications and frameworks.  If your front controller isn't `index.php` or needs different parameters, you can specify the exact URI to be used instead of `true`.  (If the document root isn't the root of your code, you need to set `PUBLIC_DIR` as well.)

For example, if you are deploying a Laravel application, you need to set `PUBLIC_DIR` to `public`, and `PHP_CONTROLLER` to `true`.  Then, any URLs that don't resolve to static files in `public` will be routed through `/index.php` instead of producing nginx 404 errors.

By default, `PATH_INFO` is disabled, meaning that you cannot add trailing paths after .php files.  If you need this (e.g. for Moodle), you can set `USE_PATH_INFO` to `true`, and then you can access urls like `/some/file.php/other/stuff`.  As long as `/some/file.php` exists, then it will be run with `$_SERVER['PATH_INFO']` set to `/other/stuff`.  If you also enable `PHP_CONTROLLER`, then the default `PHP_CONTROLLER` will be `/index.php$uri?$args`, so that the front controller gets `PATH_INFO` set as well.  (You can override this by explicitly setting `PHP_CONTROLLER` to the exact expression desired.)

#### File Permissions

For security, you must specifically make files readable or writable by nginx and php, using the `NGINX_READABLE` and `NGINX_WRITABLE` variables.  Each is a space-separated lists of file or directory globs (with `**` recursion supported) which will be recursively `chgrp`'d to nginx and made group-readable or group-writable, respectively.  Paths are interpreted relative to `CODE_BASE`, and the default `NGINX_READABLE` is `.`, meaning the entire code base is readable by default.  If you are using a web framework that writes to the code base, you must add the affected directories and/or files to `NGINX_WRITABLE`.  For frameworks like wordpress that require certain files to be owned by the web server, you can use `NGINX_OWNED`.

In some cases, it may be easier to specify what should *not* be readable or writable, or to carve out specific exceptions in a larger grant of access.  For this purpose, you can remove group+world read/write/execute access via `NGINX_NO_RWX`, and group+world write access via`NGINX_NO_WRITE`.  These settings are applied *after* the readable/writable/owned ones, and so can carve out exceptions within them.

Both variables can be used to list file or directory paths that will be recursively `chown`'d to `developer` (creating the `developer` user if necessary), and then have the relevant permissions revoked.  For simplicity's sake, existing file groups are not checked, so if you are sharing files outside the container this may not do what you want or expect.

Note: file permissions are applied prior to processing template files and running startup scripts, so if you make your entire codebase writable you will not be able to use configuration templates or startup scripts.  To preserve separation of privileges within the container, you will need to explicitly list subdirectories of your code that do *not* include your templates or startup scripts, or else list those templates and startup scripts under `NGINX_NO_WRITE`.

In addition, please note that these permission changes are applied only to files and directories that actually *exist*: files created by startup scripts or nginx/php later will not magically have these permissions applied.  To get the results you want in such cases, you may need to apply permissions to a parent directory, or pre-create the necessary files or directories yourself.

#### HTTPS and Let's Encrypt Support

HTTPS is automatically enabled if you set a `DOMAIN` and there's a private key in `/etc/letsencrypt/live/$DOMAIN/`.

If you want the key and certificate to be automatically generated, just set `LETS_ENCRYPT` to your desired registration email address, and `certbot` will automatically run at container start, either to perform the initial registration or renew the existing certificate.  (You may want to make `/etc/letsencrpt` a named or local volume in order to ensure the certificate persists across container rebuilds.)

If your container isn't restarted often enough to ensure timely certificate renewals, you can set `USE_CRON=true`, and an automatic renewal attempt will also happen on the first of each month at approximately 5am UTC.

(Note: certbot uses the "webroot" method of authentication, so the document root of `DOMAIN` **must** be the server's default document root (i.e. `$CODE_BASE/$PUBLIC_DIR`), or else certificate authentication will fail.  Once a certificate has been requested, the default document root directory must remain the same for all future renewals.  Also note that the `.well-known` directory under the webroot should *not* be made inaccessible to the webserver; i.e., it needs to be `NGINX_READABLE`, at least.)

### Adding Extensions

Additional alpine APKs, PHP core extensions, and pecl extensions can be installed using the `EXTRA_APKS`, `EXTRA_EXTS`, and `EXTRA_PECL` build-time arguments, respectively.  For example, one might use this in a `docker-compose.yml` to build a server for Moodle:

```yaml
version: '2'

services:
  moodle:
    build:
      context: https://github.com/dirtsimple/php-server.git
      args:
        - PHP_VER=7.2  # build from php:7.2-fpm-alpine3.10
        - OS_VER=3.10
        - EXTRA_APKS=ghostscript graphviz
        - EXTRA_EXTS=xmlrpc pspell ldap memcached
    environment:
      - GIT_REPO=https://github.com/moodle/moodle.git
      - GIT_BRANCH=MOODLE_33_STABLE
      - NGINX_WRITABLE=/moodledata
      - USE_PATH_INFO=true
```

For performance's sake, it's generally better to specify extras at build-time, but as a development convenience you can also pass them to the container as environment variables to be installed or built during container startup.  (Which, of course, will be slower as a result.)

Specific versions of a PECL module can be forced by using a `:`, e.g. `EXTRA_PECL=mcrypt:1.0.2`.  (A `:` is used in place of a `-` so that the version can be stripped from the extension name in generated PHP .ini file(s).)

As of the 2.x versions of this image, `EXTRA_EXTS` are built using [mlocati/docker-php-extension-installer](https://github.com/mlocati/docker-php-extension-installer/), so you no longer need to specify `EXTRA_APKS` for any of the extensions it supports, and you can build supported PECL extensions using `EXTRA_EXTS`, without needing `EXTRA_PECL`, unless you need to specify a particular module version, or need an extension that isn't supported by docker-php-extension-installer.  (But in such cases, you must explicitly list any needed packages in `EXTRA_APKS`, since the automatic installer won't be handling it for you.)

### Supervised Tasks

Any files named `/etc/supervisor.d/*.ini` are included as part of the supervisord configuration, so that you can add your own supervised tasks.  (For example, if you wanted to add a mysql or openssh server.)  This image's own tasks are there as well, and can be overridden by your own substitutions in `/tpl/etc/supervisor.d` or a `DOCKERIZE_TEMPLATES` directory:

* `nginx.ini`
* `php-fpm.ini`
* `certbot.ini` -- run registration or renewal if `LETS_ENCRYPT` and `DOMAIN` are set
* `cron.ini` -- run crond if `USE_CRON=true`
* `modd.ini` -- run modd (file watcher) if `MODD_CONF` is set
* `webhook.ini` - run webhooks if `WEBHOOK_CONF` is set

You can override any of these with an empty file to disable the relevant functionality.

#### Scheduled Jobs (cron)

If you want to add cron jobs, you have two options:

* Generate a `/etc/crontabs/nginx` crontab file
* Add scripts to a subdirectory of `/etc/periodic`.  Scripts must be in a subdirectory named `15min`, `hourly`, `daily`, `weekly`, or `monthly`  (e.g.  a script placed in `/etc/periodic/daily` would be run daily)

Cron jobs listed in the  `/etc/crontabs/nginx` file will run as the `nginx` user; scripts in `/etc/periodic/` dirs run as root.  You can preface commands in those scripts with `as-nginx` to run them as the nginx user, or `as-developer` to run them with developer privileges.  (Note: the templates for scripts to be placed in `/etc/periodic` *must* have their executable bit set in order to run!)

As always, these configuration files can be generated by mounting templates in `/tpl` or via a `DOCKERIZE_TEMPLATES ` directory inside your codebase.

#### Changed-File Jobs (modd)

The bundled [modd](https://github.com/cortesi/modd) tool lets you watch for changes to files, then run other tasks automatically (such as stopping, starting, or restarting other supervised processes).  To enable this, just set `MODD_CONF` to the path of a modd config file, and a supervised modd process will be started automatically when the container starts.  If the config file changes, modd will restart itself automatically to use the updated configuration.

You can also use `MODD_OPTIONS` to supply extra global options to modd, and `MODD_DIR` to set the directory where you want it to run, if it's not `CODE_BASE`.  (If `MODD_CONF` is a relative path, it's relative to `MODD_DIR` or `CODE_BASE`.)

Please note that the modd process runs as **root**, which means that your config file must *not* be writable by nginx (or else the container will not start).  This also means you should preface most commands in your modd config file with `as-developer` or `as-nginx` to set the appropriate user ID for the task in question.  But if you need a modd job to stop or start other tasks, you can have it simply invoke `supervisorctl` with the appropriate options.

#### Webhooks (adnanh/webhook)

The bundled webhook tool optionally lets you run commands in the container upon receiving webhooks.  These variables control where, how, and whether the webhooks are served:

* `WEBHOOK_CONF` -- the name of a JSON or YAML file with the webhooks' configuration.  If not set, webhooks are disabled.  The path can be relative or absolute; a relative path is interpreted relative to `WEBHOOK_DIR`
* `WEBHOOK_USER` -- the name of the user the webhook tool will run as; defaults to `nginx`
* `WEBHOOK_DIR` -- the directory in which the webhook tool runs; defaults to `$CODE_BASE` if not set.
* `WEBHOOK_PATH` -- the path under your site's root URL at which webhooks will be accessed.  Defaults to `hooks`, meaning that a webhook with id `foo` will be reachable via nginx at `/hooks/foo`.
* `WEBHOOK_OPTS` -- additional startup arguments to pass to the webhook tool; defaults to `-hotreload -verbose`.

The webhook tool is proxied by nginx, so its port does not need to be directly exposed, and so it listens only on 127.0.0.1:9000.  If you have something else you need to run on port 9000 (and you also want to run webhooks), you can change the default port with `WEBHOOK_PORT`.

##### Security Considerations

To prevent privilege escalation from web-served PHP, the webhook tool's configuration file **must not** be writable by nginx (or else the container won't start).

The default `WEBHOOK_USER` is `nginx`, meaning the webhooks can't do anything that nginx or web-served PHP can't.  If your webhooks need greater privileges than that, you can configure the tool to run as `developer` (if code needs to be updated), or `root` (if process control via `supervisorctl` is needed).

Note, however, that this tool is very powerful, and it is ridiculously easy to accidentally create vulnerabilities, especially if you use the `developer` or `root` user.  For example, if your configuration file contains secrets (e.g. to verify a webhook is authorized), then you need to ensure it can't be *read* by the web server or php, not just written!  (Otherwise, a PHP-level exploit can find out the secret, even if the file is not located in the container's `PUBLIC_DIR`.)  Likewise, if a webhook doesn't have some sort of authorization check as part of its configuration, then **any program run inside the container** can invoke it by talking directly to port 9000.  (Again allowing access by an exploited PHP process.)

Therefore, if a command can have detrimental effects (or if it merely accepts any input whatsoever!), it should probably be protected with some form of authorization check (such as request signatures or an authorization key field).  Alternately, the command being run can perform the check, again with the caveat that such scripts should not be readable or writable by nginx or php.  You may also need some form of concurrency protection (if webhooks arrive at the same time) and/or rate-limiting (to avoid denial of service or similar issues).

(In addition, if you're using `root` to run the webhook tool, you should also ensure webhooks that do not need root access downgrade their privileges with `as-developer` or `as-nginx` accordingly.)

In short, using this feature may require careful design consideration, as it can easily poke holes in the "defense in depth" architecture this container works so hard to create.  (Especially with a non-default `WEBHOOK_USER`.)

## Version Info

Builds of this image are tagged with multiple aliases to make it easy to pin specific revisions or to float by PHP version.  For example, a PHP 7.3.13 image with release 2.1.1 of this container could be accessed via any of the following tags (if  2.1.1 were the latest release of this image):

* `7.3`
* `7.3-2.x`
* `7.3-2.1.x`
* `7.3-2.1.1`
* `7.3.13`
* `7.3.13-2.x`
* `7.3.13-2.1.x`
* `7.3.13-2.1.1`

Note that there is **no** `latest` tag for this image; you must explicitly select at least a PHP version such as `7.3` to get the latest version of this image for that PHP version.

Also note that although you *can* just specify a PHP version, major releases of this container may be incompatble with older releases due to e.g. changes in OS versions or other factors, so you should probably at least target a specific major release of this container, e.g. `7.3-2.x` or `7.4-3.x`.

### Major Versions

* 3.x - Alpine 3.10-3.16, Composer 2, PHP 7.1 through 8.2, dropped prestissimo from default `GLOBAL_REQUIRE`, added `--optimize-autoloader` to default `COMPOSER_OPTIONS`
* 2.x - Alpine 3.9, Composer 1, PHP 7.1 through 7.3, build extensions using [mlocati/docker-php-extension-installer](https://github.com/mlocati/docker-php-extension-installer)
* 1.4.x - Alpine 3.9, Composer 1, PHP 7.1 and 7.2, image based on Docker php-fpm-alpine, scripted extension builds
* 1.3.x and older - Alpine 3.6, PHP 7.1 only,  implemented as an overlay on the nginx-php-fpm image

### Version Details

| Tags          | PHP    | nginx  | mod lua | alpine | Notes |
| ------------- | ------ | ------ | ------- | ------ | ----- |
| 8.2-3.0.x | 8.2.3  | 1.22.1 | 0.10.21 | 3.16     |Composer 2|
| 8.1-3.0.x | 8.1.16 | 1.22.1 | 0.10.21 | 3.16     ||
| 8.0-3.0.x | 8.0.19 | 1.20.1 | 0.10.19 | 3.14     ||
| 7.4-3.0.x | 7.4.22 | 1.20.1 | 0.10.19 | 3.14     ||
| 7.3-3.0.x | 7.3.29 | 1.20.1 | 0.10.19 | 3.14     ||
| 7.2-3.0.x | 7.2.34 | 1.18.0 | 0.10.15 | 3.12    ||
| 7.1-3.0.x | 7.1.33 | 1.16.1 | 0.10.15 | 3.10    ||
|  |  |  |  |  | &nbsp; |
| 7.3-2.x | 7.3.13 | 1.14.2 | 0.10.15 | 3.9  | New extension build method for all 7.x-2.x versions |
| 7.2-2.x  | 7.2.26 | 1.14.2 | 0.10.15 | 3.9    ||
| 7.1-2.x | 7.1.33 | 1.14.2 | 0.10.15 | 3.9    ||
|  |  |  |  |  | &nbsp; |
| 7.2.26-1.4.x  | 7.2.26 | 1.14.2 | 0.10.15 | 3.9    | Old extension build method used from here down |
| 7.1.33-1.4.x  | 7.1.33 | 1.14.2 | 0.10.15 | 3.9    ||
|  |  |  |  |  | &nbsp; |
| 1.4.x         | 7.1.33 | 1.14.2 | 0.10.15 | 3.9    ||
| 1.4.0         | 7.1.32 | 1.14.2 | 0.10.15 | 3.9    ||
| 1.0.x - 1.3.x | 7.1.12 | 1.13.7 | 0.10.11 | 3.6    | Based on upstream [1.3.10][ric_harvey] |

[ric_harvey]: https://gitlab.com/ric_harvey/nginx-php-fpm/tree/1.3.10