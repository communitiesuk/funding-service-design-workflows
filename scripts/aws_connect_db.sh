#!/bin/bash

usage() {
  echo
  echo "Usage: $0 [-h] [-i] <service>"
  echo "       -h for this message"
  echo "       -i to create a tunnel and leave it open for GUI-based DB access"
  echo "       service must be one of: fsd-account-store"
  echo "                               fsd-application-store"
  echo "                               fsd-assessment-store"
  echo "                               fsd-fund-store"
  echo "                               fsd-fund-application-builder"
  echo "                               post-award"
  echo "                               fsd-pre-award-stores"
  echo
}

if [ "$1" == "" -o "$1" == "-h" ]; then
  usage
  exit 0
fi

GUI=0
if [ "$1" == "-i" ]; then
  GUI=1
  shift
fi

SERVICE="$1"
case $SERVICE in
fsd-account-store) LPORT=1433 ;;
fsd-application-store) LPORT=1434 ;;
fsd-assessment-store) LPORT=1435 ;;
fsd-fund-store) LPORT=1436 ;;
post-award) LPORT=1437 ;;
fsd-fund-application-builder) LPORT=1438 ;;
fsd-pre-award-stores) LPORT=1439 ;;
*)
  echo
  echo "INVALID SERVICE!"
  usage
  exit 1
  ;;
esac

ACCOUNT=$(aws sts get-caller-identity | jq -r ".Account")
echo "Connecting through account ${ACCOUNT}"
# Not putting the full account numbers in since they're somewhat-sensitive information
case $ACCOUNT in
012*)
  echo "(dev)"
  ADD=0
  ;;
960*)
  echo "(test)"
  ADD=10
  ;;
378*)
  echo "(uat)"
  ADD=20
  ;;
233*)
  echo "(prod)"
  ADD=30
  echo
  echo -e "==========================="
  echo -e "Pair up! This is PRODUCTION"
  echo -e "==========================="
  echo
  ;;
*)
  echo
  echo "INVALID ACCOUNT!"
  usage
  exit 1
  ;;
esac
let LPORT+=$ADD

if [ "$AWS_ACCESS_KEY_ID" == "" -o "$AWS_SECRET_ACCESS_KEY" == "" -o "$AWS_SESSION_TOKEN" == "" ]; then
  echo "Log in to AWS and try again."
  exit 1
fi

which jq >/dev/null
if [ $? -ne 0 ]; then
  echo "Please install jq - this is needed to interpret the required secret values."
  exit 1
fi

if [ $GUI -eq 0 ]; then
  which psql >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "To run an interactive psql session, please ensure psql is installed on your machine."
    exit 1
  fi
fi

echo "Getting secret..."
if [[ "$SERVICE" == "post-award" || "$SERVICE" == "fsd-pre-award-stores" ]]; then
  VALUE="${SERVICE//-/}clusterAuroraSecret"
  ARN=$(aws secretsmanager list-secrets --query "SecretList[?Tags[?Key=='aws:cloudformation:logical-id' && Value=='${VALUE}']].ARN" | jq -r '.[0]')
else
  ARN=$(aws secretsmanager list-secrets --query "SecretList[?Tags[?Key=='copilot-service' && Value=='${SERVICE}']].ARN" | jq -r '.[0]')
fi

echo
echo "Getting secret values..."
VALUE=$(aws secretsmanager get-secret-value --secret-id $ARN --query 'SecretString' --output 'text')
CLUSTER=$(echo "$VALUE" | jq -r '.dbClusterIdentifier')
DBNAME=$(echo "$VALUE" | jq -r '.dbname')
USERNAME=$(echo "$VALUE" | jq -r '.username')
PASSWORD=$(echo "$VALUE" | jq -r '.password')
HOST=$(echo "$VALUE" | jq -r '.host')
PORT=$(echo "$VALUE" | jq -r '.port')

BASTION_NAME='bastion'
BASTION=$(aws ec2 describe-instances --filters Name=tag:Name,Values=\'*-$BASTION_NAME\' "Name=instance-state-name,Values='running'" --query "Reservations[*].Instances[*].InstanceId" | jq -r '.[0][0]')

echo $BASTION

echo
echo "Setting up connection..."
echo "aws ssm start-session --target $BASTION --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host=\"$HOST\",portNumber=\"$PORT\",localPortNumber=\"$LPORT\""
aws ssm start-session --target $BASTION --document-name AWS-StartPortForwardingSessionToRemoteHost --parameters host="$HOST",portNumber="$PORT",localPortNumber="$LPORT" &

echo "Waiting 5..."
sleep 5
echo
echo "Connecting..."
URL=postgres://$USERNAME:$PASSWORD@localhost:$LPORT/$DBNAME
if [ $GUI -eq 1 ]; then
  echo
  echo "URL is $URL"
  echo "If using JDBC (e.g. in DBeaver) - use jdbc:postgresql://localhost:$LPORT/$DBNAME"
  echo
  echo "PASSWORD is $PASSWORD"
  echo
  echo "Press enter to tear down session when complete."
  echo
  read a
else
  psql ${URL}
fi

echo "Checking cleanup..."
TRY_PYTHON=0
ps -ft$(tty) 2>/dev/null || TRY_PYTHON=1
if [ $TRY_PYTHON -eq 0 ]; then
  PSOUT=$(ps -ft$(tty) | grep session-manager-plugin | grep -v grep | while read a b c; do echo $b; done)
  PSOUT=$(echo $PSOUT | xargs echo) # Remove newlines
  if [ "$PSOUT" != "" ]; then
    ps -ft$(tty) | grep session-manager-plugin | grep -v grep | cut -c-100
    echo Killing $PSOUT
    for pid in $PSOUT; do
      kill -9 $pid
    done
  fi
else
  which python3 2>/dev/null && PY=python3
  which python 2>/dev/null && PY=python
  $PY -c 'import psutil;[p.terminate() for p in psutil.process_iter() if "session-manager-plugin" in p.name()]'
fi
