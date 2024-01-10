#!/bin/bash

if [ "$AWS_ACCESS_KEY_ID" == "" -o "$AWS_SECRET_ACCESS_KEY" == "" -o "$AWS_SESSION_TOKEN" == "" ]
then
    echo "Log in to AWS and try again."
    exit 1
fi

which yq >/dev/null
if [ $? -ne 0 ]
then
    echo "Please install yq - this is needed to interpret the required secret values."
    exit 1
fi

BASTION=$(aws ec2 describe-instances --filter Name=tag:Name,Values='*-bastion' --filter Name=instance-state-name,Values='running' --query "Reservations[*].Instances[*].InstanceId" | yq '.[0][0]')
echo $BASTION
echo
echo "Getting secret..."
ARN=$(aws secretsmanager list-secrets --query "SecretList[?Tags[?Key=='aws:cloudformation:logical-id' && Value=='RedisSecret']].ARN" | yq '.[0]')
echo
echo "Getting secret values..."
VALUE=$(aws secretsmanager get-secret-value --secret-id $ARN --query 'SecretString' | yq '..')
USERNAME=$(echo "$VALUE" | yq '.username')
PASSWORD=$(echo "$VALUE" | yq '.password')

aws elasticache describe-cache-clusters --show-cache-node-info | yq '.CacheClusters[].CacheNodes[].Endpoint.Address'
REDIS=$(aws elasticache describe-cache-clusters --show-cache-node-info | yq '.CacheClusters[].CacheNodes[].Endpoint.Address' | grep funding-service-magic-links | head -1)
PORT=6379
echo ${REDIS}

echo
echo "Setting up connection..."
echo "aws ssm start-session --target $BASTION --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host=\"$REDIS\",portNumber=\"$PORT\",localPortNumber=\"$PORT\""
aws ssm start-session --target $BASTION --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host="$REDIS",portNumber="$PORT",localPortNumber="$PORT" &

echo "Waiting 5..."
sleep 5
echo
echo "Connecting..."

#echo "redis-cli -h localhost --tls -u '${USERNAME}' -a '${PASSWORD}' -p ${PORT}"
#redis-cli -h localhost --tls -u "${USERNAME}" -a "${PASSWORD}" -p ${PORT}
redis-cli "redis://${USERNAME}:${PASSWORD}@localhost:${PORT}" PING

echo "Checking cleanup..."
PSOUT=$(ps -ft$(tty) | grep session-manager-plugin | grep -v grep | while read a b c;do echo $b;done)
PSOUT=$(echo $PSOUT | xargs echo) # Remove newlines
if [ "$PSOUT" != "" ]
then
    ps -ft$(tty) | grep session-manager-plugin | grep -v grep | cut -c-100
    echo Killing $PSOUT
    for pid in $PSOUT
    do
        kill -9 $pid
    done
fi
