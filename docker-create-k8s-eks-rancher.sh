#!/usr/bin/env bash

set -euxo pipefail

export CI="${CI:-false}"

if [[ "${CI}" = "true" ]]; then
  DOCKER_CLI_PARAMS=( "-i" "--rm" )
else
  DOCKER_CLI_PARAMS=( "-i" "-t" "--rm" )
fi

docker run "${DOCKER_CLI_PARAMS[@]}" \
  -e AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY \
  -e AWS_SESSION_TOKEN \
  -e MY_PASSWORD \
  -v "${PWD}:/mnt" \
  -w /mnt \
  ubuntu ./create-k8s-eks-rancher.sh
