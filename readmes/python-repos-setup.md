# Setup steps for FSD Access Funding Python Repositories

## Dev Container
> [!TIP]
> This document contains instructions for local setup without a dev container. For a quicker setup and consistent environment see [IDE Setup](./python-repos-ide-setup.md)

## QuickStart - TL;DR;
Quickstart instructions for each type of application - note that this won't necessarily include all dependencies!

If on windows: use `python` instead of `python3`, `set` instead of `export`, and `.venv\Scripts\activate` instead of `.venv/bin/activate`.

### Stores
Exmaple shown is for assessment store
```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
docker container run -e POSTGRES_PASSWORD=postgres -p 5432:5432 --name=assess_store_postgres -e POSTGRES_DB=assess_store_dev postgres
# pragma: allowlist nextline secret
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/assess_store_dev'
flask run
```

### Frontends
```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
python build.py
flask run
```

## Prerequisites
- python == 3.10

## Installation

Clone the repository - scripts to clone all access funding repositories available [here](https://dluhcdigital.atlassian.net/wiki/spaces/FS/pages/79205102/Running+Access+Funding+Locally#Cloning-the-Repos)

### Create a Virtual environment

```bash
    python3 -m venv .venv
```

### Enter the virtual environment

...either macOS using bash:

```bash
    source .venv/bin/activate
```

...or if on Windows using Command Prompt:

```bash
    .venv\Scripts\activate.bat
```

### Install dependencies
From the top-level directory enter the command to install pip and the dependencies of the project

```bash
    python3 -m pip install --upgrade pip && pip install -r requirements-dev.txt
```
NOTE: requirements-dev.txt and requirements.txt are updated using [pip-tools pip-compile](https://github.com/jazzband/pip-tools)
To update requirements please manually add the dependencies in the .in files (not the requirements.txt files)
Then run:

```bash
    pip-compile requirements.in

    pip-compile requirements-dev.in
```

### Build Swagger & GovUK Assets

If the repo has static assests, it requires building it manually. Currently this step is required for frontend, authenticator & assessment repos.

This build step imports assets required for the GovUK template and styling components.
It also builds customised swagger files which slightly clean the layout provided by the vanilla SwaggerUI 3.52.0 (which is included in dependency swagger-ui-bundle==0.0.9) are located at /swagger/custom/3_52_0.

Before first usage, the vanilla bundle needs to be imported and overwritten with the modified files. To do this run:

    python3 build.py

Developer note: If you receive a certification error when running the above command on macOS,
consider if you need to run the Python
'Install Certificates.command' which is a file located in your globally installed Python directory. For more info see [StackOverflow](https://stackoverflow.com/questions/52805115/certificate-verify-failed-unable-to-get-local-issuer-certificate)

## How to use
To run the application standalone, enter the virtual environment as described above, then:

```bash
    flask run
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
    gunicorn wsgi:app -c run/gunicorn/local.py
```
