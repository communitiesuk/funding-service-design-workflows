from application_reminder import application_deadline_reminder
from config import Config
from data import get_data
from helpers.aws_extended_client import SQSExtendedClient
from incomplete_application import process_events


def lambda_handler(event, context):
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


def _get_round_details(fund_id):
    round_info = get_data(
        Config.FUND_STORE_API_HOST + Config.FUND_ROUNDS_ENDPOINT.format(fund_id=fund_id)
    )
    return round_info
