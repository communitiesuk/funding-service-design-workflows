#!/bin/bash

usage()
{
    echo
    echo "Usage: $0 [-h] [-i] <service>"
    echo "       -h for this message"
    echo "       -i to create a tunnel and leave it open for GUI-based DB access"
    echo "       service must be one of: fsd-account-store"
    echo "                               fsd-application-store"
    echo "                               fsd-assessment-store"
    echo "                               fsd-fund-store"
    echo 
}

if [ "$1" == "" -o "$1" == "-h" ]
then
    usage
    exit 0
fi

GUI=0
if [ "$1" == "-i" ]
then
    GUI=1
    shift
fi

SERVICE="$1"
case $SERVICE in 
    fsd-account-store)     ;;
    fsd-application-store) ;;
    fsd-assessment-store)  ;;
    fsd-fund-store)        ;;
    *)                     echo;echo "INVALID SERVICE!";usage;exit 1;;
esac

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

if [ $GUI -eq 0 ]
then
    which psql >/dev/null 2>&1
    if [ $? -ne 0 ]
    then
        echo "To run an interactive psql session, please ensure psql is installed on your machine."
        exit 1
    fi
fi

BASTION=$(aws ec2 describe-instances --filter Name=tag:Name,Values='*-bastion' --query "Reservations[*].Instances[*].InstanceId" | yq '.[0][0]')
echo $BASTION
echo
echo "Getting secret..."
ARN=$(aws secretsmanager list-secrets --query "SecretList[?Tags[?Key=='copilot-service' && Value=='${SERVICE}']].ARN" | yq '.[0]')
echo
echo "Getting secret values..."
VALUE=$(aws secretsmanager get-secret-value --secret-id $ARN --query 'SecretString' | yq '..')
CLUSTER=$(echo "$VALUE" | yq '.dbClusterIdentifier')
DBNAME=$(echo "$VALUE" | yq '.dbname')
USERNAME=$(echo "$VALUE" | yq '.username')
PASSWORD=$(echo "$VALUE" | yq '.password')
HOST=$(echo "$VALUE" | yq '.host')
PORT=$(echo "$VALUE" | yq '.port')

echo
echo "Setting up connection..."
echo "aws ssm start-session --target $BASTION --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host=\"$HOST\",portNumber=\"$PORT\",localPortNumber=\"1433\""
aws ssm start-session --target $BASTION --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host="$HOST",portNumber="$PORT",localPortNumber="1433" &

echo "Waiting 5..."
sleep 5
echo
echo "Connecting..."
URL=postgres://$USERNAME:$PASSWORD@localhost:1433/$DBNAME
if [ $GUI -eq 1 ]
then
    echo
    echo "URL is $URL"
    echo "PASSWORD is $PASSWORD"
    echo
    echo "Press enter to tear down session when complete."
    echo
    read a
else
    psql ${URL}
fi

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

