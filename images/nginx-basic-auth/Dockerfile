# The unprivileged variant, so this can run as a non-root USER. It already has /etc/nginx
# and /var/cache/nginx writable by uid 101 and keeps the pid under /tmp; the plain nginx
# image would need all of that unpicking by hand before USER could work.
FROM nginxinc/nginx-unprivileged:1.30-alpine-slim

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

# No package installs: the password is hashed at startup with busybox mkpasswd, which is
# already in the base image. Nothing to version-pin, and one less package to patch.
COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY --chmod=0755 40-generate-htpasswd.sh /docker-entrypoint.d/40-generate-htpasswd.sh

# Numeric rather than 'nginx' so the ID resolves without the image's passwd file, which
# also keeps Kubernetes-style runAsNonRoot checks happy. 101 is the nginx user.
USER 101

EXPOSE 8087
