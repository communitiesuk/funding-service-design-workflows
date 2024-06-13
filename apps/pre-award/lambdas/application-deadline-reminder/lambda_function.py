from application_reminder import application_deadline_reminder
from incomplete_application import process_events


def lambda_handler(event, context):
    application_deadline_reminder()
    result = process_events()

    return {
        "statusCode": 200,
        "body": result,
    }
