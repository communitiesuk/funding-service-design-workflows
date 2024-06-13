import json
import logging
from datetime import datetime
from uuid import uuid4

import boto3

logging.getLogger("lambda_runtime").setLevel(logging.INFO)
logging.getLogger().setLevel(logging.DEBUG)

S3_KEY_ATTRIBUTE_NAME = "S3Key"
MAX_ALLOWED_ATTRIBUTES = 10 - 1  # 10 for SQS and 1 reserved attribute
DEFAULT_MESSAGE_SIZE_THRESHOLD = 262144
RESERVED_ATTRIBUTE_NAME = "ExtendedPayloadSize"
MESSAGE_POINTER_CLASS = "software.amazon.payloadoffloading.PayloadS3Pointer"


class SQSExtendedClient:
    def __init__(
        self,
        aws_access_key_id=None,
        aws_secret_access_key=None,
        region_name="eu-west-2",
        endpoint_url=None,
        large_payload_support=None,
        always_through_s3=None,
        **kwargs,
    ):
        self.large_payload_support = large_payload_support
        self.always_through_s3 = always_through_s3

        if aws_access_key_id and aws_secret_access_key:
            self.sqs_client = boto3.client(
                "sqs",
                aws_access_key_id=aws_access_key_id,
                aws_secret_access_key=aws_secret_access_key,
                region_name=region_name,
                endpoint_url=endpoint_url,
                **kwargs,
            )
            self.s3_client = boto3.client(
                "s3",
                aws_access_key_id=aws_access_key_id,
                aws_secret_access_key=aws_secret_access_key,
                region_name=region_name,
                endpoint_url=endpoint_url,
            )
        else:
            """
            if 'aws_access_key_id' and 'aws_access_key_id' are not provided make sure to provide
            'AWS_ACCESS_KEY_ID' and 'AWS_SECRET_ACCESS_KEY' with environment variables
            """
            self.sqs_client = boto3.client(
                "sqs",
                region_name=region_name,
                endpoint_url=endpoint_url,
                **kwargs,
            )
            self.s3_client = boto3.client(
                "s3",
                region_name=region_name,
                endpoint_url=endpoint_url,
            )

    def submit_single_message(
        self,
        queue_url,
        message,
        extra_attributes: dict = None,
        message_group_id=None,
        message_deduplication_id=None,
    ):
        sqs_message_attributes = {
            "message_created_at": {
                "StringValue": str(datetime.now()),
                "DataType": "String",
            },
        }
        message_body, message_attributes = self._store_message_in_s3(
            message, sqs_message_attributes, extra_attributes
        )
        # add extra message attributes (if provided)
        if extra_attributes:
            for key, value in extra_attributes.items():
                message_attributes[key] = value

        response = self.sqs_client.send_message(
            QueueUrl=queue_url,
            MessageBody=message_body,
            MessageAttributes=message_attributes,
            MessageGroupId=message_group_id,
            MessageDeduplicationId=message_deduplication_id,
        )
        # Check if the delete operation succeeded, if not raise an error?
        status_code = response["ResponseMetadata"]["HTTPStatusCode"]
        if status_code != 200:
            logging.error(
                f"submit_single_message failed with status code {status_code}."
            )
        message_id = response["MessageId"]
        logging.info(f"Called SQS and submitted the message and id [{message_id}]")
        return message_id

    def _store_message_in_s3(
        self, message_body: str, message_attributes: dict, extra_attributes: dict
    ) -> (str, dict):
        """
        Responsible for storing a message payload in a S3 Bucket
        :message_body: A UTF-8 encoded version of the message body
        :message_attributes: A dictionary consisting of message attributes
        :extra_attributes: A dictionary consisting of message attributes
        Each message attribute consists of the name (key) along with a
        type and value of the message body. The following types are supported
        for message attributes: StringValue, BinaryValue and DataType.
        """
        if len(message_body) == 0:
            # Message cannot be empty
            logging.error("messageBody cannot be null or empty.")

        if self.large_payload_support and self.always_through_s3:
            # Check message attributes for ExtendedClient related constraints
            encoded_body = message_body.encode("utf-8")

            # Modifying the message attributes for storing it in the Queue
            message_attributes[RESERVED_ATTRIBUTE_NAME] = {}
            attribute_value = {
                "DataType": "Number",
                "StringValue": str(len(encoded_body)),
            }
            message_attributes[RESERVED_ATTRIBUTE_NAME] = attribute_value

            # S3 Key should either be a constant or be a random uuid4 string.
            s3_key = SQSExtendedClient._get_s3_key(message_attributes, extra_attributes)

            # Adding the object into the bucket
            response = self.s3_client.put_object(
                Body=encoded_body, Bucket=self.large_payload_support, Key=s3_key
            )
            # Check if the delete operation succeeded, if not raise an error?
            status_code = response["ResponseMetadata"]["HTTPStatusCode"]
            if status_code != 200:
                logging.error(
                    f"submit_single_message failed with status code {status_code}."
                )
            # Modifying the message body for storing it in the Queue
            message_body = json.dumps(
                [
                    MESSAGE_POINTER_CLASS,
                    {"s3BucketName": self.large_payload_support, "s3Key": s3_key},
                ]
            )
        return message_body, message_attributes

    @staticmethod
    def _get_s3_key(message_attributes: dict, extra_attributes: dict) -> str:
        """
        Responsible for checking if the S3 Key exists in the
        message_attributes
        :message_attributes: A dictionary consisting of message attributes
        :extra_attributes: A dictionary consisting of message attributes
        Each message attribute consists of the name (key) along with a
        type and value of the message body. The following types are supported
        for message attributes: StringValue, BinaryValue and DataType.
        """
        if S3_KEY_ATTRIBUTE_NAME in message_attributes:
            return message_attributes[S3_KEY_ATTRIBUTE_NAME]["StringValue"]
        elif extra_attributes and S3_KEY_ATTRIBUTE_NAME in extra_attributes:
            return (
                extra_attributes[S3_KEY_ATTRIBUTE_NAME]["StringValue"]
                + "/"
                + str(uuid4())
            )
        return str(uuid4())
