#!/bin/bash
#
# One-time cleanup script to remove the old gamma volume group
# This is useful when you need to rebuild the VG from scratch
#
# ⚠️  WARNING: This will DESTROY ALL DATA in the gamma volume group!
# Make sure you have backed up any important data before running this script.
#
# Usage:
#   ./scripts/cleanup-gamma-vg.sh <proxmox_host> [proxmox_user]
#
# Example:
#   ./scripts/cleanup-gamma-vg.sh 10.11.12.10 root
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROXMOX_HOST="${1:-}"
PROXMOX_USER="${2:-root}"
VG_NAME="gamma"

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Function to run command on Proxmox host
run_on_proxmox() {
    ssh "${PROXMOX_USER}@${PROXMOX_HOST}" "$*"
}

# Validate input
if [[ -z "$PROXMOX_HOST" ]]; then
    log_error "Usage: $0 <proxmox_host> [proxmox_user]"
    log_error "Example: $0 10.11.12.10 root"
    exit 1
fi

log_info "=========================================="
log_info "Gamma Volume Group Cleanup Script"
log_info "=========================================="
log_info "Proxmox Host: ${PROXMOX_HOST}"
log_info "Proxmox User: ${PROXMOX_USER}"
log_info "Volume Group: ${VG_NAME}"
log_info ""

# Test SSH connection
log_info "Testing SSH connection to Proxmox host..."
if ! run_on_proxmox "echo 'Connection successful'" >/dev/null 2>&1; then
    log_error "Cannot connect to ${PROXMOX_USER}@${PROXMOX_HOST}"
    log_error "Please ensure:"
    log_error "  1. The host is reachable"
    log_error "  2. SSH key authentication is set up"
    log_error "  3. The user has sudo/root privileges"
    exit 1
fi
log_success "SSH connection successful"

# Check if VG exists
log_info "Checking if volume group '${VG_NAME}' exists..."
if ! run_on_proxmox "vgs ${VG_NAME}" >/dev/null 2>&1; then
    log_warning "Volume group '${VG_NAME}' does not exist. Nothing to clean up."
    exit 0
fi
log_success "Volume group '${VG_NAME}' found"

# Get VG information
log_info "Gathering volume group information..."
VG_INFO=$(run_on_proxmox "vgs --units g -o vg_name,pv_count,lv_count,vg_size,vg_free ${VG_NAME}" 2>/dev/null || true)
echo "$VG_INFO"
echo ""

# Get LV information
LV_COUNT=$(run_on_proxmox "lvs --noheadings -o lv_name ${VG_NAME} 2>/dev/null | wc -l" || echo "0")
if [[ $LV_COUNT -gt 0 ]]; then
    log_warning "Volume group has ${LV_COUNT} logical volume(s):"
    run_on_proxmox "lvs ${VG_NAME}" || true
    echo ""
fi

# Get PV information
log_info "Physical volumes in the volume group:"
PV_LIST=$(run_on_proxmox "pvs --noheadings -o pv_name,pv_size,pv_free | grep ${VG_NAME}" 2>/dev/null || true)
echo "$PV_LIST"
echo ""

# Get device mapping
log_info "Device to disk-id mapping:"
run_on_proxmox "pvs --noheadings -o pv_name ${VG_NAME} 2>/dev/null | while read pv; do
    echo -n \"  \$pv -> \"
    ls -la /dev/disk/by-id/ 2>/dev/null | grep \$(basename \$pv) | awk '{print \$9}' | head -1 || echo 'unknown'
done" || true
echo ""

# Check if VG is in use by Proxmox
log_info "Checking if VG is used by Proxmox storage..."
PROXMOX_STORAGE=$(run_on_proxmox "pvesm status 2>/dev/null | grep ${VG_NAME}" || echo "")
if [[ -n "$PROXMOX_STORAGE" ]]; then
    log_warning "Volume group is configured as Proxmox storage:"
    echo "$PROXMOX_STORAGE"
    echo ""
    log_warning "You may want to remove it from Proxmox storage config:"
    log_warning "  pvesm remove ${VG_NAME}"
    echo ""
fi

# Final confirmation
echo ""
log_error "⚠️  WARNING: This will DELETE the entire '${VG_NAME}' volume group!"
log_error "⚠️  ALL DATA in ${LV_COUNT} logical volume(s) will be PERMANENTLY LOST!"
echo ""
read -p "Are you ABSOLUTELY sure you want to proceed? Type 'DELETE ${VG_NAME}' to confirm: " confirmation

if [[ "$confirmation" != "DELETE ${VG_NAME}" ]]; then
    log_info "Cleanup cancelled. No changes made."
    exit 0
fi

echo ""
log_info "Starting cleanup process..."

