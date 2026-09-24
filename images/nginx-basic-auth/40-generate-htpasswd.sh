#!/bin/sh
# Runs before nginx starts; the official nginx entrypoint execs /docker-entrypoint.d/*
# in lexical order, so this lands after 20-envsubst-on-templates.sh.
set -eu

# Fail the container rather than falling back to a guessable default. These are injected
# from SSM by ECS; if that ever silently fails we want the deploy to break, not to serve
# the site behind admin/admin.
if [ -z "${BASIC_AUTH_USERNAME:-}" ] || [ -z "${BASIC_AUTH_PASSWORD:-}" ]; then
  echo "FATAL: BASIC_AUTH_USERNAME and BASIC_AUTH_PASSWORD must both be set." >&2
  exit 1
fi

# SHA-512 crypt; nginx reads these via crypt(3), which musl supports.
printf '%s:%s\n' "$BASIC_AUTH_USERNAME" "$(openssl passwd -6 "$BASIC_AUTH_PASSWORD")" \
  >/etc/nginx/auth.htpasswd

# The master process is root, but workers run as nginx and it's the worker that
# reads auth_basic_user_file on each request.
chown nginx:nginx /etc/nginx/auth.htpasswd
chmod 400 /etc/nginx/auth.htpasswd
