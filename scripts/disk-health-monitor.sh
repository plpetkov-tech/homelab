#!/bin/bash

# Disk Health Monitoring Script for ClusterCreator
# This script monitors SSD health, LVM status, and connection issues

set -euo pipefail

# Configuration
PROXMOX_HOST="${PROXMOX_HOST:-10.11.12.136}"
GAMMA_DISKS="sda sdc sdd sde"
LOG_FILE="/tmp/disk-health-$(date +%Y%m%d).log"
ALERT_EMAIL="${ALERT_EMAIL:-}"
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

alert() {
    local message="$1"
    log "ALERT: $message"
    echo -e "${RED}🚨 ALERT: $message${NC}"
    
    # Send email alert if configured
    if [[ -n "$ALERT_EMAIL" ]]; then
        echo "$message" | mail -s "ClusterCreator Disk Alert" "$ALERT_EMAIL" 2>/dev/null || true
    fi
    
    # Send Telegram alert if configured
    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
            -d chat_id="$TELEGRAM_CHAT_ID" \
            -d text="🚨 ClusterCreator Disk Alert: $message" >/dev/null 2>&1 || true
    fi
}

warning() {
    local message="$1"
    log "WARNING: $message"
    echo -e "${YELLOW}⚠️  WARNING: $message${NC}"
}

success() {
    local message="$1"
    log "SUCCESS: $message"
    echo -e "${GREEN}✅ $message${NC}"
}

check_smart_health() {
    local disk="$1"
    local result
    
    log "Checking SMART health for /dev/$disk"
    
    if ! ssh root@"$PROXMOX_HOST" "smartctl -H /dev/$disk" >/dev/null 2>&1; then
        alert "Cannot access SMART data for /dev/$disk - disk may be disconnected"
        return 1
    fi
    
    result=$(ssh root@"$PROXMOX_HOST" "smartctl -H /dev/$disk" | grep "SMART overall-health" | awk '{print $NF}')
    
    if [[ "$result" != "PASSED" ]]; then
        alert "SMART health check FAILED for /dev/$disk - Status: $result"
        return 1
    fi
    
    return 0
}

check_smart_attributes() {
    local disk="$1"
    local temp wear_level reallocated
    
    log "Checking SMART attributes for /dev/$disk"
    
    # Get temperature
    temp=$(ssh root@"$PROXMOX_HOST" "smartctl -A /dev/$disk | grep Temperature_Celsius | head -1 | awk '{print \$10}'" 2>/dev/null || echo "N/A")
    
    # Get wear level (SSD specific)
    wear_level=$(ssh root@"$PROXMOX_HOST" "smartctl -A /dev/$disk | grep 'Wear_Leveling_Count\\|Media_Wearout_Indicator' | head -1 | awk '{print \$4}'" 2>/dev/null || echo "N/A")
    
    # Get reallocated sectors
    reallocated=$(ssh root@"$PROXMOX_HOST" "smartctl -A /dev/$disk | grep 'Reallocated_Sector_Ct\\|Reallocated_Event_Count' | head -1 | awk '{print \$10}'" 2>/dev/null || echo "N/A")
    
    # Check temperature
    if [[ "$temp" != "N/A" && "$temp" =~ ^[0-9]+$ && "$temp" -gt 70 ]]; then
        warning "/dev/$disk temperature is high: ${temp}°C"
    fi
    
    # Check wear level (lower is worse for SSDs)
    if [[ "$wear_level" != "N/A" && "$wear_level" =~ ^[0-9]+$ && "$wear_level" -lt 10 ]]; then
        alert "/dev/$disk wear level is critical: $wear_level%"
    elif [[ "$wear_level" != "N/A" && "$wear_level" =~ ^[0-9]+$ && "$wear_level" -lt 50 ]]; then
        warning "/dev/$disk wear level is low: $wear_level%"
    fi
    
    # Check reallocated sectors
    if [[ "$reallocated" != "N/A" && "$reallocated" =~ ^[0-9]+$ && "$reallocated" -gt 0 ]]; then
        warning "/dev/$disk has $reallocated reallocated sectors"
    fi
    
    log "/dev/$disk - Temp: ${temp}°C, Wear: $wear_level%, Reallocated: $reallocated"
}

check_disk_connectivity() {
    local disk="$1"
    local size
    
    log "Checking connectivity for /dev/$disk"
    
    # Check if disk is detected and has proper size
    size=$(ssh root@"$PROXMOX_HOST" "lsblk -b -n -o SIZE /dev/$disk 2>/dev/null | head -1" || echo "0")
    
    if [[ "$size" == "0" || ! "$size" =~ ^[0-9]+$ ]]; then
        alert "/dev/$disk shows 0 bytes or invalid size - disk disconnected or failed"
        return 1
    fi
    
    # Expected size for 1TB SSD (approximately)
    if [[ "$size" =~ ^[0-9]+$ && "$size" -lt 900000000000 ]]; then
        warning "/dev/$disk size is smaller than expected: $(($size / 1000000000))GB"
    fi
    
    # Test basic read operation
    if ! ssh root@"$PROXMOX_HOST" "dd if=/dev/$disk of=/dev/null bs=1M count=1" >/dev/null 2>&1; then
        alert "/dev/$disk failed basic read test - I/O errors detected"
        return 1
    fi
    
    return 0
}

