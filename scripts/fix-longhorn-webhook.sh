#!/bin/bash

# Fix Longhorn conversion webhook issue that causes API server overload
#
# ISSUE: Longhorn v1.10.0 has a broken conversion webhook (port 9501) that doesn't start
# but the CRDs are configured to use it. This causes the API server to continuously
# hammer the missing webhook, consuming 50%+ of control plane RAM and causing cluster
# instability (timeouts, failed deployments, controller-manager crashloops).
#
# SOLUTION: Remove the conversion webhook configuration from all Longhorn CRDs.

set -e

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../.clustercreator/common.sh"

# Required Variables
required_vars=(
  "CLUSTER_NAME"
)
check_required_vars "${required_vars[@]}"

KUBECONFIG_FILE="${HOME}/.kube/${CLUSTER_NAME}.yml"

echo -e "${BLUE}Fixing Longhorn conversion webhook configuration for cluster: ${CLUSTER_NAME}${ENDCOLOR}"

# List of Longhorn CRDs with conversion webhook configured
LONGHORN_CRDS=(
  "volumes.longhorn.io"
  "nodes.longhorn.io"
  "engineimages.longhorn.io"
  "backuptargets.longhorn.io"
  "replicas.longhorn.io"
  "engines.longhorn.io"
  "instancemanagers.longhorn.io"
  "sharemanagers.longhorn.io"
  "backingimages.longhorn.io"
  "backupvolumes.longhorn.io"
  "backups.longhorn.io"
  "recurringjobs.longhorn.io"
  "settings.longhorn.io"
  "volumeattachments.longhorn.io"
)

for crd in "${LONGHORN_CRDS[@]}"; do
  echo -e "${GREEN}Patching CRD: ${crd}${ENDCOLOR}"
  KUBECONFIG="$KUBECONFIG_FILE" kubectl patch crd "$crd" --type=json -p='[{"op": "remove", "path": "/spec/conversion"}]' 2>&1 || {
    echo -e "${YELLOW}Warning: Could not patch ${crd} (may not exist or already patched)${ENDCOLOR}"
  }
done

echo -e "${GREEN}✅ Fixed Longhorn conversion webhook configuration!${ENDCOLOR}"
echo -e "${BLUE}The API server should now stabilize and free up memory.${ENDCOLOR}"
echo ""
echo -e "${BLUE}Monitor improvement with:${ENDCOLOR}"
echo -e "  ssh plamen@<control-plane-ip> 'free -h'"
echo -e "  kubectl top nodes"
