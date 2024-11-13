# Setup steps for FSD Access Funding Python Repositories

## Dev Container
> [!TIP]
> This document contains instructions for local setup without a dev container. For a quicker setup and consistent environment see [IDE Setup](./python-repos-ide-setup.md)

## QuickStart - TL;DR;
Quickstart instructions for each type of application - note that this won't necessarily include all dependencies!

### Stores
Exmaple shown is for assessment store
```bash
uv sync
docker container run -e POSTGRES_PASSWORD=postgres -p 5432:5432 --name=assess_store_postgres -e POSTGRES_DB=assess_store_dev postgres
# pragma: allowlist nextline secret
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/assess_store_dev'
uv run flask run
```

### Frontends
```bash
uv sync
uv run python build.py
uv run flask run
```

## Prerequisites
- [uv](https://docs.astral.sh/uv/)

## Installation

Clone the repository - scripts to clone all access funding repositories available [here](https://dluhcdigital.atlassian.net/wiki/spaces/FS/pages/79205102/Running+Access+Funding+Locally#Cloning-the-Repos)

Use `uv` to install the correct Python version and setup your virtual environment:

```bash
uv sync
```

To update requirements, use `uv add <package>` and `uv remove <package>`.

### Build Swagger & GovUK Assets

If the repo has static assests, it requires building it manually. Currently this step is required for frontend, authenticator & assessment repos.

This build step imports assets required for the GovUK template and styling components.
It also builds customised swagger files which slightly clean the layout provided by the vanilla SwaggerUI 3.52.0 (which is included in dependency swagger-ui-bundle==0.0.9) are located at /swagger/custom/3_52_0.

Before first usage, the vanilla bundle needs to be imported and overwritten with the modified files. To do this run:

    uv run python build.py

Developer note: If you receive a certification error when running the above command on macOS,
consider if you need to run the Python
'Install Certificates.command' which is a file located in your globally installed Python directory. For more info see [StackOverflow](https://stackoverflow.com/questions/52805115/certificate-verify-failed-unable-to-get-local-issuer-certificate)

## How to use
To run the application standalone, enter the virtual environment as described above, then:

```bash
    uv run flask run
```

Note: Not all applications will function correctly without other dependencies also being avaialble, eg. Databases, other microservices. To run all the microservices together, we have a `docker-compose` file that links them, documented [here](https://dluhcdigital.atlassian.net/wiki/spaces/FS/pages/79205102/Running+Access+Funding+Locally#Running-FSD-E2E-locally)

## Run with Gunicorn

In deployed environments the service is run with gunicorn. You can run the service locally with gunicorn to test

First set the FLASK_ENV environment you wish to test eg:

```bash
    export FLASK_ENV=dev
```
Then run gunicorn using the following command:

```bash
    uv run gunicorn wsgi:app -c run/gunicorn/local.py
```
