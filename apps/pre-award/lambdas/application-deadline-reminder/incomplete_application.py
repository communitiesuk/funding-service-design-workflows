from datetime import datetime
from dateutil import tz
from config import Config
from data import get_data_safe

import requests

import logging

logging.getLogger("lambda_runtime").setLevel(Config.LOG_LEVEL)


def process_events():
    """
    Pulls events from the fund store and checks if they need processing. If so, the relevant processor
    will be called (determined by event type). If the processing was successful, the event is updated
    and marked as processed.

    Return:
        True if the function ran without issue.
    """
    logging.info("Running event check")
    uk_timezone = tz.gettz("Europe/London")
    current_datetime = datetime.now(uk_timezone).replace(tzinfo=None)
    funds_response = requests.get(Config.FUND_STORE_API_HOST + Config.FUNDS_ENDPOINT)
    # If we cannot retrieve the funds then fail loudly
    funds_response.raise_for_status()
    funds = funds_response.json()

    # Iterate over rounds and events. Note that failure to retrieve rounds / events should be non blocking so that
    # the rest of the rounds / events can still be processed
    for fund in funds:
        fund_id = fund["id"]
        fund_info = get_data_safe(
            Config.FUND_STORE_API_HOST + Config.FUND_ENDPOINT.format(fund_id=fund_id)
        )
        rounds = get_data_safe(
            Config.FUND_STORE_API_HOST
            + Config.FUND_ROUNDS_ENDPOINT.format(fund_id=fund_id)
        )
        if not (fund_info and rounds):
            continue

        fund_name = fund_info["name"]

        for round in rounds:
            round_id = round["id"]
            round_name = round["title"]
            round_contact_email = round.get("contact_email")
            events = get_data_safe(
                Config.FUND_STORE_API_HOST
                + Config.FUND_EVENTS_ENDPOINT.format(fund_id=fund_id, round_id=round_id)
            )

            if not events:
                continue

            for event in events:
                event_type = event["type"]
                event_activation_date = datetime.strptime(
                    event.get("activation_date"), "%Y-%m-%dT%H:%M:%S"
                )
                event_id = event["id"]
                event_processed = event["processed"]

                # Check if event needs to be processed and past the activation date
                if event_processed or current_datetime < event_activation_date:
                    continue

                try:
                    event_processor = {
                        "SEND_INCOMPLETE_APPLICATIONS": send_incomplete_applications_after_deadline
                    }[event_type]
                except KeyError:
                    logging.error(
                        f"Incompatible event type found {event_type} for event {event_id}"
                    )
                    continue

                # Process the event and mark it as processed.
                result = event_processor(
                    fund_id=fund_id,
                    fund_name=fund_name,
                    round_id=round_id,
                    round_name=round_name,
                    round_contact_email=round_contact_email,
                )
                if not result:
                    continue

                try:
                    response = requests.put(
                        Config.FUND_STORE_API_HOST
                        + Config.FUND_EVENT_ENDPOINT.format(
                            fund_id=fund_id,
                            round_id=round_id,
                            event_id=event_id,
                        ),
                        params={"processed": True},
                    )
                    response.raise_for_status()
                except:
                    logging.error(
                        f"Failed to mark event {event_id}"
                        f" as processed for {fund_name} {round_name}"
                    )

                logging.info(
                    f"Event {event_id} has been"
                    " marked as processed for"
                    f" {fund_name} {round_name}"
        )
    return True


def send_incomplete_applications_after_deadline(
    fund_id, fund_name, round_id, round_name, round_contact_email
):
    """
    Retrieves a list of unsubmitted applications for the given fund and round. Then use the
    notification service to email the account for each application.

    Args:
    - fund_id (str): The ID of the fund.
    - fund_name (str): The name of the fund.
    - round_id (str): The ID of the funding round.
    - round_name (str): The name of the round.
    - round_contact_email (str): The email to contact for the round

    Return:
        True if there were zero unsubmitted applications, or if at least one account was emailed. False otherwise.
    """

    search_params = {
        "status_only": ["NOT_STARTED", "IN_PROGRESS", "COMPLETED"],
        "fund_id": fund_id,
        "round_id": round_id,
    }

    try:
        response = requests.get(
            Config.APPLICATION_STORE_API_HOST + Config.APPLICATIONS_ENDPOINT,
            params=search_params,
        )
        response.raise_for_status()
        unsubmitted_applications = response.json()
    except Exception as e:
        logging.error(
            f"Unable to retrieve incomplete applications for fund {fund_name} and round {round_name}. Exception {str(e)}"
        )
        return False

    logging.info(
        f"Found {len(unsubmitted_applications)} unsubmitted applications for fund {fund_name} and round {round_name}"
    )
    unsuccessful_notifications = 0

    # Get all required information for applications
    for application in unsubmitted_applications:
        try:
            application_info_request = requests.get(
                Config.APPLICATION_STORE_API_HOST
                + Config.APPLICATION_ENDPOINT.format(application_id=application["id"])
            )
            application_info_request.raise_for_status()
            application_info = application_info_request.json()
            account_info_request = requests.get(
                Config.ACCOUNT_STORE_API_HOST + Config.ACCOUNTS_ENDPOINT,
                params={"account_id": application["account_id"]},
            )
            account_info_request.raise_for_status()
            account_info = account_info_request.json()
            application_to_send = {
                **application,
                "fund_name": fund_name,
                "forms": application_info["forms"],
                "round_name": round_name,
                "account_email": account_info["email_address"],
                "contact_help_email": round_contact_email,
            }
        except Exception as e:
            logging.error(
                f"Unable to retrieve application or account information for application {application['id']}. Exception {str(e)}"
            )
            unsuccessful_notifications += 1
            continue

        # Send an email to the account associated with the application.
        try:
            json_payload = {
                "type": Config.NOTIFY_TEMPLATE_INCOMPLETE_APPLICATION,
                "to": account_info["email_address"],
                "content": {
                    "application": application_to_send,
                    "contact_help_email": round_contact_email,
                },
            }
            response = requests.post(
                Config.NOTIFICATION_SERVICE_API_HOST + Config.SEND_ENDPOINT,
                json=json_payload,
            )
            response.raise_for_status()
        except Exception as e:
            logging.error(
                f"Unable to send an incomplete application email for application {application['id']}. Exception {str(e)}"
            )
            unsuccessful_notifications += 1

    num_unsubmitted_applications = len(unsubmitted_applications)
    logging.info(
        f"Sent {num_unsubmitted_applications - unsuccessful_notifications} out of {num_unsubmitted_applications} incomplete application emails"
    )

    return (
        num_unsubmitted_applications > unsuccessful_notifications
        if num_unsubmitted_applications > 0
        else True
    )
