#!/usr/bin/env bash

ACTION=${1}
K8S_VERSION=${2}

# Network configuration
#   DOCKER_NETWORK        : name of the created docker bridge network
#   AWS_SECONDARY_SUBNET    : secondary aws subnet to be configured in your VPC
#   METALLB_MGMT_SUBNET     : metallb subnet for k8s service lb ip assignment within mgmt cluster
#   METALLB_ACTIVE_SUBNET   : metallb subnet for k8s service lb ip assignment within active cluster
#   METALLB_STANDBY_SUBNET  : metallb subnet for k8s service lb ip assignment within standby cluster
#
#   Make sure that
#     (1) METALLB_XYZ_SUBNET do not overlap
#     (2) METALLB_XYZ_SUBNET fall within AWS_SECONDARY_SUBNET
#   Check https://www.ipaddressguide.com/cidr

DOCKER_NETWORK=tsb-demo
AWS_SECONDARY_SUBNET=172.10.16.0/20     # 172.10.16.0 - 172.10.31.255
MGMT_METALLB_SUBNET=172.10.16.0/22          # 172.10.16.0 - 172.10.19.255
ACTIVE_METALLB_SUBNET=172.10.20.0/22      # 172.10.20.0 - 172.10.23.255
STANDBY_METALLB_SUBNET=172.10.24.0/22    # 172.10.24.0 - 172.10.27.255

MGMT_PROFILE=mgmt-cluster-m1
MGMT_METALLB_STARTIP=172.10.16.1
MGMT_METALLB_ENDIP=172.10.19.254

ACTIVE_PROFILE=active-cluster-m2
ACTIVE_METALLB_STARTIP=172.10.20.1
ACTIVE_METALLB_ENDIP=172.10.23.254

STANDBY_PROFILE=standby-cluster-m3
STANDBY_METALLB_STARTIP=172.10.24.1
STANDBY_METALLB_ENDIP=172.10.27.254

# Configure metallb start and end IP
#   args:
#     (1) minikube profile name
#     (2) start ip
#     (3) end ip
function configure_metallb {
  expect <<DONE
  spawn minikube --profile ${1} addons configure metallb
  expect "Enter Load Balancer Start IP:" { send "${2}\\r" }
  expect "Enter Load Balancer End IP:" { send "${3}\\r" }
  expect eof
DONE
}

# Pull tsb docker images 
function sync_images {
  docker login -u ${TSB_DOCKER_USERNAME} -p ${TSB_DOCKER_PASSWORD} containers.dl.tetrate.io ;

  # Sync all tsb images locally (if not yet available)
  for image in `tctl install image-sync --just-print --raw --accept-eula 2>/dev/null` ; do
    if ! docker image inspect ${image} &>/dev/null ; then
      docker pull ${image} ;
    fi
  done

  # Sync image for application deployment
  if ! docker image inspect containers.dl.tetrate.io/obs-tester-server:1.0 &>/dev/null ; then
    docker pull containers.dl.tetrate.io/obs-tester-server:1.0 ;
  fi

  # Sync image for debugging
  if ! docker image inspect containers.dl.tetrate.io/netshoot &>/dev/null ; then
    docker pull containers.dl.tetrate.io/netshoot ;
  fi
}

# Load docker images into minikube profile 
#   args:
#     (1) minikube profile name
function load_images {
  for image in `tctl install image-sync --just-print --raw --accept-eula 2>/dev/null` ; do
    if ! minikube --profile ${1} image ls | grep ${image} &>/dev/null ; then
      echo "Syncing image ${image} to minikube profile ${1}" ;
      minikube --profile ${1} image load ${image} ;
    fi
  done

  # Load image for application deployment
  if ! minikube --profile ${1} image ls | grep containers.dl.tetrate.io/obs-tester-server:1.0 &>/dev/null ; then
    echo "Syncing image containers.dl.tetrate.io/obs-tester-server:1.0 to minikube profile ${1}" ;
    minikube --profile ${1} image load containers.dl.tetrate.io/obs-tester-server:1.0 ;
  fi

  # Load image for debugging
  if ! minikube --profile ${1} image ls | grep containers.dl.tetrate.io/netshoot &>/dev/null ; then
    echo "Syncing image containers.dl.tetrate.io/netshoot to minikube profile ${1}" ;
    minikube --profile ${1} image load containers.dl.tetrate.io/netshoot ;
  fi
}

