#!/bin/bash

# Run this script with a . in order to set environment variables in your shell
# For example:
# . ./getcreds.sh

usage()
{
    echo
    echo "Usage: $0 <env>"
    echo "       env must be one of: test, uat, prod"
    echo
}

ENV=$1
case $ENV in
test) ADD="-test";;
uat)  ADD="";;
prod) ADD="";;
*)    echo "Invalid env!";usage;exit 1;;
esac

for e in `env | grep AWS | cut -d'=' -f1`
do
unset $e
done

SERVICE_INSTANCE_NAME=form-uploads${ADD}
KEY_NAME=my-key

cf delete-service-key -f "${SERVICE_INSTANCE_NAME}" "${KEY_NAME}"
cf create-service-key "${SERVICE_INSTANCE_NAME}" "${KEY_NAME}" -c '{"allow_external_access": true}'
export S3_CREDENTIALS=$(cf service-key "${SERVICE_INSTANCE_NAME}" "${KEY_NAME}" | tail -n +2)
echo $S3_CREDENTIALS
echo $S3_CREDENTIALS | yq -r '.credentials'
echo $S3_CREDENTIALS | yq -r '.credentials.aws_access_key_id'

export AWS_ACCESS_KEY_ID=$(echo "${S3_CREDENTIALS}" | yq -r '.credentials.aws_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "${S3_CREDENTIALS}" | yq -r '.credentials.aws_secret_access_key')
export BUCKET_NAME=$(echo "${S3_CREDENTIALS}" | yq -r '.credentials.bucket_name')
export AWS_DEFAULT_REGION=$(echo "${S3_CREDENTIALS}" | yq -r '.credentials.aws_region')

env | grep AWS
aws s3 ls --recursive s3://$BUCKET_NAME | while read d t sz filename
do
echo $filename
done
rm -rf tmpytmpy
aws s3 cp --recursive s3://$BUCKET_NAME tmpytmpy/
