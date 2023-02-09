#!/usr/bin/env bash
#
# This helper script will make a private ip range on a docker bridge interface
# routable throught he host for network traffic coming from the public interface
# on that host.
#
# Args:
#   (1) PUBLIC_INTF : the public interface of the host (usually eth0)
#
DOCKER_NETWORK=tsb-demo
DOCKER_NETWORK_ID=$(docker network inspect ${DOCKER_NETWORK} --format '{{.Id}}'  | cut --characters -5)
DOCKER_INTF=$(ip link show | grep ${DOCKER_NETWORK_ID} | head -n1 | cut -d ':' -f2 | tr -d " ")

PUBLIC_INTF=${1}

if ! ip addr show dev ${PUBLIC_INTF} ; then
  echo "Please provide a valid PUBLIC_INTF input parameter as first argument (usually eth0)"
  exit 1
fi

# Always accept loopback traffic
iptables -A INPUT -i lo -j ACCEPT

# We allow traffic from the AWS side
iptables -A INPUT -i ${PUBLIC_INTF} -j ACCEPT

######################################################################
#
#                         ROUTING
#
######################################################################

# ${PUBLIC_INTF} is interface connected to AWS
# ${DOCKER_INTF} is interface connected to docker bridged network

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# Masquerade.
iptables -t nat -A POSTROUTING -o ${DOCKER_INTF} -j MASQUERADE
# fowarding
iptables -A FORWARD -i ${DOCKER_INTF} -o ${PUBLIC_INTF} -m state --state RELATED,ESTABLISHED -j ACCEPT
# Allow outgoing connections from the AWS side.
iptables -A FORWARD -i ${PUBLIC_INTF} -o ${DOCKER_INTF} -j ACCEPT
