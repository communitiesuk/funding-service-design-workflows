# funding-service-design-post-award-lambda

## application-deadline-reminder

## Prerequisites

- Python 3.10.x or higher

## Getting started
* Install Python 3.10
(Instructions assume python 3 is installed on your PATH as `python` but may be `python3` on OSX)

Check your python version starts with 3.11 i.e.
```
python --version

Python 3.10
```

### Create the virtual environment

From directory application-deadline-reminder:

```
python -m venv .venv
```

...or if using PyCharm **when importing project**, create venv and set local python interpreter to use it:

In Pycharm:
1) File -> New Project... :
2) Select 'New environment using' -> Virtualenv
3) Set 'location' to project folder application-deadline-reminder
4) Base interpreter should be set to global Python install.

### Enter the virtual environment

...either macOS using bash/zsh:

    source .venv/bin/activate

...or if on Windows using Command Prompt:

    .venv\Scripts\activate.bat

...or if using Pycharm, if venv not set up during project import:

1) settings -> project -> python interpreter -> add interpreter -> add local interpreter
2) **If not previously created** -> Environment -> New -> select path to top level of project
3) **If previously created** -> Environment -> Existing -> Select path to local venv/scripts/python.exe
4) Do not inherit global site packages

To check if Pycharm is running local interpreter (rather than global):

    pip -V    #check the resultant path points to virtual env folder in project

Add pip tools:
```
python -m pip install pip-tools
```

### Setup pre-commit checks

* [Install pre-commit locally](https://pre-commit.com/#installation)
* Pre-commit hooks can either be installed using pip `pip install pre-commit` or homebrew (for Mac users)`brew install pre-commit`
* From your checkout directory run `pre-commit install` to set up the git hook scripts

### Run app
To run the front-end app locally, you can run the following:

01) Add python-lambda-local to run lambda locally

    ```
    pip install python-lambda-local
    ```

02) To run locally in as a bash script

    ```
    python-lambda-local -f lambda_handler lambda_function.py event.json
    ```

    ...or if using Pycharm: In Edit configurations


        script :

            ```<project location>/funding-service-design-workflows/apps/pre-award/lambdas/application-deadline-reminder/.venv/bin/python-lambda-local``` here check is the virtual environment folder is same as here

        script parameters :

            ```--timeout 3000 -f lambda_handler lambda_function.py event.json```

        Working Directory
            ```<project location>/funding-service-design-workflows/apps/pre-award/lambdas/application-deadline-reminder```

        ---event.json---
            ```{}```

        environment variables for local env:

            ```ACCOUNT_STORE_API_HOST=http://localhost:3003;ACCOUNTS_ENDPOINT=/accounts;APPLICATION_ENDPOINT=/applications /{application_id};APPLICATION_REMINDER_STATUS=/funds/{round_id}/application_reminder_status?status = true;APPLICATION_STORE_API_HOST=http://localhost:3002;APPLICATIONS_ENDPOINT=/applications;FUND_ENDPOINT=/funds/{fund_id};FUND_EVENT_ENDPOINT=/funds/{fund_id}/rounds/{round_id}/event/{event_id};FUND_EVENTS_ENDPOINT=/funds/{fund_id}/rounds/{round_id}/events;FUND_ROUNDS_ENDPOINT=/funds/{fund_id}/rounds;FUND_STORE_API_HOST=http://localhost:3001;FUNDS_ENDPOINT=/funds;NOTIFICATION_SERVICE_API_HOST=http://localhost:3006;NOTIFY_TEMPLATE_APPLICATION_DEADLINE_REMINDER=APPLICATION_DEADLINE_REMINDER;NOTIFY_TEMPLATE_INCOMPLETE_APPLICATION=INCOMPLETE_APPLICATION_RECORDS;PYTHONUNBUFFERED=1;```

        path to env
            ```<project location>/funding-service-design-docker-runner/.awslocal.env```

More information please refer : https://pypi.org/project/python-lambda-local/
