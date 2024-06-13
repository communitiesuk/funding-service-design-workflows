import json
import logging
from typing import Optional
from urllib.parse import urlencode
from uuid import uuid4

import requests
from config import Config
from helpers.aws_extended_client import SQSExtendedClient

# Logging to output to CloudWatch Logs
logging.getLogger("lambda_runtime").setLevel(logging.INFO)
logging.getLogger().setLevel(logging.DEBUG)


def get_data(endpoint, params: Optional[dict] = None):
    query_string = ""
    if params:
        params = {k: v for k, v in params.items() if v is not None}
        query_string = urlencode(params)

    endpoint = endpoint + "?" + query_string
    response = requests.get(endpoint)

    if response.status_code == 200:
        data = response.json()
        return data

    logging.error(
        "There was a problem retrieving response from"
        f" {endpoint}. Status code: {response.status_code}"
    )
    return None


def get_data_safe(endpoint, params: Optional[dict] = None):
    try:
        response = requests.get(endpoint, params=params)
        response.raise_for_status()
        return response.json()
    except requests.HTTPError:
        logging.info(
            "No data retrieved from" f" {endpoint}. Status code {response.status_code}"
        )
    except Exception as e:
        logging.error("Unable to retrieve data from" f" {endpoint}. Exception {str(e)}")

    return None


def send_notification(
    template_type: str,
    to_email: str,
    content,
    application_id: str,
    sqs_extended_client: SQSExtendedClient,
) -> str:
    try:
        json_payload = {
            "type": template_type,
            "to": to_email,
            "content": content,
        }
        application_attributes = {
            "application_id": {
                "StringValue": application_id,
                "DataType": "String",
            },
            "S3Key": {
                "StringValue": "notification/incomplete",
                "DataType": "String",
            },
        }
        message_id = sqs_extended_client.submit_single_message(
            Config.AWS_SQS_NOTIF_APP_PRIMARY_QUEUE_URL,
            message=json.dumps(json_payload),
            message_group_id="notification",
            message_deduplication_id=str(uuid4()),  # ensures message uniqueness
            extra_attributes=application_attributes,
        )
        logging.info(
            f"Successfully added the message to queue for "
            f"application id {application_id} and message id [{message_id}]."
        )
        return str(message_id)
    except Exception as e:
        logging.error(
            f"Unable to send message to sqs for {application_id}. Exception {str(e)}"
        )
        raise e


def get_account(email: Optional[str] = None, account_id: Optional[str] = None):
    if email is account_id is None:
        raise TypeError("Requires an email address or account_id")

    url = Config.ACCOUNT_STORE_API_HOST + Config.ACCOUNTS_ENDPOINT
    params = {"email_address": email, "account_id": account_id}
    response = get_data(url, params)

    if response and "account_id" in response:
        return response
