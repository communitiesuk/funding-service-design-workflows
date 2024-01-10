# Pre-Commit 
Each repo contains a .pre-commit-config.yaml which all developers should use to check styles etc before pushing changes.

Run the following while in your virtual enviroment:

```bash
    pip install pre-commit black

    pre-commit install
```

Once the above is done you will have autoformatting and pep8 compliance built into your workflow. You will be notified of any pep8 errors during commits.