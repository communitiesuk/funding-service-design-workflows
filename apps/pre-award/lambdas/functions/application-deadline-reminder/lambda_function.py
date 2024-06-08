from config import Config
from incomplete_application import process_events
from shared.aws_extended_client import SQSExtendedClient


def lambda_handler(event, context):
    sqs_extended_client = SQSExtendedClient(
        aws_access_key_id=Config.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=Config.AWS_SECRET_ACCESS_KEY,
        region_name=Config.AWS_REGION,
        endpoint_url=Config.AWS_ENDPOINT_OVERRIDE,
        large_payload_support=Config.AWS_MSG_BUCKET_NAME,
        always_through_s3=True,
    )
    # application_deadline_reminder()
    result = process_events(sqs_extended_client)

    return {
        "statusCode": 200,
        "body": result,
    }
