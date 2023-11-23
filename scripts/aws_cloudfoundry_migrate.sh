#!/bin/bash

# If not done, go to https://eu-west-2.console.aws.amazon.com/ec2/v2/home?region=eu-west-2#SecurityGroups:
# Find the security groups associated with the AddOnStack (which already has inbound rules) and add PostgresQL format bastion sg.

export AWS_REGION=eu-west-2

usage()
{
    echo
    echo "Usage: $0 [-h] <service>"
    echo "       -h for this message"
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

SERVICE=$1

ENV=test
TEST=0
CF=1

if [ $CF -eq 1 ]
then

CFSERVICE=
case $SERVICE in
fsd-account-store)     CFSERVICE=funding-service-design-account-store-${ENV}-db;;
fsd-application-store) CFSERVICE=application-store-${ENV}-db;;
fsd-assessment-store)  CFSERVICE=assessment-store-${ENV}-db;;
fsd-fund-store)        CFSERVICE=funding-service-design-fund-store-${ENV}-db;;
*)                     echo;echo "INVALID SERVICE!";usage;exit 1;;
esac

echo "Ensure CF login has happened..."
X=`cf services` || exit 1
echo 

echo "Retrieving cf data from $CFSERVICE..."
rm -f /tmp/x.sql
cf conduit $CFSERVICE -- pg_dump --file /tmp/x.sql --no-acl --no-owner
ls -l /tmp/x.sql

fi # If doing CF service dump

if [ "$AWS_ACCESS_KEY_ID" == "" -o "$AWS_SECRET_ACCESS_KEY" == "" -o "$AWS_SESSION_TOKEN" == "" ]
then
    echo "Log in to AWS and try again."
    exit 1
fi

echo "Getting BASTION..."
BASTION=$(aws ec2 describe-instances --filter Name=tag:Name,Values='*-bastion' --query "Reservations[*].Instances[*].InstanceId" | yq '.[0][0]')
echo $BASTION
echo
echo "Getting secret..."
ARN=$(aws secretsmanager list-secrets --query "SecretList[?Tags[?Key=='copilot-service' && Value=='${SERVICE}']].ARN" | yq '.[0]')
echo $ARN
if [ "$ARN" = "null" ]
then
    echo "No secret!"
    exit 1
fi
echo
echo "Getting secret value..."
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
echo $URL
psql ${URL} -c SELECT 1;

if [ $TEST -eq 0 ]
then
    echo
    psql ${URL} -o /tmp/x.out -f ~/OneDrive\ -\ Version\ 1/dluhc/blank.sql;cat /tmp/x.out
    echo "Were there errors? (y/n)"
    read answer
    if [ "$answer" = "n" ]
    then
        psql ${URL} -o /tmp/x.out -f /tmp/x.sql;cat /tmp/x.out
        echo
    fi
fi

echo "Disconnecting..."
kill %1

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