if [[ ${ACTION} = "up" ]]; then

  # Start minikube profiles for all clusters
  if minikube profile list | grep ${MGMT_PROFILE} | grep "Running" &>/dev/null ; then
    echo "Minikube cluster profile ${MGMT_PROFILE} already running"
  else
    minikube start --kubernetes-version=v${K8S_VERSION} --profile ${MGMT_PROFILE} --network ${DOCKER_NETWORK} ;
  fi
  if minikube profile list | grep ${ACTIVE_PROFILE} | grep "Running" &>/dev/null ; then
    echo "Minikube cluster profile ${ACTIVE_PROFILE} already running"
  else
    minikube start --kubernetes-version=v${K8S_VERSION} --profile ${ACTIVE_PROFILE} --network ${DOCKER_NETWORK} ;
  fi
  if minikube profile list | grep ${STANDBY_PROFILE} | grep "Running" &>/dev/null ; then
    echo "Minikube cluster profile ${STANDBY_PROFILE} already running"
  else
    minikube start --kubernetes-version=v${K8S_VERSION} --profile ${STANDBY_PROFILE} --network ${DOCKER_NETWORK} ;
  fi

  set -x
  # Configure network routing for metallb ranges to minikube
  DOCKER_NETWORK_ID=$(docker network inspect ${DOCKER_NETWORK} --format '{{.Id}}'  | cut --characters -5)
  DOCKER_INTF=$(ip link show | grep ${DOCKER_NETWORK_ID} | head -n1 | cut -d ':' -f2 | tr -d " ")
  MGMT_MINIKUBE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${MGMT_PROFILE})
  ACTIVE_MINIKUBE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${ACTIVE_PROFILE})
  STANDBY_MINIKUBE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${STANDBY_PROFILE})
  

  if ! route -n | grep $(echo ${MGMT_METALLB_SUBNET} | sed "s|/.*||") | grep ${MGMT_MINIKUBE_IP} | grep ${DOCKER_INTF} &>/dev/null ; then
    sudo -E ip route add ${MGMT_METALLB_SUBNET} via ${MGMT_MINIKUBE_IP} dev ${DOCKER_INTF}
  fi

  if ! route -n | grep $(echo ${ACTIVE_METALLB_SUBNET} | sed "s|/.*||") | grep ${ACTIVE_MINIKUBE_IP} | grep ${DOCKER_INTF} &>/dev/null ; then
    sudo -E ip route add ${ACTIVE_METALLB_SUBNET} via ${ACTIVE_MINIKUBE_IP} dev ${DOCKER_INTF}
  fi

  if ! route -n | grep $(echo ${STANDBY_METALLB_SUBNET} | sed "s|/.*||") | grep ${STANDBY_MINIKUBE_IP} | grep ${DOCKER_INTF} &>/dev/null ; then
    sudo -E ip route add ${STANDBY_METALLB_SUBNET} via ${STANDBY_MINIKUBE_IP} dev ${DOCKER_INTF}
  fi

  exit

  # Configure and enable metallb in all clusters
  configure_metallb ${MGMT_PROFILE} ${MGMT_METALLB_STARTIP} ${MGMT_METALLB_ENDIP} ;
  configure_metallb ${ACTIVE_PROFILE} ${ACTIVE_METALLB_STARTIP} ${ACTIVE_METALLB_ENDIP} ;
  configure_metallb ${STANDBY_PROFILE} ${STANDBY_METALLB_STARTIP} ${STANDBY_METALLB_ENDIP} ;

  minikube --profile ${MGMT_PROFILE} addons enable metallb ;
  minikube --profile ${ACTIVE_PROFILE} addons enable metallb ;
  minikube --profile ${STANDBY_PROFILE} addons enable metallb ;

  # Pull images locally and sync them to minikube profiles
  sync_images ;
  load_images ${MGMT_PROFILE} &
  pid_load_images_mgmt_cluster=$!
  load_images ${ACTIVE_PROFILE} &
  pid_load_images_active_cluster=$!
  load_images ${STANDBY_PROFILE} &
  pid_load_images_standby_cluster=$!
  wait $pid_load_images_mgmt_cluster
  wait $pid_load_images_active_cluster
  wait $pid_load_images_standby_cluster

  # Add nodes labels for locality based routing (region and zone)
  kubectl --context ${MGMT_PROFILE} label node ${MGMT_PROFILE} topology.kubernetes.io/region=region1 --overwrite=true ;
  kubectl --context ${ACTIVE_PROFILE} label node ${ACTIVE_PROFILE} topology.kubernetes.io/region=region1 --overwrite=true ;
  kubectl --context ${STANDBY_PROFILE} label node ${STANDBY_PROFILE} topology.kubernetes.io/region=region2 --overwrite=true ;

  kubectl --context ${MGMT_PROFILE} label node ${MGMT_PROFILE} topology.kubernetes.io/zone=zone1a --overwrite=true ;
  kubectl --context ${ACTIVE_PROFILE} label node ${ACTIVE_PROFILE} topology.kubernetes.io/zone=zone1b --overwrite=true ;
  kubectl --context ${STANDBY_PROFILE} label node ${STANDBY_PROFILE} topology.kubernetes.io/zone=zone2a --overwrite=true ;

  exit 0
fi

if [[ ${ACTION} = "down" ]]; then

  # Stop and delete minikube profiles
  minikube stop --profile ${MGMT_PROFILE} ;
  minikube stop --profile ${ACTIVE_PROFILE} ;
  minikube stop --profile ${STANDBY_PROFILE} ;

  minikube delete --profile ${MGMT_PROFILE} ;
  minikube delete --profile ${ACTIVE_PROFILE} ;
  minikube delete --profile ${STANDBY_PROFILE} ;

  exit 0
fi

echo "Please specify correct action: up/down"
exit 1