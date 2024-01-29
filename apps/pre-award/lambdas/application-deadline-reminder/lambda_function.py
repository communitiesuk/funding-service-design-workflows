from application_reminder import application_deadline_reminder

def lambda_handler(event, context):

    return {
        'statusCode': 200,
        'body': application_deadline_reminder(),
        }