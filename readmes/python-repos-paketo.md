# Build with Paketo

[Pack](https://buildpacks.io/docs/tools/pack/cli/pack_build/)

[Paketo buildpacks](https://paketo.io/)

```bash
    pack build <name your image> --builder paketobuildpacks/builder:base
```

Example:

    [~/work/repos/funding-service-design-fund-store] pack build paketo-demofsd-app --builder paketobuildpacks/builder:base
    ***
    Successfully built image paketo-demofsd-app


You can then use that image with docker to run a container

```bash
    docker run -d -p 8080:8080 --env PORT=8080 --env FLASK_ENV=dev [envs] paketo-demofsd-app
```

`envs` needs to include values for each of:
SENTRY_DSN
GITHUB_SHA

```bash
    docker ps -a
    CONTAINER ID   IMAGE                       COMMAND                  CREATED          STATUS                    PORTS                    NAMES
    42633142c619   paketo-demofsd-app          "/cnb/process/web"       8 seconds ago    Up 7 seconds              0.0.0.0:8080->8080/tcp   peaceful_knuth
```