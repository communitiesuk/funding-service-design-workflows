#!/bin/bash

echo "Getting source secret..."
SOURCE_ARN=$(aws secretsmanager list-secrets --query "SecretList[?Tags[?Key=='copilot-service' && Value=='data-store']].ARN" | jq -r '.[0]')
echo
echo "Getting source secret values..."
SOURCE_VALUE=$(aws secretsmanager get-secret-value --secret-id $SOURCE_ARN --query 'SecretString' --output 'text')
SOURCE_CLUSTER=$(echo "$SOURCE_VALUE" | jq -r '.dbClusterIdentifier')
SOURCE_DBNAME=$(echo "$SOURCE_VALUE" | jq -r '.dbname')
SOURCE_USERNAME=$(echo "$SOURCE_VALUE" | jq -r '.username')
SOURCE_PASSWORD=$(echo "$SOURCE_VALUE" | jq -r '.password')
SOURCE_HOST=$(echo "$SOURCE_VALUE" | jq -r '.host')
SOURCE_PORT=$(echo "$SOURCE_VALUE" | jq -r '.port')
if [[ "${SOURCE_HOST:0:15}" == "post-award-prod" ]]; then
  SOURCE_BASTION_NAME='postbast'
else
  SOURCE_BASTION_NAME='bastion'
fi
SOURCE_LPORT=1437


echo "Getting target secret..."
TARGET_ARN=$(aws secretsmanager list-secrets --query "SecretList[?Tags[?Key=='aws:cloudformation:logical-id' && Value=='postawardclusterAuroraSecret']].ARN" | jq -r '.[0]')
echo
echo "Getting target secret values..."
TARGET_VALUE=$(aws secretsmanager get-secret-value --secret-id $TARGET_ARN --query 'SecretString' --output 'text')
TARGET_CLUSTER=$(echo "$TARGET_VALUE" | jq -r '.dbClusterIdentifier')
TARGET_DBNAME=$(echo "$TARGET_VALUE" | jq -r '.dbname')
TARGET_USERNAME=$(echo "$TARGET_VALUE" | jq -r '.username')
TARGET_PASSWORD=$(echo "$TARGET_VALUE" | jq -r '.password')
TARGET_HOST=$(echo "$TARGET_VALUE" | jq -r '.host')
TARGET_PORT=$(echo "$TARGET_VALUE" | jq -r '.port')
TARGET_BASTION_NAME='bastion'
TARGET_LPORT=1438


SOURCE_BASTION=$(aws ec2 describe-instances --filters Name=tag:Name,Values=\'*-$SOURCE_BASTION_NAME\'  "Name=instance-state-name,Values='running'" --query "Reservations[*].Instances[*].InstanceId" | jq -r '.[0][0]')
TARGET_BASTION=$(aws ec2 describe-instances --filters Name=tag:Name,Values=\'*-$TARGET_BASTION_NAME\'  "Name=instance-state-name,Values='running'" --query "Reservations[*].Instances[*].InstanceId" | jq -r '.[0][0]')

echo
echo "Setting up connection..."
aws ssm start-session --target $SOURCE_BASTION --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host="$SOURCE_HOST",portNumber="$SOURCE_PORT",localPortNumber="$SOURCE_LPORT" &
aws ssm start-session --target $TARGET_BASTION --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host="$TARGET_HOST",portNumber="$TARGET_PORT",localPortNumber="$TARGET_LPORT" &
sleep 5

SOURCE_URL=postgres://$SOURCE_USERNAME:$SOURCE_PASSWORD@localhost:$SOURCE_LPORT/$SOURCE_DBNAME
TARGET_URL=postgres://$TARGET_USERNAME:$TARGET_PASSWORD@localhost:$TARGET_LPORT/$TARGET_DBNAME

echo "Doing dump and restore..."
pg_dump $SOURCE_URL -v -F c --clean | pg_restore -d $TARGET_URL -v --clean
echo "Completed dump and restore."