# Step 1: Check for active VMs using the storage
log_info "Checking for active VMs using ${VG_NAME} storage..."
ACTIVE_VMS=$(run_on_proxmox "qm list 2>/dev/null | tail -n +2 | awk '{print \$1}' | while read vmid; do
    qm config \$vmid 2>/dev/null | grep -q \"${VG_NAME}:\" && echo \$vmid
done" || echo "")

if [[ -n "$ACTIVE_VMS" ]]; then
    log_warning "Found VMs using ${VG_NAME} storage:"
    for vmid in "${ACTIVE_VMS[@]}"; do
        VM_NAME=$(run_on_proxmox "qm config $vmid | grep '^name:' | cut -d' ' -f2" || echo "unknown")
        VM_STATUS=$(run_on_proxmox "qm status $vmid | awk '{print \$2}'" || echo "unknown")
        log_warning "  VM $vmid ($VM_NAME) - Status: $VM_STATUS"
    done
    echo ""
    log_error "Please stop and migrate or remove these VMs before proceeding."
    exit 1
fi
log_success "No active VMs found using ${VG_NAME} storage"

# Step 2: Deactivate all logical volumes
if [[ $LV_COUNT -gt 0 ]]; then
    log_info "Deactivating logical volumes..."
    if run_on_proxmox "lvchange -an ${VG_NAME}"; then
        log_success "Logical volumes deactivated"
    else
        log_warning "Some logical volumes could not be deactivated (this may be OK)"
    fi
fi

# Step 3: Remove logical volumes
if [[ $LV_COUNT -gt 0 ]]; then
    log_info "Removing logical volumes..."
    if run_on_proxmox "lvremove -f ${VG_NAME}"; then
        log_success "Logical volumes removed"
    else
        log_error "Failed to remove logical volumes"
        exit 1
    fi
fi

# Step 4: Deactivate volume group
log_info "Deactivating volume group..."
if run_on_proxmox "vgchange -an ${VG_NAME}"; then
    log_success "Volume group deactivated"
else
    log_warning "Volume group could not be deactivated (this may be OK)"
fi

# Step 5: Remove volume group
log_info "Removing volume group..."
if run_on_proxmox "vgremove -f ${VG_NAME}"; then
    log_success "Volume group removed"
else
    log_error "Failed to remove volume group"
    exit 1
fi

# Step 6: Get list of PVs that were in the VG
log_info "Removing physical volumes..."
PV_DEVICES=$(echo "$PV_LIST" | awk '{print $1}')
for pv in "${PV_DEVICES[@]}"; do
    log_info "  Removing PV: $pv"
    if run_on_proxmox "pvremove -ff $pv"; then
        log_success "    PV removed: $pv"
    else
        log_warning "    Could not remove PV: $pv (may already be removed)"
    fi
done

# Step 7: Wipe filesystem signatures
log_info "Wiping filesystem signatures..."
for pv in "${PV_DEVICES[@]}"; do
    log_info "  Wiping: $pv"
    if run_on_proxmox "wipefs -a $pv 2>/dev/null"; then
        log_success "    Wiped: $pv"
    else
        log_warning "    Could not wipe: $pv (may already be clean)"
    fi
done

# Step 8: Remove from Proxmox storage config if present
if [[ -n "$PROXMOX_STORAGE" ]]; then
    log_info "Removing ${VG_NAME} from Proxmox storage configuration..."
    if run_on_proxmox "pvesm remove ${VG_NAME} 2>/dev/null"; then
        log_success "Removed from Proxmox storage configuration"
    else
        log_warning "Could not remove from storage config (may not be configured)"
    fi
fi

# Final verification
echo ""
log_info "Verifying cleanup..."
if run_on_proxmox "vgs ${VG_NAME}" >/dev/null 2>&1; then
    log_error "Volume group still exists! Cleanup may have failed."
    exit 1
else
    log_success "Volume group successfully removed"
fi

echo ""
log_success "=========================================="
log_success "Cleanup completed successfully!"
log_success "=========================================="
echo ""
log_info "Next steps:"
log_info "1. Run the Ansible playbook to create a new gamma VG:"
log_info "   ansible-playbook -i \"localhost,\" ansible/proxmox-gamma-vg-setup.yaml \\"
log_info "     -e \"proxmox_host=${PROXMOX_HOST}\" \\"
log_info "     -e \"proxmox_user=${PROXMOX_USER}\" \\"
log_info "     -e \"gamma_disk_ids=['disk-id-1','disk-id-2',...]'\""
echo ""
log_info "2. To find available disk IDs, run:"
log_info "   ssh ${PROXMOX_USER}@${PROXMOX_HOST} \"ls -la /dev/disk/by-id/ | grep -v part\""
echo ""
