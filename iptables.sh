#!/usr/bin/env bash
#
# This helper script will make a private ip range on a docker bridge interface
# routable throught he host for network traffic coming from the public interface
# on that host.
#
# Args:
#   (1) PUBLIC_INTF : the public interface of the host
#   (2) PRIVATE_DOCKER_INTF : the private interface of the docker bridge network
#

PUBLIC_INTF=${1}
PRIVATE_DOCKER_INTF=${2}

if ! ip addr show dev ${PUBLIC_INTF} ; then
  echo "Please provide a valid PUBLIC_INTF input parameter as first argument"
  exit 1
elif ! ip addr show dev ${PRIVATE_DOCKER_INTF} ; then
  echo "Please provide a valid PRIVATE_DOCKER_INTF input parameter as second argument"
  exit 1
elif

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
# ${PRIVATE_DOCKER_INTF} is interface connected to docker bridged network

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# Masquerade.
iptables -t nat -A POSTROUTING -o ${PRIVATE_DOCKER_INTF} -j MASQUERADE
# fowarding
iptables -A FORWARD -i ${PRIVATE_DOCKER_INTF} -o ${PUBLIC_INTF} -m state --state RELATED,ESTABLISHED -j ACCEPT
# Allow outgoing connections from the AWS side.
iptables -A FORWARD -i ${PUBLIC_INTF} -o ${PRIVATE_DOCKER_INTF} -j ACCEPT
