# nginx basic-auth sidecar

An nginx reverse proxy that puts HTTP basic auth in front of an app container in the same ECS task.
Used as a `sidecars.nginx` entry by the non-prod environments of `fsd-pre-award`,
`fsd-fund-application-builder`, `fsd-form-runner-adapter` and `post-award`. No prod environment uses it.

Published to `ghcr.io/communitiesuk/nginx-basic-auth` by
[`publish-nginx-basic-auth.yml`](../../.github/workflows/publish-nginx-basic-auth.yml).

## Why this exists

It replaces `xscys/nginx-sidecar-basic-auth`, which was last rebuilt in **July 2019** and whose source
repo (`xsc/nginx-sidecar-basic-auth`) has been archived since March 2020. It was referenced untagged, so
we were pulling a six-year-old image with years of unpatched nginx/Alpine/OpenSSL CVEs.

There is no maintained drop-in replacement. `beevelop/nginx-basic-auth` is well maintained but sets no
`Host` or `X-Forwarded-*` headers, has no `client_max_body_size` or read-timeout knobs, and takes a
pre-hashed `HTPASSWD` string instead of a username and password — so it would have broken the
authenticator redirect flow and capped uploads at 1 MB.

This image keeps the **same environment-variable interface** as the one it replaces, so adopting it was a
one-line change per manifest block with no SSM migration.

## Configuration

| Variable | Default | Notes |
|---|---|---|
| `PORT` | `8087` | Port nginx listens on; the ALB target-group port. |
| `FORWARD_HOST` | `localhost` | Containers in a task share a network namespace, so this is normally left alone. |
| `FORWARD_PORT` | `8080` | Port of the app container. |
| `BASIC_AUTH_USERNAME` | **none** | Required. Injected from SSM. |
| `BASIC_AUTH_PASSWORD` | **none** | Required. Injected from SSM. |
| `CLIENT_MAX_BODY_SIZE` | `1m` | Set to `10m` everywhere, for file uploads. |
| `PROXY_READ_TIMEOUT` | `60s` | `post-award` sets `180s`. |
| `PROXY_SEND_TIMEOUT` | `60s` | |
| `PROXY_REQUEST_BUFFERING` | `on` | |
| `PROXY_BUFFERING` | `on` | |

The two credential variables are deliberately **not** defaulted. If either is missing the container exits
with a `FATAL` message rather than starting up behind a guessable `admin`/`admin`.

`OPTIONS` requests bypass auth, because CORS preflights cannot carry credentials.

ALB health checks are configured against the *app* container's port, not `8087`, so the proxy does not
need an unauthenticated health endpoint.

## Patching it

Patching is deliberate — the manifests pin a digest, so a rebuild changes nothing until someone adopts
the new digest. Nothing is patched implicitly by deploying an app.

1. The weekly scheduled scan posts to Slack when the published `:current` image has fixable HIGH/CRITICAL
   vulnerabilities. That is the signal to start.
2. Run the **Publish nginx basic-auth sidecar image** workflow (`workflow_dispatch`). It rebuilds on the
   current `nginxinc/nginx-unprivileged:1.30-alpine-slim`, fails if Trivy still finds fixable
   HIGH/CRITICAL issues, and prints the new digest in the job summary.
3. Bump `sidecars.nginx.image.location` to the new digest in each app repo, deploy to dev, and check a
   sign-in round trip works before rolling on to test and uat.

Bumping the base image to a new nginx *minor* (e.g. `1.30` to `1.31`) is an edit to the `Dockerfile` here;
pushing that to `main` republishes automatically.

## Implementation notes

Two things to know before editing `default.conf.template`:

- The official nginx entrypoint renders `/etc/nginx/templates/*.template` with `envsubst`, using an
  allow-list built from `printenv`. nginx's own runtime variables (`$host`, `$remote_addr`) are therefore
  left alone, but **every `${...}` must have a default in the `Dockerfile`** or it renders empty and nginx
  refuses to start.
- The base is `nginxinc/nginx-unprivileged`, not the plain `nginx` image, so that the whole container can
  run as `USER 101`. It ships `/etc/nginx` and `/var/cache/nginx` writable by that user and keeps the pid
  under `/tmp`; the plain image would need all of that unpicking by hand first.
- Nothing is `apk add`ed. The startup hash uses busybox `mkpasswd -m sha512`, already in the base, so
  there is no package to version-pin and one less thing to patch.

## Testing locally

```bash
docker build -t nginx-basic-auth-test images/nginx-basic-auth
docker network create ba-test
docker run -d --name echo --network ba-test mendhak/http-https-echo:latest
docker run -d --name auth --network ba-test -p 8087:8087 \
  -e FORWARD_HOST=echo -e FORWARD_PORT=8080 \
  -e CLIENT_MAX_BODY_SIZE=10m \
  -e BASIC_AUTH_USERNAME=admin -e BASIC_AUTH_PASSWORD=hunter2 \
  nginx-basic-auth-test

curl -si localhost:8087/                     # 401
curl -si -u admin:hunter2 localhost:8087/    # 200, echoes the forwarded headers
docker exec auth nginx -T                    # check the rendered config
```
