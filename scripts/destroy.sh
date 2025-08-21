#!/bin/bash

# Source the required environment variables and functions
source "$(dirname "$0")/k8s.env"

usage() {
  echo "Usage: ccr destroy"
  echo ""
  echo "⚠️  DANGER: This command COMPLETELY DESTROYS all infrastructure for the current cluster!"
  echo ""
  echo "This will:"
  echo " * Stop and destroy all VMs"
  echo " * Delete all VM disks and storage"
  echo " * Remove all networks and VLANs (if created)"
  echo " * Delete VM template (if it exists)"
  echo " * Remove all Terraform state"
  echo " * Clean up local configuration files"
  echo ""
  echo "⚠️  WARNING: This action is IRREVERSIBLE and will result in COMPLETE DATA LOSS!"
  echo ""
  echo "Options:"
  echo "  --force       Skip all confirmation prompts (DANGEROUS)"
  echo "  -h, --help    Show this help message"
}

# Parse command-line arguments
FORCE_MODE=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --force) FORCE_MODE=true ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown parameter passed: $1"; usage; exit 1 ;;
    esac
    shift
done

# Set error handling
set -e
trap 'echo -e "${RED}An error occurred during destruction. Some resources may remain. Please check manually.${ENDCOLOR}"' ERR

# Validate cluster exists
if [ -z "$CLUSTER_NAME" ]; then
    echo -e "${RED}Error: No cluster context set. Use 'ccr ctx <cluster-name>' first.${ENDCOLOR}"
    exit 1
fi

# Check if workspace exists
cd "$REPO_PATH/terraform"
if ! tofu workspace list | grep -q -E "^[[:space:]]*(\*[[:space:]]*)?${CLUSTER_NAME}[[:space:]]*$"; then
    echo -e "${RED}Error: Terraform workspace '${CLUSTER_NAME}' does not exist.${ENDCOLOR}"
    echo -e "${YELLOW}Available workspaces:${ENDCOLOR}"
    tofu workspace list
    exit 1
fi

