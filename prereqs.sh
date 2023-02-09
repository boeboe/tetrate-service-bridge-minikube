#!/usr/bin/env bash

ACTION=${1}

if [[ ${ACTION} = "check-main-deps" ]]; then

  DEPENDENCIES=( tctl minikube expect docker kubectl jq awk )

  # check necessary dependencies are installed
  for dep in "${DEPENDENCIES[@]}"
  do
    if ! command -v ${dep} &> /dev/null
    then
      echo "${dep} could not be found, please install this on your local system first" ;
      exit 1
    fi
  done

  TSB_VERSION=${2}

  # check if the expected tctl version is installed
  if ! [[ "$(tctl version --local-only)" =~ "${TSB_VERSION}" ]]
  then
    echo "wrong version of tctl, please install version ${TSB_VERSION} first" ;
    exit 2
  fi

  exit 0
fi

if [[ ${ACTION} = "check-vm-deps" ]]; then

  DEPENDENCIES=( docker )

  # check necessary dependencies are installed
  for dep in "${DEPENDENCIES[@]}"
  do
    if ! command -v ${dep} &> /dev/null
    then
      echo "${dep} could not be found, please install this on your local system first" ;
      exit 1
    fi
  done

  # check if the expected tctl version is installed
  if ! [[ "$(tctl version --local-only)" =~ "${TSB_VERSION}" ]]
  then
    echo "wrong version of tctl, please install version ${TSB_VERSION} first" ;
    exit 2
  fi

  exit 0
fi

echo "Please specify correct action: check-main-deps/check-vm-deps"
exit 1
