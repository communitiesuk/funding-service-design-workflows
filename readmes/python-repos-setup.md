# Setup steps for FSD Access Funding Python Repositories

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