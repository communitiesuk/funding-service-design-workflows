from os import environ


class Config:
    # fund store
    FUND_STORE_API_HOST = environ.get("FUND_STORE_API_HOST")
    FUNDS_ENDPOINT = environ.get("FUNDS_ENDPOINT")
    FUND_ENDPOINT = environ.get("FUND_ENDPOINT")
    FUND_ROUNDS_ENDPOINT = environ.get("FUND_ROUNDS_ENDPOINT")
    FUND_EVENTS_ENDPOINT = environ.get("FUND_EVENTS_ENDPOINT")
    FUND_EVENT_ENDPOINT = environ.get("FUND_EVENT_ENDPOINT")

    # account store
    ACCOUNT_STORE_API_HOST = environ.get("ACCOUNT_STORE_API_HOST")
    ACCOUNTS_ENDPOINT = environ.get("ACCOUNTS_ENDPOINT")

    # application store
    APPLICATION_STORE_API_HOST = environ.get("APPLICATION_STORE_API_HOST")
    APPLICATION_REMINDER_STATUS = environ.get("APPLICATION_REMINDER_STATUS")
    APPLICATIONS_ENDPOINT = environ.get("APPLICATIONS_ENDPOINT")
    APPLICATION_ENDPOINT = environ.get("APPLICATION_ENDPOINT")

    # notification service
    NOTIFICATION_SERVICE_API_HOST = environ.get("NOTIFICATION_SERVICE_API_HOST")
    NOTIFY_TEMPLATE_APPLICATION_DEADLINE_REMINDER = environ.get(
        "NOTIFY_TEMPLATE_APPLICATION_DEADLINE_REMINDER"
    )
    NOTIFY_TEMPLATE_INCOMPLETE_APPLICATION = environ.get(
        "NOTIFY_TEMPLATE_INCOMPLETE_APPLICATION"
    )
    
    ENVIRONMENT = environ.get(
        "ENVIRONMENT"
    )

    # ---------------
    # AWS Overall Config # TODO after the refactoring test related configs will be moved
    # ---------------
    AWS_REGION = environ.get("AWS_REGION")
    AWS_ENDPOINT_OVERRIDE = environ.get("AWS_ENDPOINT_OVERRIDE")

    # ---------------
    # S3 Config
    # ---------------
    AWS_MSG_BUCKET_NAME = environ.get("AWS_MSG_BUCKET_NAME")
    # ---------------
    # SQS Config
    # ---------------
    AWS_SQS_NOTIF_APP_PRIMARY_QUEUE_URL = environ.get(
        "AWS_SQS_NOTIF_APP_PRIMARY_QUEUE_URL"
    )

    # Sentry
    SENTRY_DSN = environ.get("SENTRY_DSN")