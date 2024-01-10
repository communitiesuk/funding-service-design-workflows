## Local Database
If not using the docker runner (docker compose [setup](https://dluhcdigital.atlassian.net/wiki/spaces/FS/pages/79205102/Running+Access+Funding+Locally#Running-FSD-E2E-locally) for running all services together) you will need a local database instance for testing. This is particularly useful if making changes to models etc.

1. Install Postgres
1. Create a database for the service you are using. Some repositories contain a script to create a DB for that service with any required extensions - see individual readmes for details. If the service you are using does not offer this, create a new DB manually:
    ```bash
        psql postgresql://localhost:5432 --user postgres
        CREATE DATABASE <db_name>;
        \l
    ```
    Replace `<db_name>` with the name of the database you wish to create, eg. `fsd_application_store`. The `\l` at the end lists all available databases, to confirm your new database has been created.
1. Create an environment variable to point at your local database, eg

    ```bash
        # pragma: allowlist nextline secret
        export DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/<db_name>
    ```

1. Run the service with `flask run` and it will connect to your local database as above

## Development with SQLAlchemy
We use SQLAlchemy as our ORM implementation, and develop using a code-first approach.

The below instructions assume you have already followed the [initial python setup guidelines](./python-repos-setup.md).

Initialise the database for sql alchemy development:
```bash
    flask db init
```

Then run any existing migrations to bring your local database up to date:
```bash
    flask db upgrade
```

Whenever you make changes to database models, please run. 
```bash
    flask db migrate
```
This updates the sql alchecmy migration files in `/db/migrations`. To see these updates reflected in your DB, you need to run `flask db upgrade` as above.

Once your model changes are complete, commit and push these to github so that the migrations will be run in the pipelines to correctly upgrade the deployed db instances with your changes.