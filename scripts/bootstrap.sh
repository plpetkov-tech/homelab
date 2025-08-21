#!/bin/bash

usage() {
  echo "Usage: ccr bootstrap [OPTIONS]"
  echo ""
  echo "Runs a series of Ansible playbooks to bootstrap your Kubernetes cluster"
  echo ""
  echo "Options:"
  echo "  --addons-only        Run only storage and addon setup (Longhorn, Cilium LB, Flux, etc.)"
  echo "  --enable-metrics     Enable control plane metrics (works with both full bootstrap and --addons-only)"
  echo "  -h, --help           Show this help message"
  echo ""
  echo "The ansible playbooks handle:"
  echo " * Optional decoupled etcd cluster setup."
  echo " * Highly available control plane with Kube-VIP."
  echo " * Cilium CNI (with optional dual-stack networking)."
  echo " * Metrics server installation."
  echo " * StorageClass configuration."
  echo " * Longhorn distributed storage installation."
  echo " * Node labeling and tainting."
  echo " * Node preparation and joining."
}

# Parse command-line arguments
ADDONS_ONLY=false
ENABLE_METRICS=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --addons-only) ADDONS_ONLY=true ;;
        --enable-metrics) ENABLE_METRICS=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# Set environment variable for observability if requested
if [[ "$ENABLE_METRICS" == "true" ]]; then
    export ENABLE_CONTROL_PLANE_METRICS=true
    echo -e "${GREEN}Control plane metrics will be enabled during bootstrap.${ENDCOLOR}"
fi

# Cleanup
cleanup_files=(
  "tmp/${CLUSTER_NAME}/worker_join_command.sh"
  "tmp/${CLUSTER_NAME}/control_plane_join_command.sh"
)
set -e
trap 'echo "An error occurred. Cleaning up..."; cleanup_files "${cleanup_files[@]}"' ERR INT

if [[ "$ADDONS_ONLY" == "true" ]]; then
  echo -e "${GREEN}Running addons-only bootstrap for cluster: $CLUSTER_NAME.${ENDCOLOR}"
  echo -e "${YELLOW}This will only run storage and addon setup playbooks.${ENDCOLOR}"
  
  # Addons-only playbooks (from Longhorn onwards)
  playbooks=(
    "generate-hosts-txt.yaml"
    "trust-hosts.yaml"
    "kubelet-csr-approver.yaml"
    "local-storageclasses-setup.yaml"
    "longhorn-disks-setup.yaml"
    "longhorn-setup.yaml"
    "longhorn-add-disks.yaml"
    "metrics-server-setup.yaml"
    "cilium-lb-setup.yaml"
    "flux-setup.yaml"
    "gpu-operator-setup.yaml"
    "gpu-operator-validation-fix.yaml"
    "label-and-taint-nodes.yaml"
    "ending-output.yaml"
  )
  
  # Add observability playbook if metrics are requested
  if [[ "$ENABLE_METRICS" == "true" ]]; then
    echo -e "${GREEN}Control plane metrics will be enabled after addon setup.${ENDCOLOR}"
    playbooks+=("update-control-plane-metrics.yaml")
  fi
else
  echo -e "${GREEN}Bootstrapping Kubernetes onto cluster: $CLUSTER_NAME.${ENDCOLOR}"
  
  # Prompt for confirmation
  echo -e "${YELLOW}Warning: Once bootstrapped, you can't add/remove decoupled etcd nodes using this toolset.${ENDCOLOR}"
  read -r -p "Are you sure you want to proceed? (y/N): " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation canceled."
    exit 1
  fi

  # Full bootstrap playbooks
  playbooks=(
    "generate-hosts-txt.yaml"
    "trust-hosts.yaml"
    "prepare-nodes.yaml"
    "etcd-nodes-setup.yaml"
    "kubevip-setup.yaml"
    "controlplane-setup.yaml"
   "move-kubeconfig-local.yaml"
    "join-controlplane-nodes.yaml"
    "join-worker-nodes.yaml"
    "move-kubeconfig-remote.yaml"
    "conditionally-taint-controlplane.yaml"
    "etcd-encryption.yaml"
    "cilium-setup.yaml"
    "kubelet-csr-approver.yaml"
    "local-storageclasses-setup.yaml"
    "longhorn-disks-setup.yaml"
    "longhorn-setup.yaml"
    "longhorn-add-disks.yaml"
    "metrics-server-setup.yaml"
    "cilium-lb-setup.yaml"
    "flux-setup.yaml"
    "gpu-operator-setup.yaml"
    "gpu-operator-validation-fix.yaml"
    "label-and-taint-nodes.yaml"
    "ending-output.yaml"
  )
fi

# --------------------------- Script Start ---------------------------
run_playbooks "${playbooks[@]}"

echo -e "${GREEN}Cluster bootstrap completed successfully!${ENDCOLOR}"
echo -e "${GREEN}Components installed:${ENDCOLOR}"
echo -e "${GREEN}  • Kubernetes v${KUBERNETES_MEDIUM_VERSION}${ENDCOLOR}"
echo -e "${GREEN}  • Cilium CNI v${CILIUM_VERSION}${ENDCOLOR}"
echo -e "${GREEN}  • CoreDNS with search domain optimization (prevents DNS pollution)${ENDCOLOR}"
echo -e "${GREEN}  • Longhorn Storage v${LONGHORN_VERSION} (3x replication)${ENDCOLOR}"
echo -e "${GREEN}  • Cilium Load Balancer (integrated with CNI)${ENDCOLOR}"
echo -e "${GREEN}  • Flux GitOps v${FLUX_VERSION}${ENDCOLOR}"
echo -e "${GREEN}  • NVIDIA GPU Operator ${GPU_OPERATOR_VERSION} (if GPU nodes present)${ENDCOLOR}"
echo ""
echo -e "${GREEN}Access services:${ENDCOLOR}"
echo -e "${GREEN}  • Longhorn UI: kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80${ENDCOLOR}"
echo -e "${GREEN}  • Flux status: flux get all${ENDCOLOR}"
echo ""
echo -e "${GREEN}Source your bash or zsh profile and run 'kubectx ${CLUSTER_NAME}' to access the cluster from your local machine.${ENDCOLOR}"

# ---------------------------- Script End ----------------------------

cleanup_files "${cleanup_files[@]}"

echo -e "${GREEN}DONE${ENDCOLOR}"
