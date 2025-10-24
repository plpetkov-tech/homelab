#!/bin/bash

# Script to add 1.5TB disks to Longhorn nodes
# Make sure you're using the correct kubeconfig context before running this script

DISK_PATH="/var/lib/longhorn-disk/longhorn-data"
NODES=("gamma-general-0" "gamma-general-1" "gamma-general-2")

echo "Adding 1.5TB storage disks to Longhorn nodes..."

for node in "${NODES[@]}"; do
    echo "Processing node: $node"
    
    # Generate a unique disk name
    disk_name="longhorn-disk-$(echo "$node" | sed 's/gamma-general-//')"
    
    # Create the patch to add the new disk
    cat <<EOF > /tmp/longhorn-disk-patch-${node}.yaml
spec:
  disks:
    ${disk_name}:
      allowScheduling: true
      diskDriver: ""
      diskType: filesystem
      evictionRequested: false
      path: "${DISK_PATH}"
      storageReserved: 107374182400
      tags: []
EOF

    echo "Adding disk ${disk_name} to node ${node}..."
    kubectl patch node.longhorn.io "$node" -n longhorn-system --patch-file /tmp/longhorn-disk-patch-"$node".yaml --type=merge
    
    if [ $? -eq 0 ]; then
        echo "✓ Successfully added disk to $node"
    else
        echo "✗ Failed to add disk to $node"
    fi
    
    # Clean up temp file
    rm -f /tmp/longhorn-disk-patch-"$node".yaml
done

echo ""
echo "Waiting for Longhorn to detect new disks..."
sleep 30

echo ""
echo "Current Longhorn storage status:"
kubectl get nodes.longhorn.io -n longhorn-system

echo ""
echo "Detailed disk information:"
for node in "${NODES[@]}"; do
    echo "=== $node ==="
    kubectl get node.longhorn.io "$node" -n longhorn-system -o jsonpath='{.status.diskStatus}' | jq '.'
    echo ""
done