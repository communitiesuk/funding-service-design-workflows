FROM nginx:1.30-alpine-slim

# Defaults for every variable referenced in default.conf.template. envsubst is given an
# allow-list built from printenv, so an unset variable here renders empty and nginx won't
# start. BASIC_AUTH_USERNAME / BASIC_AUTH_PASSWORD are deliberately NOT defaulted: they
# are injected from SSM, and the entrypoint fails fast rather than serving admin/admin.
ENV PORT=8087 \
    FORWARD_HOST=localhost \
    FORWARD_PORT=8080 \
    PROXY_READ_TIMEOUT=60s \
    PROXY_SEND_TIMEOUT=60s \
    CLIENT_MAX_BODY_SIZE=1m \
    PROXY_REQUEST_BUFFERING=on \
    PROXY_BUFFERING=on

# openssl CLI for runtime password hashing. Deliberately not apache2-utils, which
# drags in apr / apr-util / expat purely to run htpasswd once at startup.
RUN apk add --no-cache openssl

COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY --chmod=0755 40-generate-htpasswd.sh /docker-entrypoint.d/40-generate-htpasswd.sh

EXPOSE 8087
