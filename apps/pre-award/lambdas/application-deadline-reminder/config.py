from os import environ

class Config:
    #  APIs
    # TEST_FUND_STORE_API_HOST = "fund_store"
    # TEST_ACCOUNT_STORE_API_HOST = "account_store"
    # TEST_NOTIFICATION_SERVICE_HOST = "notification_service"

    FUND_STORE_API_HOST = environ.get("FUND_STORE_API_HOST")
    FUNDS_ENDPOINT = environ.get("FUNDS_ENDPOINT")
