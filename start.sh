#!/bin/bash

bool () {
    # for consistency, exactly match how gomplate's bool function works
    case $1 in
        true|TRUE|True|T|t|1) return 0 ;;  # these strings are true
                           *) return 1 ;;  # all others are false
    esac
}

# Setup most configuration files based on environment
gomplate --input-dir /tpl --output-dir / || exit 1

# Enable SSL configuration if certs exist
ssl_available=/etc/nginx/sites-available/default-ssl.conf
ssl_enabled=/etc/nginx/sites-enabled/default-ssl.conf

if [ ! -z "$DOMAIN" ] && [ -f /etc/letsencrypt/live/$DOMAIN/privkey.pem ] ; then
    ln -sf $ssl_available $ssl_enabled
elif [ -L $ssl_enabled ] && [ "$(readlink $ssl_enabled)" -ef "$ssl_available" ]; then
    # Delete ssl conf only if it's a symlink we created
    rm $ssl_enabled
fi

# Setup SSH configuration
chmod 0700 /root/.ssh
if [ ! -z "$SSH_KEY" ]; then
 echo "$SSH_KEY" | base64 -d > /root/.ssh/id_rsa
 chmod 600 /root/.ssh/id_rsa
fi

# Re-create nginx user w/specified UID/GID
if [ ! -z "$PUID" ]; then
  if [ -z "$PGID" ]; then
    PGID=${PUID}
  fi
  deluser nginx
  addgroup -g ${PGID} nginx
  adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx -u ${PUID} nginx
else
  # Always chown webroot for better mounting
  chown -Rf nginx.nginx /var/www/html
fi


# Dont pull code down if the .git folder exists
if [ ! -d "/var/www/html/.git" ]; then
 # Pull down code from git for our site!
 if [ ! -z "$GIT_REPO" ]; then
   # Remove the test index file if you are pulling in a git repo
   if [ ! -z ${REMOVE_FILES} ] && ! bool "${REMOVE_FILES-true}"; then
     echo "skiping removal of files"
   else
     rm -Rf /var/www/html/*
   fi
   GIT_COMMAND='git clone '
   if [ ! -z "$GIT_BRANCH" ]; then
     GIT_COMMAND=${GIT_COMMAND}" -b ${GIT_BRANCH}"
   fi

   if [ -z "$GIT_USERNAME" ] && [ -z "$GIT_PERSONAL_TOKEN" ]; then
     GIT_COMMAND=${GIT_COMMAND}" ${GIT_REPO}"
   else
    if bool "$GIT_USE_SSH"; then
      GIT_COMMAND=${GIT_COMMAND}" ${GIT_REPO}"
    else
      GIT_COMMAND=${GIT_COMMAND}" https://${GIT_USERNAME}:${GIT_PERSONAL_TOKEN}@${GIT_REPO}"
    fi
   fi
   ${GIT_COMMAND} /var/www/html || exit 1
   chown -Rf nginx.nginx /var/www/html
 fi
fi

# Install env-templated files if they exist
if [ -d /var/www/html/conf-tpl ]; then
    gomplate --input-dir /var/www/html/conf-tpl --output-dir / || exit 1
fi

# Try auto install for composer
if [ -f "/var/www/html/composer.lock" ]; then
    su -s /bin/bash -p nginx -c 'composer install --no-dev --working-dir=/var/www/html' || exit 1
fi

# Run custom scripts
if bool "$RUN_SCRIPTS" ; then
  if [ -d "/var/www/html/scripts/" ]; then
    # make scripts executable incase they aren't
    chmod -Rf 750 /var/www/html/scripts/*
    # run scripts in number order
    for i in `ls /var/www/html/scripts/`; do /var/www/html/scripts/$i ; done
  else
    echo "Can't find script directory"
  fi
fi

# Start supervisord and services
exec /usr/bin/supervisord -n -c /etc/supervisord.conf

