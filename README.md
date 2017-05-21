# dirtsimple/nginx-php-fpm

This is a docker image for an alpine nginx + php-fpm combo container, with support for:

* Cloning a git repo at container start (and running `composer install` if applicable)
* Running cron jobs or other supervisord-controlled tasks
* Build arguments to allow adding extra packages and PHP extensions
* Environment-based templating of any configuration file in the container at startup
* Running any user-supplied startup scripts

Inspired by (and implemented as a wrapper over) [ngineered/nginx-php-fpm](https://github.com/ngineered/nginx-php-fpm), this image supports all of that image's [configuration flags](https://github.com/ngineered/nginx-php-fpm/blob/master/docs/config_flags.md), plus the following enhancements and bug fixes:

* Configuration files are generated using [gomplate](https://github.com/hairyhenderson/gomplate) templates instead of `sed`
* Your code can provide a `conf-tpl` directory with additional configuration files to be processed w/gomplate at container start time (or you can mount replacements for this image's configuration templates under `/tpl`)
* You can set `SUPERVISOR_INCLUDES` to a space-separated list of supervisord .conf files to be included in the supervisor configuration
* cron jobs are supported by setting `USE_CRON=1` and putting the job data in `/etc/crontabs/root` , `/etc/crontabs/nginx`, or a file in one of the `/etc/periodic/` subdirectories (via volume mount, startup script, `conf-tpl` or `/tpl` files)
* `php-fpm` pool parameters can be set with environment vars (`FPM_PM`, `FPM_MAX_CHILDREN`, `FPM_START_SERVERS`, `FPM_MIN_SPARE_SERVERS`, `FPM_MAX_SPARE_SERVERS`, `FPM_MAX_REQUESTS`)
* nginx's `set_real_ip_from` is recursive, and supports Cloudflare (via `REAL_IP_CLOUDFLARE=1`) as well as your own load balancers/proxies (via `REAL_IP_FROM`)
* Additional alpine APKs, PHP core extensions, and pecl extensions can be installed using the `EXTRA_APKS`, `EXTRA_EXTS`, and `EXTRA_PECL` build-time arguments, respectively.
* composer-installed files are properly chowned, and cloned files are chowned to the correct `PUID`/`PGID` instead of the default `nginx` uid/gid
* Configuration files don't grow on each container restart
* nginx and composer are run as the nginx/`PUID` user, not root

### Adding Your Code

This image assumes your primary application code will be found in `/var/www/html`.  You can place it there via a volume mount, installation in a derived image, or by specifying a `GIT_REPO` environment variable targeting your code.

If a `GIT_REPO` is specified, the given repository will be cloned to `/var/www/html` at container startup, unless a `/var/www/html/.git` directory is already present  (e.g. in the case of a restart, or a mounted checkout).

(Important: do *not* both mount your code as a volume *and* provide a `GIT_REPO`: your code will be **erased** unless it's a git checkout, or you set `REMOVE_FILES=0` in your environment.)

Whether you're using a `GIT_REPO` or not, this image checks for the following things in the code directory (i.e., `/var/www/html`) during startup:

* a `composer.lock` file (triggering an automatic `composer install` run if found)
* a `conf-tpl/` subdirectory (triggering configuration file updates from any supplied templates; see next section for details)
* a `scripts/` subdirectory (containing startup scripts that will be run in alphanumeric order, if the `RUN_SCRIPTS` variable is set to `1`)

Note: if you are using a framework that exposes a subdirectory (like `web` or `public`) as the actual directory to be served by nginx, you must set the `WEBROOT` environment variable to that subdirectory (e.g. `/var/www/html/public`).  (Assuming you don't override the web server configuration; see more below.)

### Configuration Templating

This image uses [gomplate](https://github.com/hairyhenderson/gomplate) to generate arbitrary configuration files from templates.  Templates are loaded from two locations:

* The `/tpl` directory (created at build-time and supplied by this image)
* The `/var/www/html/conf-tpl` directory, found in your code checkout, volume mount, or derived image

The path of an output configuration file is derived from its relative path.  So, for example, the default template for `/etc/supervisord.conf` can be found in `/tpl/etc/supervisord.conf`, and can be overrridden by a template in `/var/www/html/conf-tpl/etc/supervisord.conf`.

Templates found in `/tpl` are applied at the very beginning of container startup, before code is cloned or startup scripts are run.  Templates in `conf-tpl/` are applied just after the code checkout (if any), and just before `composer install` (if applicable).

Template files are just plain text, except that they can contain Go template code like `{{.Env.WEBROOT}}` to insert environment variables.  Please see the [gomplate](https://github.com/hairyhenderson/gomplate) documentation and [Go Text Template](https://golang.org/pkg/text/template/#hdr-Text_and_spaces) language reference for more details, and this project's  [`tpl`](https://github.com/dirtsimple/nginx-php-fpm/tree/master/tpl) subdirectory for examples.

(Note: unlike ngineered/nginx-php-fpm, this image does *not* support a plain `conf` subdirectory with nginx configuration files. If you need to change the nginx configuration, we suggest simply defining a complete nginx configuration template in your code's `conf-tpl/etc/nginx/nginx.conf` directory.)

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
