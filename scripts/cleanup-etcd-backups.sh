#!/bin/bash

# Script to clean up old etcd backups across all etcd nodes
# Removes backup files older than 2 days to prevent disk space issues

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
ENDCOLOR='\033[0m'

usage() {
  echo "Usage: ccr cleanup-etcd-backups [OPTIONS]"
  echo ""
  echo "Cleans up old etcd backup files to prevent disk space issues"
  echo ""
  echo "OPTIONS:"
  echo "  -d, --days DAYS    Remove backups older than DAYS (default: 1)"
  echo "  -n, --dry-run      Show what would be deleted without actually deleting"
  echo "  -h, --help         Show this help message"
  echo ""
  echo "This script removes etcd backup files older than the specified number of days"
  echo "from /var/backups/etcd/ on all etcd nodes in the cluster."
}

# Default values
DAYS=1
DRY_RUN=false

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--days) DAYS="$2"; shift ;;
        -n|--dry-run) DRY_RUN=true ;;
        -h|--help) usage; exit 0 ;;
        *)
          echo "Unknown parameter passed: $1"
          usage
          exit 1
          ;;
    esac
    shift
done

# Validate days parameter
if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || [ "$DAYS" -lt 1 ]; then
    echo -e "${RED}Error: Days must be a positive integer${ENDCOLOR}"
    exit 1
fi

echo -e "${GREEN}Cleaning up etcd backups older than $DAYS day(s)...${ENDCOLOR}"

# Load cluster configuration
if [ ! -f "tmp/$CLUSTER_NAME/cluster_config.json" ]; then
    echo -e "${RED}Error: Cluster configuration not found. Run this from ClusterCreator directory.${ENDCOLOR}"
    exit 1
fi

# Get etcd node IPs from cluster config
ETCD_NODES=$(jq -r '.node_classes.etcd | "10.11.12." + (.start_ip | tostring) + " " + "10.11.12." + ((.start_ip + 1) | tostring) + " " + "10.11.12." + ((.start_ip + 2) | tostring)' tmp/$CLUSTER_NAME/cluster_config.json)

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}DRY RUN MODE - No files will be deleted${ENDCOLOR}"
fi

# Clean up backups on each etcd node
for node in $ETCD_NODES; do
    echo -e "${GREEN}Processing etcd node: $node${ENDCOLOR}"
    
    # Check if node is reachable
    if ! ping -c 1 -W 2 "$node" >/dev/null 2>&1; then
        echo -e "${RED}Warning: Node $node is not reachable, skipping...${ENDCOLOR}"
        continue
    fi
    
    # Show current disk usage
    echo "Current disk usage:"
    ssh plamen@"$node" "df -h / | grep -v Filesystem"
    
    # Find and show files to be deleted
    echo "Finding backup files older than $DAYS days..."
    OLD_FILES=$(ssh plamen@"$node" "sudo find /var/backups/etcd -name '*.db' -type f -mtime +$DAYS 2>/dev/null" || echo "")
    
    if [ -z "$OLD_FILES" ]; then
        echo "No old backup files found on $node"
        continue
    fi
    
    echo "Files to be removed:"
    ssh plamen@"$node" "sudo find /var/backups/etcd -name '*.db' -type f -mtime +$DAYS -exec ls -lah {} \; 2>/dev/null" | head -10
    
    FILE_COUNT=$(echo "$OLD_FILES" | wc -l)
    TOTAL_SIZE=$(ssh plamen@"$node" "sudo find /var/backups/etcd -name '*.db' -type f -mtime +$DAYS -exec du -ch {} \; 2>/dev/null | tail -1 | cut -f1" || echo "0")
    
    echo "Found $FILE_COUNT files totaling $TOTAL_SIZE"
    
    if [ "$DRY_RUN" = false ]; then
        echo "Removing old backup files..."
        ssh plamen@"$node" "sudo find /var/backups/etcd -name '*.db' -type f -mtime +$DAYS -delete 2>/dev/null" || echo "Warning: Some files could not be deleted"
        
        echo "Disk usage after cleanup:"
        ssh plamen@"$node" "df -h / | grep -v Filesystem"
    fi
    
    echo ""
done

if [ "$DRY_RUN" = false ]; then
    echo -e "${GREEN}Cleanup completed!${ENDCOLOR}"
    echo -e "${YELLOW}Consider setting up a cron job to run this cleanup automatically:${ENDCOLOR}"
    echo -e "${YELLOW}  0 2 * * * $PWD/scripts/cleanup-etcd-backups.sh -d 1${ENDCOLOR}"
else
    echo -e "${YELLOW}Dry run completed. Run without --dry-run to actually delete files.${ENDCOLOR}"
fi