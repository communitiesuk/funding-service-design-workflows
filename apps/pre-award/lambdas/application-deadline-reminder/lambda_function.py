from application_reminder import application_deadline_reminder

def lambda_handler(event, context):
    # TODO implement
    return {
        'statusCode': 200,
        'body': application_deadline_reminder(),
    }
