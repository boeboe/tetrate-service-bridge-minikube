#!/usr/bin/env bash
#
# This script will clean up all resouces created by a tctl demo installation to start from scratch
#

# Clean up namespace specific resources
for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do

  kubectl get deployments -n ${NS} -o custom-columns=:metadata.name \
    | grep operator | xargs -I {} kubectl scale deployment {} -n ${NS} --replicas=0 ;

  kubectl get deployments -n ${NS} -o custom-columns=:metadata.name \
    | grep operator | xargs -I {} kubectl delete deployment {} -n ${NS} --timeout=10s --wait=false ;

  kubectl delete --all deployments -n ${NS} --timeout=10s --wait=false ;
  kubectl delete --all jobs -n ${NS} --timeout=10s --wait=false ;
  kubectl delete --all statefulset -n ${NS} --timeout=10s --wait=false ;

  kubectl get deployments -n ${NS} -o custom-columns=:metadata.name \
    | grep operator | xargs -I {} kubectl patch deployment {} -n ${NS} --type json \
    --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;

  kubectl delete namespace ${NS} --timeout=10s --wait=false ;

done 

# Clean up cluster wide resources
kubectl get mutatingwebhookconfigurations -o custom-columns=:metadata.name \
  | xargs -I {} kubectl delete mutatingwebhookconfigurations {}  --timeout=10s --wait=false ;
kubectl get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
  | xargs -I {} kubectl delete crd {} --timeout=10s --wait=false ;
kubectl get validatingwebhookconfigurations -o custom-columns=:metadata.name \
  | xargs -I {} kubectl delete validatingwebhookconfigurations {} --timeout=10s --wait=false ;
kubectl get clusterrole -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
  | xargs -I {} kubectl delete clusterrole {} --timeout=10s --wait=false ;
kubectl get clusterrolebinding -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tsb\|xcp" \
  | xargs -I {} kubectl delete clusterrolebinding {} --timeout=10s --wait=false ;
kubectl get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
  | xargs -I {} kubectl patch crd {} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]' ;
kubectl get crds -o custom-columns=:metadata.name | grep "cert-manager\|istio\|tetrate" \
  | xargs -I {} kubectl delete crd {} --timeout=10s --wait=false ;

# Clean up pending finalizer namespaces
kubectl proxy &
PID_KP=$!
sleep 5

for NS in tsb istio-system istio-gateway xcp-multicluster cert-manager ; do

  curl -k -H "Content-Type: application/json" -X PUT \
    -d "{ \"apiVersion\": \"v1\", \"kind\": \"Namespace\", \"metadata\": { \"name\": \"${NS}\" }, \"spec\": { \"finalizers\": [] } }" \
    http://127.0.0.1:8001/api/v1/namespaces/${NS}/finalize ;

done

kill ${PID_KP} ;
