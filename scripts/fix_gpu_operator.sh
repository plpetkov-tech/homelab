#!/bin/bash

usage() {
  echo "Usage: ccr fix-gpu-operator [OPTIONS]"
  echo ""
  echo "Fixes the GPU operator validation deadlock issue when driver.enabled=false"
  echo ""
  echo "Options:"
  echo "  --force          Force restart of GPU operator even if already running"
  echo "  --deploy-working Deploy working GPU components that bypass broken node selectors"
  echo "  -h, --help       Show this help message"
  echo ""
  echo "This script addresses the known issue where GPU operator DaemonSets"
  echo "don't schedule when using pre-installed drivers (driver.enabled=false)."
  echo "The fix creates persistent validation files and working DaemonSets."
  echo ""
  echo "Problem solved:"
  echo " * Driver-validation init container deadlock"
  echo " * Missing /run/nvidia/validations/ files"
  echo " * DaemonSets stuck at Desired: 0, Current: 0"
  echo " * GPU operator broken node selector logic"
  echo " * No nvidia.com/gpu resources available"
}

# Parse command-line arguments
FORCE_RESTART=false
DEPLOY_WORKING=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --force) FORCE_RESTART=true ;;
        --deploy-working) DEPLOY_WORKING=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

echo -e "${GREEN}Applying GPU operator validation fix for cluster: $CLUSTER_NAME${ENDCOLOR}"
echo -e "${YELLOW}This fixes the known driver-validation deadlock issue with driver.enabled=false${ENDCOLOR}"

# User confirmation
if [[ "$FORCE_RESTART" == "true" ]]; then
    echo -e "${YELLOW}Force restart enabled - will restart GPU operator pods${ENDCOLOR}"
else
    echo -e "${BLUE}This fix will:${ENDCOLOR}"
    echo "  • Create persistent validation files on GPU nodes"
    echo "  • Establish systemd service for validation persistence"
    echo "  • Force GPU operator DaemonSet reconciliation"
    echo "  • Enable proper scheduling of GPU operator components"
    echo ""
    read -r -p "Do you want to apply the GPU operator validation fix? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Fix canceled."
        exit 1
    fi
fi

echo -e "${GREEN}Applying GPU operator validation fix...${ENDCOLOR}"

# --------------------------- Script Start ---------------------------

export FORCE_GPU_RESTART="$FORCE_RESTART"

playbooks=(
  "trust-hosts.yaml"
  "gpu-operator-validation-fix.yaml"
)

run_playbooks "${playbooks[@]}"

# Deploy working components if requested
if [[ "$DEPLOY_WORKING" == "true" ]]; then
    echo -e "${GREEN}Deploying working GPU operator components...${ENDCOLOR}"
    run_playbooks "gpu-operator-working-daemonsets.yaml"
fi

# ---------------------------- Script End ----------------------------

echo -e "${GREEN}GPU operator validation fix applied successfully!${ENDCOLOR}"
echo ""
echo -e "${GREEN}Next Steps:${ENDCOLOR}"
echo "1. Monitor GPU operator pod startup: ${BLUE}kubectl get pods -n gpu-operator -w${ENDCOLOR}"
echo "2. Check GPU resources: ${BLUE}kubectl get nodes -l nodeclass=gpu -o wide${ENDCOLOR}"
echo "3. Verify DaemonSets: ${BLUE}kubectl get daemonsets -n gpu-operator${ENDCOLOR}"
echo "4. Check validation status: ${BLUE}sudo /usr/local/bin/check-gpu-operator-status.sh${ENDCOLOR}"
echo ""
echo -e "${GREEN}Expected timeline: 5-15 minutes for full GPU operator deployment${ENDCOLOR}"
echo ""
echo -e "${BLUE}Test GPU functionality when ready:${ENDCOLOR}"
echo "kubectl run gpu-test --rm -it --restart=Never --image=nvidia/cuda:12.0-runtime-ubuntu20.04 --overrides='{\"spec\":{\"tolerations\":[{\"key\":\"gpu\",\"operator\":\"Equal\",\"value\":\"true\",\"effect\":\"NoSchedule\"}],\"nodeSelector\":{\"nvidia.com/gpu\":\"true\"}}}' -- nvidia-smi"