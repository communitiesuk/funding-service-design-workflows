# General
If not using VS Code, or if you do not want to use a devcontainer, refer to the general local setup instructions in [Python Repos Setup](./python-repos-setup.md)

# Dev Container
The python repos (still a WIP to roll out to all repos at time of writing 15/07/24) contain a vs code dev container specification in `./.devcontainer/python/devcontainer.json`. When used through VS code it provides:
- All the python dependencies for each service pre-installed
For repos with a DB, it also contains:
- The postgres cmd client `psql`
- A standalone postgres instance, accessible from the dev container at `<service>>-db:5432` 

See [confluence](https://dluhcdigital.atlassian.net/wiki/spaces/FS/pages/218824722/VS+Code+Dev+Containers) for more discussion on dev containers and details of the basic setup.

## Local Setup - VS Code
- Clone the repo into eg. funding-service-design-fund-store
- Open the folder funding-service-design-fund-store
- Use the command pallette (cmd + shift + P) and select 'Dev Containers: Reopen folder in container' (VS Code may prompt you for this on its own - it does the same thing)
- You are now in the dev container with all dependencies installed, and useful VS code extensions.
- There may be a delay in all the extensions (eg. unit testing) being available while it installs them in the container. This only happens the first time (or if you change container config and rebuild).
- You can now start the app in the usual way from the terminal inside the container with eg. `flask run` or run unit tests using the vs code extension or run `pytest` on the command line.
- This devcontainer also contains the dependencies and plugins needed for [Pre-Commit](#pre-commit) as detailed below, but you still need to run `pre-commit install`.
- Git is accessible from with this container and should work with the vs code extension as usual.

## Files involved
- [.devcontainer](./.devcontainer/python/devcontainer.json) Contains the vs code configuration for the container, such as which docker compose files to reference, and what extensions to install in the container.
- [docker-compose.yml](./docker-compose.yml) Details of the containers that are needed to develop this app. For fund-store it uses [Dockerfile](./Dockerfile) and a `posgtres` image.
- [Dockerfile](./Dockerfile) Details of the image to use for the dev container, under the stage `<app-name>-dev`. 
- [Optional] [compose.override.yml](./compose.override.yml) Allows overriding of properties such as exposed ports, or adding environment variables to the containers listed in `docker-compose.yml`. eg. If you want the postgres instance to be accessible from your local machine you could add the following to this file:
    ```
    services:
    fund-store-db:
        ports:
        - 5433:5432
    ```
    This will expose that postgres instance on port `5433` so you could connect a local `psql` client to it at `localhost:5432`

    If using this, add an additional item to the `dockerComposeFile` array in [devcontainer.json](./.devcontainer/python-container/devcontainer.json) pointing to this overrides file.




# Pre-Commit
Each repo contains a .pre-commit-config.yaml which all developers should use to check styles etc before pushing changes.

Run the following while in your virtual enviroment:

```bash
    pip install pre-commit black

    pre-commit install
```

Once the above is done you will have autoformatting and pep8 compliance built into your workflow. You will be notified of any pep8 errors during commits.

### Setup Flake8 linting
Each repo contains a `pyproject.toml`. This is a single lint configuration file for all the lint tools (flake8, black) used. By default, flake8 doesn't recognise `.toml` config files, so we use a flake8 plugin `Flake8-pyproject`(more [details](https://pypi.org/project/Flake8-pyproject/)). To install it run the below command
```bash
    pip install Flake8-pyproject
```
For convenience, this is also included in the `requirements-dev.in` set of dependencies.
For VS Code IDE users, once `Flake8-pyproject` is installed, the flake8 extension automatically applies configuration from `pyproject.toml` file.

### `detect-secrets` hook
We use this pre-commit hook to prevent new secrets from entering the code base.(For more info: https://github.com/Yelp/detect-secrets)
- If the hook detects false positives, mark with an inline `pragma: allowlist secret` comment to ignore it.