check_lvm_health() {
    log "Checking LVM health for gamma volume group"
    
    # Check for missing PVs
    local missing_pvs
    missing_pvs=$(ssh root@"$PROXMOX_HOST" "vgs gamma 2>&1 | grep 'missing PV' | wc -l" || echo "0")
    
    if [[ "$missing_pvs" =~ ^[0-9]+$ && "$missing_pvs" -gt 0 ]]; then
        alert "Gamma volume group has $missing_pvs missing physical volumes"
        return 1
    fi
    
    # Check VG status
    local vg_status
    vg_status=$(ssh root@"$PROXMOX_HOST" "vgs --noheadings -o vg_attr gamma 2>/dev/null | head -1 | tr -d ' '")
    
    if [[ "${vg_status:0:1}" != "w" ]]; then
        alert "Gamma volume group is not writable (status: $vg_status)"
        return 1
    fi
    
    # Check thin pool status
    if ssh root@"$PROXMOX_HOST" "lvs gamma/data" >/dev/null 2>&1; then
        local pool_health
        pool_health=$(ssh root@"$PROXMOX_HOST" "lvs --noheadings -o lv_health_status gamma/data 2>/dev/null | head -1 | tr -d ' '")
        
        if [[ -n "$pool_health" && "$pool_health" != "" ]]; then
            warning "Gamma thin pool health status: $pool_health"
        fi
    fi
    
    success "LVM health check passed"
    return 0
}

check_kernel_messages() {
    log "Checking kernel messages for disk errors"
    
    local error_count
    error_count=$(ssh root@"$PROXMOX_HOST" "dmesg | grep -i 'error\\|fail' | grep -E 'sd[a-z]' | tail -10 | wc -l" 2>/dev/null || echo "0")
    
    if [[ "$error_count" =~ ^[0-9]+$ && "$error_count" -gt 0 ]]; then
        warning "Found $error_count recent disk-related error messages in kernel log"
        ssh root@"$PROXMOX_HOST" "dmesg | grep -i 'error\\|fail' | grep -E 'sd[a-z]' | tail -5" 2>/dev/null | while read -r line; do
            log "KERNEL: $line"
        done
    fi
}

run_disk_tests() {
    local disk="$1"
    
    echo "🔍 Testing /dev/$disk..."
    
    if ! check_disk_connectivity "$disk"; then
        return 1
    fi
    
    if ! check_smart_health "$disk"; then
        return 1
    fi
    
    check_smart_attributes "$disk"
    
    success "/dev/$disk passed all tests"
    return 0
}

main() {
    echo "🔍 ClusterCreator Disk Health Monitor"
    echo "=============================================="
    log "Starting disk health monitoring"
    
    local failed_disks=0
    local total_disks=0
    
    # Test each gamma datastore disk
    for disk in "${GAMMA_DISKS[@]}"; do
        total_disks=$((total_disks + 1))
        if ! run_disk_tests "$disk"; then
            failed_disks=$((failed_disks + 1))
        fi
        echo
    done
    
    # Check LVM health
    if ! check_lvm_health; then
        failed_disks=$((failed_disks + 1))
    fi
    
    # Check kernel messages
    check_kernel_messages
    
    echo "=============================================="
    if [[ "$failed_disks" -eq 0 ]]; then
        success "All disk health checks passed ($total_disks disks tested)"
    else
        alert "$failed_disks out of $total_disks disks failed health checks"
        exit 1
    fi
    
    log "Disk health monitoring completed"
}

# Show usage if --help is passed
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << EOF
ClusterCreator Disk Health Monitor

Usage: $0 [options]

Options:
  --help, -h     Show this help message

Environment Variables:
  PROXMOX_HOST          Proxmox host IP (default: 10.11.12.136)
  ALERT_EMAIL           Email address for alerts
  TELEGRAM_BOT_TOKEN    Telegram bot token for alerts
  TELEGRAM_CHAT_ID      Telegram chat ID for alerts

Examples:
  # Basic health check
  $0

  # With email alerts
  ALERT_EMAIL="admin@example.com" $0

  # Run from cron every hour
  0 * * * * /path/to/disk-health-monitor.sh

Exit Codes:
  0  All disks healthy
  1  One or more disks have issues
EOF
    exit 0
fi

main "$@"