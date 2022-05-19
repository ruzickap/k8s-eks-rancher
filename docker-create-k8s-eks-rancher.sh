#!/usr/bin/env bash

set -euxo pipefail

docker run -it --rm \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_SESSION_TOKEN \
  -e MY_PASSWORD \
  -v "${PWD}:/mnt" \
  -w /mnt \
  ubuntu ./create-k8s-eks-rancher.sh
