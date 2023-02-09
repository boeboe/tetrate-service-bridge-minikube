#!/usr/bin/env bash

ACTION=${1}
K8S_VERSION=${2}

# Network configuration
#   MINIKUBE_NETWORK        : name of the created docker bridge network
#   AWS_SECONDARY_SUBNET    : secondary aws subnet to be configured in your VPC
#   MINIKUBE_SUBNET         : minikube subnet (ip addresses for k8s api servers)
#   METALLB_MGMT_SUBNET     : metallb subnet for k8s service lb ip assignment within mgmt cluster
#   METALLB_ACTIVE_SUBNET   : metallb subnet for k8s service lb ip assignment within active cluster
#   METALLB_STANDBY_SUBNET  : metallb subnet for k8s service lb ip assignment within standby cluster
#
#   Make sure that
#     (1) MINIKUBE_SUBNET and METALLB_XYZ_SUBNET do not overlap
#     (2) MINIKUBE_SUBNET and METALLB_XYZ_SUBNET fall within AWS_SECONDARY_SUBNET
#   Check https://www.ipaddressguide.com/cidr

MINIKUBE_NETWORK=tsb-demo
AWS_SECONDARY_SUBNET=172.10.16.0/20     # 172.10.16.0 - 172.10.31.255
MINIKUBE_SUBNET=172.10.16.0/22          # 172.10.16.0 - 172.10.19.255
METALLB_MGMT_SUBNET=172.10.20.0/22      # 172.10.20.0 - 172.10.23.255
METALLB_ACTIVE_SUBNET=172.10.24.0/22    # 172.10.24.0 - 172.10.27.255
METALLB_STANDBY_SUBNET=172.10.28.0/22   # 172.10.28.0 - 172.10.31.255

MGMT_CLUSTER_PROFILE=mgmt-cluster-m1
MGMT_CLUSTER_METALLB_STARTIP=172.10.20.1
MGMT_CLUSTER_METALLB_ENDIP=172.10.23.254

ACTIVE_CLUSTER_PROFILE=active-cluster-m2
ACTIVE_CLUSTER_METALLB_STARTIP=172.10.24.1
ACTIVE_CLUSTER_METALLB_ENDIP=172.10.27.254

STANDBY_CLUSTER_PROFILE=standby-cluster-m3
STANDBY_CLUSTER_METALLB_STARTIP=172.10.28.1
STANDBY_CLUSTER_METALLB_ENDIP=172.10.31.254

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
  for image in `tctl install image-sync --just-print --raw --accept-eula` ; do
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
  
  if docker network inspect ${MINIKUBE_NETWORK} | grep ${AWS_SECONDARY_SUBNET} ; then
    echo "Docker network ${MINIKUBE_NETWORK} matches the expected aws subnet ${AWS_SECONDARY_SUBNET}"
  else
    docker network rm ${MINIKUBE_NETWORK} &>/dev/null ;
    docker network create ${MINIKUBE_NETWORK} --subnet ${AWS_SECONDARY_SUBNET} ;

    if ! docker network inspect ${MINIKUBE_NETWORK} | grep ${AWS_SECONDARY_SUBNET} ; then
      echo "Failed to create docker network ${MINIKUBE_NETWORK} with subnet ${AWS_SECONDARY_SUBNET}"
      echo "Check manually what goes wrong"
      exit 1
    else
      echo "Docker network ${MINIKUBE_NETWORK} matches the expected aws subnet ${AWS_SECONDARY_SUBNET}"
    fi
  fi

  # Start minikube profiles for all clusters
  minikube start --kubernetes-version=v${K8S_VERSION} --profile ${MGMT_CLUSTER_PROFILE} --network ${MINIKUBE_NETWORK} --subnet ${MINIKUBE_SUBNET} ;
  minikube start --kubernetes-version=v${K8S_VERSION} --profile ${ACTIVE_CLUSTER_PROFILE} --network ${MINIKUBE_NETWORK} --subnet ${MINIKUBE_SUBNET} ;
  minikube start --kubernetes-version=v${K8S_VERSION} --profile ${STANDBY_CLUSTER_PROFILE} --network ${MINIKUBE_NETWORK} --subnet ${MINIKUBE_SUBNET} ;

  # Configure and enable metallb in all clusters
  configure_metallb ${MGMT_CLUSTER_PROFILE} ${MGMT_CLUSTER_METALLB_STARTIP} ${MGMT_CLUSTER_METALLB_ENDIP} ;
  configure_metallb ${ACTIVE_CLUSTER_PROFILE} ${ACTIVE_CLUSTER_METALLB_STARTIP} ${ACTIVE_CLUSTER_METALLB_ENDIP} ;
  configure_metallb ${STANDBY_CLUSTER_PROFILE} ${STANDBY_CLUSTER_METALLB_STARTIP} ${STANDBY_CLUSTER_METALLB_ENDIP} ;

  minikube --profile ${MGMT_CLUSTER_PROFILE} addons enable metallb ;
  minikube --profile ${ACTIVE_CLUSTER_PROFILE} addons enable metallb ;
  minikube --profile ${STANDBY_CLUSTER_PROFILE} addons enable metallb ;

  # Pull images locally and sync them to minikube profiles
  sync_images ;
  load_images ${MGMT_CLUSTER_PROFILE} &
  pid_load_images_mgmt_cluster=$!
  load_images ${ACTIVE_CLUSTER_PROFILE} &
  pid_load_images_active_cluster=$!
  load_images ${STANDBY_CLUSTER_PROFILE} &
  pid_load_images_standby_cluster=$!
  wait $pid_load_images_mgmt_cluster
  wait $pid_load_images_active_cluster
  wait $pid_load_images_standby_cluster

  # Add nodes labels for locality based routing (region and zone)
  kubectl --context ${MGMT_CLUSTER_PROFILE} label node ${MGMT_CLUSTER_PROFILE} topology.kubernetes.io/region=region1 --overwrite=true ;
  kubectl --context ${ACTIVE_CLUSTER_PROFILE} label node ${ACTIVE_CLUSTER_PROFILE} topology.kubernetes.io/region=region1 --overwrite=true ;
  kubectl --context ${STANDBY_CLUSTER_PROFILE} label node ${STANDBY_CLUSTER_PROFILE} topology.kubernetes.io/region=region2 --overwrite=true ;

  kubectl --context ${MGMT_CLUSTER_PROFILE} label node ${MGMT_CLUSTER_PROFILE} topology.kubernetes.io/zone=zone1a --overwrite=true ;
  kubectl --context ${ACTIVE_CLUSTER_PROFILE} label node ${ACTIVE_CLUSTER_PROFILE} topology.kubernetes.io/zone=zone1b --overwrite=true ;
  kubectl --context ${STANDBY_CLUSTER_PROFILE} label node ${STANDBY_CLUSTER_PROFILE} topology.kubernetes.io/zone=zone2a --overwrite=true ;

  exit 0
fi

if [[ ${ACTION} = "down" ]]; then

  # Stop and delete minikube profiles
  minikube stop --profile ${MGMT_CLUSTER_PROFILE} ;
  minikube stop --profile ${ACTIVE_CLUSTER_PROFILE} ;
  minikube stop --profile ${STANDBY_CLUSTER_PROFILE} ;

  minikube delete --profile ${MGMT_CLUSTER_PROFILE} ;
  minikube delete --profile ${ACTIVE_CLUSTER_PROFILE} ;
  minikube delete --profile ${STANDBY_CLUSTER_PROFILE} ;

  exit 0
fi

echo "Please specify correct action: up/down"
exit 1