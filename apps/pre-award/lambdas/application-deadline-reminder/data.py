import json
import os
from typing import Optional
from urllib.parse import urlencode


from config import Config
from urllib import request, parse




def get_data(endpoint: str, params: Optional[dict] = None):
    """
    Queries the API endpoint provided and returns a
    data response in JSON format.

    Args:
        endpoint (str): an API get data address

    Returns:
        data (json): data response in JSON format
    """
    print(f"Fetching data from '{endpoint}' with params {params}.")
    data = get_remote_data(endpoint, params)

    if data is None:
        return f"Data request failed, unable to recover: {endpoint}"

    return data

def get_remote_data(endpoint, params: Optional[dict] = None):
    query_string = ""

    if params:
        params = {k: v for k, v in params.items() if v is not None}
        query_string = parse.urlencode(params)

    full_url = f"{endpoint}"
    print(f"FULL URL: {full_url}")
    response = request.urlopen(full_url)

    response_data = response.read()
    print(f"RESPONSE: {response_data}")

    if response.getcode() == 200:
        data = response_data.decode('utf-8')
        return data
    else:
        return (
            "GET remote data call was unsuccessful with status code:"
            f" {response.getcode()}."
        )
        return None
