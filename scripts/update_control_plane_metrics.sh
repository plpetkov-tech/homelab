#!/bin/bash

usage() {
  echo "Usage: ccr update-metrics"
  echo ""
  echo "Updates existing cluster to expose control plane metrics for monitoring"
  echo ""
  echo "This script safely updates static pod manifests to configure:"
  echo "  • kube-scheduler metrics on 0.0.0.0:10259"
  echo "  • kube-controller-manager metrics on 0.0.0.0:10257"
  echo "  • etcd metrics on external interface:2381"
  echo ""
  echo "The script uses the move-edit-move method for safe static pod updates"
  echo "and creates backups before making any changes."
  echo ""
  echo "WARNING: This modifies critical Kubernetes control plane components."
  echo "Ensure you have VM backups before proceeding."
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) usage; exit 0 ;;
        *)
          echo "Unknown parameter passed: $1"
          usage
          exit 1
          ;;
    esac
    shift
done

echo -e "${GREEN}Updating control plane metrics configuration for cluster: $CLUSTER_NAME${ENDCOLOR}"

# User confirmation prompt
echo -e "${YELLOW}WARNING:${ENDCOLOR} This script will modify control plane static pod manifests to expose metrics endpoints."
echo ""
echo -e "${YELLOW}This process will temporarily restart control plane components.${ENDCOLOR}"
echo -e "Please ensure you have taken VM backups before proceeding."
echo ""
read -p "Do you understand the risks and wish to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
  echo -e "${RED}Update aborted by the user.${ENDCOLOR}"
  exit 1
fi

echo -e "${GREEN}Updating control plane metrics configuration for cluster: $CLUSTER_NAME${ENDCOLOR}"

# --------------------------- Script Start ---------------------------

playbooks=(
  "trust-hosts.yaml"
  "update-control-plane-metrics.yaml"
)

run_playbooks "${playbooks[@]}"

# ---------------------------- Script End ----------------------------

echo -e "${GREEN}Control plane metrics configuration updated successfully!${ENDCOLOR}"
echo -e "${GREEN}Metrics endpoints are now available at:${ENDCOLOR}"
echo -e "${GREEN}  • kube-scheduler: http://[control-plane-ip]:10259/metrics${ENDCOLOR}"
echo -e "${GREEN}  • kube-controller-manager: http://[control-plane-ip]:10257/metrics${ENDCOLOR}"
echo -e "${GREEN}  • etcd: https://[etcd-ip]:2381/metrics${ENDCOLOR}"
echo ""
echo -e "${GREEN}Backups created in /etc/kubernetes/backups/ on each node${ENDCOLOR}"