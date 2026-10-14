#!/bin/sh
# Creates the IAM roles and EKS Pod Identity associations the platform layer needs.
# Run once per workload cluster; safe to re-run.
# usage: bootstrap/iam/setup.sh <cluster-name> <region>
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <cluster-name> <region>" >&2
  exit 2
fi

cluster=$1
region=$2
dir=$(cd "$(dirname "$0")" && pwd)

# Prints the ARN of role <cluster>-<policy>, creating the role on first run.
role() {
  name="$cluster-$1"
  if ! aws iam get-role --role-name "$name" >/dev/null 2>&1; then
    aws iam create-role --role-name "$name" \
      --assume-role-policy-document "file://$dir/pod-identity-trust.json" >/dev/null
  fi
  aws iam put-role-policy --role-name "$name" --policy-name "$1" \
    --policy-document "file://$dir/$1.json"
  aws iam get-role --role-name "$name" --query Role.Arn --output text
}

# associate <namespace> <service-account> <role-arn>
associate() {
  existing=$(aws eks list-pod-identity-associations --region "$region" --cluster-name "$cluster" \
    --namespace "$1" --service-account "$2" --query 'associations[0].associationId' --output text)
  if [ "$existing" = "None" ]; then
    aws eks create-pod-identity-association --region "$region" --cluster-name "$cluster" \
      --namespace "$1" --service-account "$2" --role-arn "$3" >/dev/null
  fi
}

fluent_bit_role=$(role fluent-bit)
monitoring_role=$(role monitoring-secrets)

associate logging fluent-bit "$fluent_bit_role"
associate monitoring alertmanager "$monitoring_role"
associate monitoring grafana "$monitoring_role"