# Check if there are actually resources to destroy
tofu workspace select "$CLUSTER_NAME" >/dev/null 2>&1
RESOURCE_COUNT=$(tofu state list 2>/dev/null | wc -l)
if [ "$RESOURCE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}Warning: No Terraform resources found for cluster '${CLUSTER_NAME}'.${ENDCOLOR}"
    echo -e "${YELLOW}The cluster may already be destroyed or never existed.${ENDCOLOR}"
    read -r -p "Continue with cleanup of local files only? (y/N): " continue_cleanup
    if [[ ! "$continue_cleanup" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Operation cancelled.${ENDCOLOR}"
        exit 0
    fi
    SKIP_TERRAFORM=true
else
    echo -e "${GREEN}Found $RESOURCE_COUNT Terraform resources to destroy.${ENDCOLOR}"
    SKIP_TERRAFORM=false
fi

echo -e "${RED}╔══════════════════════════════════════════════════════════════════╗${ENDCOLOR}"
echo -e "${RED}║                        ⚠️  DANGER ZONE ⚠️                          ║${ENDCOLOR}"
echo -e "${RED}║                                                                  ║${ENDCOLOR}"
echo -e "${RED}║  You are about to COMPLETELY DESTROY cluster: $CLUSTER_NAME${ENDCOLOR}"
echo -e "${RED}║                                                                  ║${ENDCOLOR}"
echo -e "${RED}║  This will PERMANENTLY DELETE:                                  ║${ENDCOLOR}"
echo -e "${RED}║  • All VMs and their disks                                      ║${ENDCOLOR}"
echo -e "${RED}║  • All storage data (including Longhorn volumes)               ║${ENDCOLOR}"
echo -e "${RED}║  • All network configurations                                   ║${ENDCOLOR}"
echo -e "${RED}║  • All Kubernetes data and configurations                      ║${ENDCOLOR}"
echo -e "${RED}║  • Terraform state for this cluster                            ║${ENDCOLOR}"
echo -e "${RED}║                                                                  ║${ENDCOLOR}"
echo -e "${RED}║  ⚠️  THIS ACTION CANNOT BE UNDONE! ⚠️                             ║${ENDCOLOR}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${ENDCOLOR}"
echo ""

if [ "$FORCE_MODE" = false ]; then
    echo -e "${YELLOW}Are you absolutely sure you want to destroy cluster '$CLUSTER_NAME'?${ENDCOLOR}"
    echo -e "${YELLOW}This will delete ALL data and cannot be recovered.${ENDCOLOR}"
    echo ""
    read -r -p "Type 'DELETE-EVERYTHING' to confirm destruction: " confirm
    
    if [ "$confirm" != "DELETE-EVERYTHING" ]; then
        echo -e "${GREEN}Destruction cancelled. Cluster '$CLUSTER_NAME' remains intact.${ENDCOLOR}"
        exit 0
    fi
    
    echo ""
    echo -e "${RED}Final confirmation: Are you 100% certain? (yes/NO): ${ENDCOLOR}"
    read -r -p "" final_confirm
    
    if [[ ! "$final_confirm" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${GREEN}Destruction cancelled. Cluster '$CLUSTER_NAME' remains intact.${ENDCOLOR}"
        exit 0
    fi
fi

echo ""
echo -e "${RED}🔥 DESTRUCTION INITIATED for cluster: $CLUSTER_NAME 🔥${ENDCOLOR}"
echo ""

# Step 1: Destroy Terraform infrastructure
echo -e "${YELLOW}Step 1/5: Destroying Terraform infrastructure...${ENDCOLOR}"
cd "$REPO_PATH/terraform"

if [ "$SKIP_TERRAFORM" = true ]; then
    echo "    ⚠️  Skipping Terraform destruction (no resources found)"
elif [ -f ".terraform.lock.hcl" ]; then
    echo "  • Switching to cluster workspace..."
    tofu workspace select "$CLUSTER_NAME" 2>/dev/null || echo "    ⚠️  Workspace '$CLUSTER_NAME' not found, continuing..."
    
    echo "  • Checking and updating Terraform providers..."
    # Fix provider lock file issues
    tofu init -upgrade >/dev/null 2>&1 || {
        echo "    ⚠️  Provider upgrade failed, trying to reinitialize..."
        rm -f .terraform.lock.hcl
        tofu init >/dev/null 2>&1
    }
    
    echo "  • Running terraform destroy..."
    # Source environment variables to avoid var-file warnings
    if [ -f "../scripts/.env" ]; then
        echo "  • Loading environment variables..."
        set -a  # Automatically export all variables
        source "../scripts/.env"
        set +a  # Turn off automatic export
    fi
    
    if [ "$FORCE_MODE" = true ]; then
        tofu destroy -auto-approve
    else
        tofu destroy
    fi
    
    echo "  • Deleting workspace..."
    tofu workspace select default 2>/dev/null || true
    tofu workspace delete "$CLUSTER_NAME" 2>/dev/null || echo "    ⚠️  Could not delete workspace, may not exist"
else
    echo "    ⚠️  No Terraform state found, skipping infrastructure destruction"
fi

# Step 2: Clean up local Terraform state
echo -e "${YELLOW}Step 2/5: Cleaning up Terraform state and cache...${ENDCOLOR}"
echo "  • Removing Terraform cache..."
rm -rf .terraform/
rm -f .terraform.lock.hcl
rm -rf terraform.tfstate*
rm -rf .terraform.tfstate*

# Step 3: Remove generated Ansible configurations
echo -e "${YELLOW}Step 3/5: Cleaning up Ansible configurations...${ENDCOLOR}"
cd "$REPO_PATH/ansible"
if [ -d "tmp/$CLUSTER_NAME" ]; then
    echo "  • Removing cluster-specific Ansible configs..."
    rm -rf "tmp/$CLUSTER_NAME"
else
    echo "    ⚠️  No Ansible configs found for cluster '$CLUSTER_NAME'"
fi

# Step 4: Remove local kubeconfig
echo -e "${YELLOW}Step 4/5: Cleaning up local kubeconfig...${ENDCOLOR}"

# Try to find kubeconfig file(s) for this cluster
KUBECONFIG_PATTERNS=(
    "$HOME/.kube/${CLUSTER_NAME}.yml"
    "$HOME/.kube/${CLUSTER_NAME}.yaml"
    "$HOME/.kube/config.${CLUSTER_NAME}"
)

FOUND_KUBECONFIG=false
for pattern in "${KUBECONFIG_PATTERNS[@]}"; do
    if [ -f "$pattern" ]; then
        echo "  • Removing kubeconfig: $pattern"
        rm -f "$pattern"
        FOUND_KUBECONFIG=true
    fi
done

if [ "$FOUND_KUBECONFIG" = false ]; then
    echo "    ⚠️  No kubeconfig files found for cluster '$CLUSTER_NAME'"
fi

# Step 5: Remove cluster context
echo -e "${YELLOW}Step 5/5: Cleaning up cluster context...${ENDCOLOR}"
if [ -f "$HOME/.config/clustercreator/current_cluster" ]; then
    current_cluster=$(cat "$HOME/.config/clustercreator/current_cluster" 2>/dev/null || echo "")
    if [ "$current_cluster" = "$CLUSTER_NAME" ]; then
        echo "  • Clearing current cluster context..."
        rm -f "$HOME/.config/clustercreator/current_cluster"
    fi
fi

# Final status
echo ""
echo -e "${RED}╔══════════════════════════════════════════════════════════════════╗${ENDCOLOR}"
echo -e "${RED}║                    🔥 DESTRUCTION COMPLETE 🔥                    ║${ENDCOLOR}"
echo -e "${RED}║                                                                  ║${ENDCOLOR}"
echo -e "${RED}║  Cluster '$CLUSTER_NAME' has been completely destroyed.${ENDCOLOR}"
echo -e "${RED}║                                                                  ║${ENDCOLOR}"
echo -e "${RED}║  All VMs, storage, networks, and data have been deleted.        ║${ENDCOLOR}"
echo -e "${RED}║  Local configurations have been cleaned up.                    ║${ENDCOLOR}"
echo -e "${RED}║                                                                  ║${ENDCOLOR}"
echo -e "${RED}║  ⚠️  This action was irreversible. ⚠️                             ║${ENDCOLOR}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${ENDCOLOR}"
echo ""

echo -e "${GREEN}You can now create a new cluster with the same name if desired.${ENDCOLOR}"
echo -e "${GREEN}Use 'ccr ctx <cluster-name>' to switch to a different cluster.${ENDCOLOR}"
