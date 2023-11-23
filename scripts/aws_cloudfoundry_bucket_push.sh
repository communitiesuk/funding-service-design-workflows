#!/bin/bash

# Run this script with a . in order to set environment variables in your shell
# For example:
# . ./getcreds.sh

usage()
{
    echo
    echo "Usage: $0 <env>"
    echo "       env must be one of: dev, test, uat, prod"
    echo
}

ENV=$1
case $ENV in
dev)  ;;
test) ;;
uat)  ;;
prod) ;;
*)    echo "Invalid env!";usage;exit 1;;
esac

cd tmpytmpy/
aws s3 cp --recursive ./ s3://fsd-form-uploads-$ENV
cd ..
rm -rf tmpytmpy
