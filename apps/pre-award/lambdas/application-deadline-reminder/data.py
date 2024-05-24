import json
from typing import Optional
from urllib.parse import urlencode
from config import Config

import requests
import logging

# Logging to output to CloudWatch Logs
logging.getLogger('lambda_runtime').setLevel(logging.INFO)
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
    else:
        logging.error("There was a problem retrieving response from"
        f" {endpoint}. Status code: {response.status_code}")
        return None
    
def get_data_safe(endpoint, params: Optional[dict] = None):
    try:
        response = requests.get(endpoint, params=params)
        response.raise_for_status()
        return response.json()
    except:
        if response.status_code == 404:
            logging.info("No data retrieved from"
        f" {endpoint}")
        else: 
            logging.error("Unable to retrieve data from"
            f" {endpoint}. Status code: {response.status_code}")
        
    return None

def post_notification(template_type: str, to_email: str, content):
    endpoint = Config.NOTIFICATION_SERVICE_API_HOST + Config.SEND_ENDPOINT
    json_payload = {
        "type": template_type,
        "to": to_email,
        "content": content,
    }

    response = requests.post(endpoint, json=json_payload)
    if response.status_code in [200, 201]:
        logging.info(
            f"Post successfully sent to {endpoint} with response code:"
            f" '{response.status_code}'."
        )
        return response.status_code

    else:
        logging.error("Sorry, the notification could not be sent for endpoint:"
        f" '{endpoint}', params: '{json_payload}', response:"
        f" '{response.json()}'")
    
            
def get_account(
    email: Optional[str] = None, account_id: Optional[str] = None
):
    if email is account_id is None:
        raise TypeError("Requires an email address or account_id")

    url = Config.ACCOUNT_STORE_API_HOST + Config.ACCOUNTS_ENDPOINT
    params = {"email_address": email, "account_id": account_id}
    response = get_data(url, params)

    if response and "account_id" in response:
        return response
        