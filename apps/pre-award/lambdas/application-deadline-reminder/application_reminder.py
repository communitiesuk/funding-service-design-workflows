from datetime import datetime

from dateutil import tz

from config import Config
from data import get_data
from data import get_account
from data import post_notification

import requests
import json

import logging

# Logging to output to CloudWatch Logs
logging.getLogger("lambda_runtime").setLevel(Config.LOG_LEVEL)


def application_deadline_reminder():

    logging.info("Application deadline reminder task is now running!")
    uk_timezone = tz.gettz("Europe/London")
    current_datetime = datetime.now(uk_timezone).replace(tzinfo=None)

    funds = get_data(Config.FUND_STORE_API_HOST + Config.FUNDS_ENDPOINT)

    for fund in funds:
        fund_id = fund.get("id")
        fund_info = get_data(
            Config.FUND_STORE_API_HOST + Config.FUND_ENDPOINT.format(fund_id=fund_id)
        )
        fund_name = fund_info.get("name")
        round_info = get_data(
            Config.FUND_STORE_API_HOST
            + Config.FUND_ROUNDS_ENDPOINT.format(fund_id=fund_id)
        )

        for round in round_info:
            round_deadline_str = round.get("deadline")
            reminder_date_str = round.get("reminder_date")
            round_id = round.get("id")
            round_name = round.get("title")
            contact_email = round.get("contact_email")

            if not reminder_date_str:
                logging.info(
                    f"No reminder is set for the round {fund_name} {round_name}"
                )
                continue

            application_reminder_sent = round.get("application_reminder_sent")

            round_deadline = datetime.strptime(round_deadline_str, "%Y-%m-%dT%H:%M:%S")

            reminder_date = datetime.strptime(reminder_date_str, "%Y-%m-%dT%H:%M:%S")

            if (
                not application_reminder_sent
                and reminder_date < current_datetime < round_deadline
            ):
                status = {
                    "status_only": ["IN_PROGRESS", "NOT_STARTED", "COMPLETED"],
                    "fund_id": fund_id,
                    "round_id": round_id,
                }

                endpoint = (
                    Config.APPLICATION_STORE_API_HOST + Config.APPLICATIONS_ENDPOINT
                )
                not_submitted_applications = requests.get(endpoint, params=status)

                all_applications = []
                for application in not_submitted_applications.json():
                    application["round_name"] = round_name
                    application["fund_name"] = fund_name
                    application["contact_help_email"] = contact_email
                    account = get_account(account_id=application.get("account_id"))

                    application["account_email"] = account.get("email_address")
                    application["deadline_date"] = round_deadline_str
                    all_applications.append({"application": application})

                logging.info(f"Total unsubmitted applications: {len(all_applications)}")
                # Only one email per account_email
                unique_email_account = {}
                for application in all_applications:
                    unique_email_account[
                        application["application"]["account_email"]
                    ] = application

                logging.info(
                    f"Total unique email accounts: {len(unique_email_account)}"
                )
                unique_application_email_addresses = list(unique_email_account.values())

                if len(unique_application_email_addresses) > 0:
                    for count, application in enumerate(
                        unique_application_email_addresses, start=1
                    ):
                        email = application["application"]["account_email"]
                        logging.info(
                            f"Sending reminder {count} of {len(unique_email_account)}"
                            f" for {fund_name} {round_name}"
                            f" to {email}"
                        )

                        try:
                            response = post_notification(
                                template_type=Config.NOTIFY_TEMPLATE_APPLICATION_DEADLINE_REMINDER,
                                to_email=email,
                                content=application,
                            )

                            if (
                                response == 200
                                and len(unique_application_email_addresses) == count
                            ):
                                logging.info(
                                    "The application reminder has been"
                                    " sent successfully for"
                                    f" {fund_name} {round_name}"
                                )

                                try:
                                    application_reminder_endpoint = (
                                        Config.FUND_STORE_API_HOST
                                        + Config.APPLICATION_REMINDER_STATUS.format(
                                            round_id=round_id
                                        )
                                    )
                                    response = requests.put(
                                        application_reminder_endpoint
                                    )
                                    if response.status_code == 200:
                                        logging.info(
                                            "The application_reminder_sent has been"
                                            " set to True for"
                                            f" {fund_name} {round_name}"
                                        )
                                except Exception as e:
                                    logging.error(
                                        "There was an issue updating the"
                                        " application_reminder_sent column in the"
                                        f" Round store for {fund_name} {round_name}."
                                        f" Error {e}."
                                    )

                        except Exception as e:
                            logging.info(
                                "There was a problem sending application(s)"
                                f" for {fund_name} {round_name}"
                                f" Error: {e}"
                            )

                else:
                    logging.info(
                        "Currently, there are no non-submitted applications"
                        f" for {fund_name} {round_name}"
                    )
            else:
                if (
                    current_datetime < reminder_date < round_deadline
                    and not application_reminder_sent
                ):
                    days_to_reminder = reminder_date - current_datetime
                    logging.info(
                        "Application deadline reminder is due in "
                        f" {days_to_reminder.days} days"
                        f" for {fund_name} {round_name}."
                    )
                    continue
                continue
