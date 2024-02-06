# Pre-Commit
Each repo contains a .pre-commit-config.yaml which all developers should use to check styles etc before pushing changes.

Run the following while in your virtual enviroment:

```bash
    pip install pre-commit black

    pre-commit install
```

Once the above is done you will have autoformatting and pep8 compliance built into your workflow. You will be notified of any pep8 errors during commits.

## Setup Flake8 linting
Each repo contains a `pyproject.toml`. This is a single lint configuration file for all the lint tools (flake8, black) used. By default, flake8 doesn't recognise `.toml` config files, so we use a flake8 plugin `Flake8-pyproject`(more [details](https://pypi.org/project/Flake8-pyproject/)). To install it run the below command
```bash
    pip install Flake8-pyproject
```
In VS Code IDE, once `Flake8-pyproject` is installed, the flake8 extension automatically applies configuration from `pyproject.toml` file.

## `detect-secrets` hook
We use this pre-commit hook to prevent new secrets from entering the code base.(For more info: https://github.com/Yelp/detect-secrets)
- If the hook detects false positives, mark with an inline `pragma: allowlist secret` comment to ignore it.