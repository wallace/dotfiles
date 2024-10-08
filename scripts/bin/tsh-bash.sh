#!/bin/bash
#/ usage: tsh-bash [--env ENV] <app>
#/   --env ENV: the environment to connect to. one of dev, staging, loadtest, prod. (default: dev).
#/   <app>: the app whose utility pod to connect to. either rails or tourneys.

set -e

usage() {
  grep '^#/ ' <"$0" | cut -c4-
  exit 1
}

env=dev
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      env=$2
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

case "$env" in
  dev)
    cluster="dev01-gcpdev-us-east4"
    ;;
  staging)
    cluster="staging01-gcpstg-us-east4"
    ;;
  loadtest)
    cluster="load01-gcplt-us-east4"
    ;;
  prod)
    cluster="prod01-gcpprod-us-east4"
    ;;
  *)
    usage
    ;;
esac

case "$1" in
  rails)
    namespace="rails-api"
    pod="prizepicks-rails-utility-0"
    ;;
  tourneys)
    namespace="tourneys"
    pod="prizepicks-tourneys-utility-0"
    ;;
  *)
    usage
    ;;
esac

kubectl config current-context | grep -q "$cluster" || (
  tsh login --proxy=prizepicks.teleport.sh:443 prizepicks.teleport.sh --auth jc
  tsh kube login "$cluster"
)

exec kubectl exec -ti --namespace "$namespace" "$pod" -- bash
