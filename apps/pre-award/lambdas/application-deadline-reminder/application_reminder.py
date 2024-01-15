from datetime import datetime

from dateutil import tz
from config import Config
from data import get_data


def application_deadline_reminder():
    uk_timezone = tz.gettz("Europe/London")
    current_datetime = datetime.now(uk_timezone).replace(tzinfo=None)

    print(current_datetime)

    funds = get_data(
        Config.FUND_STORE_API_HOST + Config.FUNDS_ENDPOINT
    )
    print(funds)
    if funds:
        return True
    else:
        return False
