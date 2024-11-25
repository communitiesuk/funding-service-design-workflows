#!/bin/bash

cd apps/pre-award
copilot svc ls --json | yq -r '.services[] | select(.app=="pre-award").name' | grep -v exit | while read svc; do
  sha=$(copilot svc show -n $svc --json | yq -r '.variables[] | select(.name=="GITHUB_SHA").value')
  printf "%22s %s\n" $svc $sha
done
