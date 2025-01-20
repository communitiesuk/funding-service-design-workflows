from application_reminder import application_deadline_reminder
from config import Config
from data import get_data
from helpers.aws_extended_client import SQSExtendedClient
from incomplete_application import process_events
import requests
import traceback
from datetime import datetime, timezone


def lambda_handler(event, context):
    try:
        sqs_extended_client = SQSExtendedClient(
            region_name=Config.AWS_REGION,
            endpoint_url=Config.AWS_ENDPOINT_OVERRIDE,
            large_payload_support=Config.AWS_MSG_BUCKET_NAME,
            always_through_s3=True,
        )
        fund_details = []
        funds = get_data(Config.FUND_STORE_API_HOST + Config.FUNDS_ENDPOINT)
        for fund in funds:
            round_info = _get_round_details(fund["id"])
            fund_details.append({"fund": fund, "fund_round": round_info})

        application_deadline_reminder(sqs_extended_client, fund_details)
        result = process_events(sqs_extended_client, fund_details)
        return {
            "statusCode": 200,
            "body": result,
        }
    except Exception as e:
        send_error_to_sentry(message="An exception occurred in Lambda", exception=e)
        raise e


def _get_round_details(fund_id):
    round_info = get_data(
        Config.FUND_STORE_API_HOST + Config.FUND_ROUNDS_ENDPOINT.format(fund_id=fund_id)
    )
    return round_info


def send_error_to_sentry(message: str, exception: Exception):
    sentry_dsn = Config.SENTRY_DSN
    host, public_key, project_id = parse_sentry_dsn(sentry_dsn)

    headers = {
        "Content-Type": "application/json",
        "X-Sentry-Auth": f"Sentry sentry_version=7, sentry_client=my-lambda/1.0, sentry_key={public_key}",
    }

    stacktrace_frames = []
    tb = traceback.extract_tb(exception.__traceback__)
    stacktrace_frames = [
        {
            "filename": frame.filename,
            "lineno": frame.lineno,
            "function": frame.name,
            "module": frame.filename.split("/")[-1],
        }
        for frame in tb
    ]

    payload = {
        "message": message,
        "level": "error",
        "timestamp": datetime.now(tz=timezone.utc).isoformat(),
        "tags": {
            "lambda_function_name": "application-deadline-reminder",
            "environment": Config.ENVIRONMENT,
        },
        "exception": {
            "values": [
                {
                    "type": type(exception).__name__,
                    "value": str(exception),
                    "stacktrace": {"frames": stacktrace_frames},
                }
            ]
        },
    }

    response = requests.post(
        url=f"https://{host}/api/{project_id}/store/",
        headers=headers,
        json=payload,
    )

    if response.status_code == 200:
        print("Error logged to Sentry successfully")
    else:
        print(f"Failed to log error to Sentry: {response.status_code}, {response.text}")


def parse_sentry_dsn(dsn: str):
    """Parse the DSN to extract host, public_key, and project_id"""
    dsn_parts = dsn.replace("https://", "").split("@")
    public_key = dsn_parts[0]
    host, project_id = dsn_parts[1].split("/", 1)
    return host, public_key, project_id
