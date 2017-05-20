# dirtsimple/nginx-php-fpm

This project is a streamlined version of [ngineered/nginx-php-fpm](https://github.com/ngineered/nginx-php-fpm), with the following enhancements and bug fixes:

* Configuration files are generated using [gomplate](https://github.com/hairyhenderson/gomplate) instead of `sed`
* Your code can provide a `conf-tpl` directory with additional configuration files to be processed w/gomplate at container start time
* You can set `SUPERVISOR_INCLUDES` to a space-separated list of supervisord .conf files to be included in the supervisor configuration
* `php-fpm` pool parameters can be set with environment vars (`FPM_PM`, `FPM_MAX_CHILDREN`, `FPM_START_SERVERS`, `FPM_MIN_SPARE_SERVERS`, `FPM_MAX_SPARE_SERVERS`, `FPM_MAX_REQUESTS`)
* nginx's `set_real_ip_from` is recursive, and supports cloudflare (via `REAL_IP_CLOUDFLARE=1`) as well as your own load balancers/proxies (via `REAL_IP_FROM`)
* Additional alpine APKs can be installed using the `EXTRA_APKS` build-time argument
* composer-installed files are properly chowned, and cloned files are chowned to the correct `PUID`/`PGID` instead of the default `nginx` uid/git
* Configuration files don't grow on each container restart

Unlike  [ngineered/nginx-php-fpm](https://github.com/ngineered/nginx-php-fpm), however, this image does *not* support a plain `conf` directory with nginx configuration files.  If you want to override the defaults you must create one or more of the following in your git project or code volume:

*  `conf-tpl/etc/nginx/sites-available/default.conf`
*  `conf-tpl/etc/nginx/sites-available/default-ssl.conf`

Your initial versions should be copied from the versions in this image's `tpl` directory and can use `gomplate` templating to configure things based on environment variables.