#!/bin/bash
#
# Targeted Longhorn Optimization Script
# 
# This script applies optimizations based on your specific cluster setup:
# - Full optimizations for general nodes (where Longhorn runs)
# - Partial optimizations for GPU node 
# - Minimal optimizations for control plane nodes
# - Skip ETCD nodes (too constrained)
#
# Based on analysis of your Proxmox cluster configuration
#

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Node classifications based on your terraform config
GENERAL_NODES=("10.11.12.140" "10.11.12.141" "10.11.12.142")  # 4 cores, 16GB, Longhorn storage
GPU_NODES=("10.11.12.150")                                     # 4 cores, 24GB, no Longhorn
CONTROLPLANE_NODES=("10.11.12.120" "10.11.12.121" "10.11.12.122") # 2 cores, 4GB
# ETCD nodes (10.11.12.110-112) are skipped - too constrained (1 core, 2GB)

USER="plamen"

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

run_on_nodes() {
    local nodes=("${!1}")
    local command="$2"
    local description="$3"
    
    log "Executing on $(IFS=,; echo "${nodes[*]}"): $description"
    
    for node in "${nodes[@]}"; do
        if ssh -o ConnectTimeout=10 "$USER@$node" "$command" 2>/dev/null; then
            success "Completed on $node"
        else
            warning "Skipped $node (may not be accessible)"
        fi
    done
    echo
}

# OPTIMIZATION 1: User-level file descriptor limits (missing from your template)
# WHY: Your template sets ContainerD limits but not user limits
# APPLIES TO: All nodes (your template already handles ContainerD)
optimize_user_file_descriptors() {
    log "=== FIXING USER FILE DESCRIPTOR LIMITS ==="
    warning "Your template handles ContainerD (1048576) but user limits are still 1024"
    
    local commands=$(cat << 'EOF'
# Check if already optimized
if ! grep -q "plamen.*nofile.*65536" /etc/security/limits.conf; then
    sudo cp /etc/security/limits.conf /etc/security/limits.conf.backup.$(date +%Y%m%d)
    echo '# User file descriptor optimization' | sudo tee -a /etc/security/limits.conf
    echo 'plamen soft nofile 65536' | sudo tee -a /etc/security/limits.conf
    echo 'plamen hard nofile 65536' | sudo tee -a /etc/security/limits.conf
    echo '* soft nofile 65536' | sudo tee -a /etc/security/limits.conf
    echo '* hard nofile 65536' | sudo tee -a /etc/security/limits.conf
    echo "User file descriptor limits set"
else
    echo "User file descriptor limits already optimized"
fi
EOF
)
    
    # Apply to all working nodes
    all_nodes=("${GENERAL_NODES[@]}" "${GPU_NODES[@]}" "${CONTROLPLANE_NODES[@]}")
    run_on_nodes all_nodes[@] "$commands" "User file descriptor limits"
}

# OPTIMIZATION 2: Memory management (missing from your template)
# WHY: Your template only has basic k8s sysctls, not memory optimization
# APPLIES TO: General nodes (high load) and GPU node (high memory)
optimize_memory_management() {
    log "=== OPTIMIZING MEMORY MANAGEMENT FOR HIGH-LOAD NODES ==="
    
    local commands=$(cat << 'EOF'
if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
    sudo cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d)
    cat >> /tmp/memory_opts.conf << 'MEM_EOF'

# Memory optimization for Longhorn workloads
vm.swappiness = 1
vm.dirty_ratio = 5  
vm.dirty_background_ratio = 2
vm.vfs_cache_pressure = 50
MEM_EOF
    sudo tee -a /etc/sysctl.conf < /tmp/memory_opts.conf
    rm /tmp/memory_opts.conf
    echo "Memory management optimized - requires reboot"
else
    echo "Memory management already optimized"
fi
EOF
)
    
    # Apply to general nodes (where load issues occur) and GPU node
    high_load_nodes=("${GENERAL_NODES[@]}" "${GPU_NODES[@]}")
    run_on_nodes high_load_nodes[@] "$commands" "Memory management optimization"
}

# OPTIMIZATION 3: Network buffers (missing from your template)  
# WHY: Essential for Longhorn replica synchronization
# APPLIES TO: General nodes (Longhorn) and GPU node (high bandwidth workloads)
optimize_network_buffers() {
    log "=== OPTIMIZING NETWORK BUFFERS ==="
    
    local commands=$(cat << 'EOF'
if ! grep -q "net.core.rmem_max" /etc/sysctl.conf; then
    cat >> /tmp/network_opts.conf << 'NET_EOF'

# Network optimization for replica sync
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_congestion_control = bbr
NET_EOF
    sudo tee -a /etc/sysctl.conf < /tmp/network_opts.conf
    rm /tmp/network_opts.conf
    echo "Network buffers optimized - requires reboot"
else
    echo "Network buffers already optimized"
fi
EOF
)
    
    high_bandwidth_nodes=("${GENERAL_NODES[@]}" "${GPU_NODES[@]}")
    run_on_nodes high_bandwidth_nodes[@] "$commands" "Network buffer optimization"
}

# OPTIMIZATION 4: IRQ balancing (missing)
# WHY: Your load average of 15-18 needs CPU interrupt distribution
# APPLIES TO: General nodes (high load) and GPU node
enable_irq_balancing() {
    log "=== ENABLING IRQ BALANCING FOR HIGH-LOAD NODES ==="
    
    local commands=$(cat << 'EOF'
if ! systemctl is-active --quiet irqbalance; then
    sudo apt update && sudo apt install -y irqbalance >/dev/null 2>&1 || echo "irqbalance install failed, may already be present"
    sudo systemctl enable irqbalance
    sudo systemctl start irqbalance
    echo "IRQ balancing enabled"
else
    echo "IRQ balancing already active"
fi
EOF
)
    
    high_load_nodes=("${GENERAL_NODES[@]}" "${GPU_NODES[@]}")
    run_on_nodes high_load_nodes[@] "$commands" "IRQ balancing"
}

# OPTIMIZATION 5: Disk I/O (ONLY for Longhorn nodes)
# WHY: Only general nodes have the 1.2TB Longhorn disks (/dev/vdb)
# APPLIES TO: General nodes ONLY
optimize_longhorn_disk_io() {
    log "=== OPTIMIZING LONGHORN DISK I/O (General Nodes Only) ==="
    
    local commands=$(cat << 'EOF'
if [ -b /dev/vdb ]; then
    # Your terraform shows vdb is the 1.2TB Longhorn disk
    echo 4096 | sudo tee /sys/block/vdb/queue/read_ahead_kb
    echo 512 | sudo tee /sys/block/vdb/queue/nr_requests
    
    # Create udev rules for persistence
    sudo tee /etc/udev/rules.d/99-longhorn-disk.rules << 'UDEV_EOF'
# Longhorn disk optimization (terraform: 1.2TB disk on general nodes)
ACTION=="add|change", KERNEL=="vdb", ATTR{queue/read_ahead_kb}="4096"  
ACTION=="add|change", KERNEL=="vdb", ATTR{queue/nr_requests}="512"
ACTION=="add|change", KERNEL=="vdb", ATTR{queue/scheduler}="mq-deadline"
UDEV_EOF
    echo "Longhorn disk I/O optimized"
else
    echo "No /dev/vdb found - not a Longhorn storage node"
fi
EOF
)
    
    # Only apply to general nodes (they have the Longhorn storage disks)
    run_on_nodes GENERAL_NODES[@] "$commands" "Longhorn disk I/O optimization"
}

# OPTIMIZATION 6: Process limits (for high-load nodes only)
# WHY: Your load of 15-18 indicates high process activity
# APPLIES TO: General nodes (high load)
optimize_process_limits() {
    log "=== OPTIMIZING PROCESS LIMITS FOR HIGH-LOAD NODES ==="
    
    local commands=$(cat << 'EOF'
if ! grep -q "kernel.pid_max" /etc/sysctl.conf; then
    cat >> /tmp/process_opts.conf << 'PROC_EOF'

# Process optimization for high-load Longhorn nodes  
kernel.pid_max = 131072
kernel.threads-max = 1048576
kernel.sched_migration_cost_ns = 5000000
PROC_EOF
    sudo tee -a /etc/sysctl.conf < /tmp/process_opts.conf
    rm /tmp/process_opts.conf
    echo "Process limits optimized - requires reboot"
else
    echo "Process limits already optimized"
fi
EOF
)
    
    # Only apply to general nodes where the load issues occur
    run_on_nodes GENERAL_NODES[@] "$commands" "Process limits for high load"
}

check_current_state() {
    log "=== CHECKING CURRENT STATE BY NODE CLASS ==="
    
    echo "GENERAL NODES (Full Longhorn optimization needed):"
    for node in "${GENERAL_NODES[@]}"; do
        echo "  $node:"
        echo "    Load: $(ssh "$USER@$node" "uptime | awk '{print \$10, \$11, \$12}'" 2>/dev/null || echo "N/A")"
        echo "    FD Limit: $(ssh "$USER@$node" "ulimit -n" 2>/dev/null || echo "N/A")"
        echo "    IRQ Balance: $(ssh "$USER@$node" "systemctl is-active irqbalance" 2>/dev/null || echo "N/A")"
        echo "    Longhorn Disk: $(ssh "$USER@$node" "test -b /dev/vdb && echo 'Present' || echo 'Missing'" 2>/dev/null || echo "N/A")"
    done
    
    echo -e "\nGPU NODE (Partial optimization needed):"
    for node in "${GPU_NODES[@]}"; do
        echo "  $node:"
        echo "    Load: $(ssh "$USER@$node" "uptime | awk '{print \$10, \$11, \$12}'" 2>/dev/null || echo "N/A")"
        echo "    FD Limit: $(ssh "$USER@$node" "ulimit -n" 2>/dev/null || echo "N/A")"
    done
    
    echo -e "\nCONTROL PLANE NODES (Minimal optimization):"
    for node in "${CONTROLPLANE_NODES[@]}"; do
        echo "  $node: $(ssh "$USER@$node" "uptime | awk '{print \$10, \$11, \$12}'" 2>/dev/null || echo "N/A")"
    done
}

create_targeted_monitoring() {
    cat > /home/plamen/monitor_targeted_health.sh << 'MONITOR_EOF'
#!/bin/bash
# Targeted monitoring based on node classes

GENERAL_NODES=("10.11.12.140" "10.11.12.141" "10.11.12.142")
GPU_NODES=("10.11.12.150")
USER="plamen"

echo "=== TARGETED LONGHORN HEALTH CHECK ==="
echo "Timestamp: $(date)"
echo

# Longhorn status
echo "Longhorn Volumes:"
kubectl get volumes.longhorn.io -n longhorn-system --no-headers | awk '{print $3}' | sort | uniq -c

echo -e "\nReplicas:"  
kubectl get replicas.longhorn.io -n longhorn-system --no-headers | awk '{print $3}' | sort | uniq -c

# Focus on problematic general nodes
echo -e "\nGENERAL NODE STATUS (Longhorn workhorses):"
for node in "${GENERAL_NODES[@]}"; do
    load=$(ssh "$USER@$node" "uptime | awk '{print \$10, \$11, \$12}'" 2>/dev/null || echo "unreachable")
    memory=$(ssh "$USER@$node" "free -h | awk 'NR==2{print \$3\"/\"\$2}'" 2>/dev/null || echo "N/A")
    echo "  $node: Load=$load Memory=$memory"
done

echo -e "\nGPU NODE STATUS:"
for node in "${GPU_NODES[@]}"; do
    load=$(ssh "$USER@$node" "uptime | awk '{print \$10, \$11, \$12}'" 2>/dev/null || echo "unreachable") 
    echo "  $node: Load=$load"
done

degraded=$(kubectl get volumes.longhorn.io -n longhorn-system -o custom-columns=ROBUSTNESS:.status.robustness --no-headers | grep degraded | wc -l)
echo -e "\nCRITICAL: $degraded degraded volumes"

if [ "$degraded" -gt 0 ]; then
    kubectl get volumes.longhorn.io -n longhorn-system -o custom-columns=NAME:.metadata.name,ROBUSTNESS:.status.robustness --no-headers | grep degraded
fi
MONITOR_EOF

    chmod +x /home/plamen/monitor_targeted_health.sh
    success "Created targeted monitoring: /home/plamen/monitor_targeted_health.sh"
}

main() {
    log "Starting TARGETED optimization based on your Proxmox cluster setup"
    log "General nodes: High-load Longhorn optimization"
    log "GPU node: Network and memory optimization" 
    log "Control plane: Basic optimization only"
    log "ETCD nodes: SKIPPED (too constrained: 1 core, 2GB)"
    echo
    
    check_current_state
    
    echo
    warning "This applies targeted optimizations based on your cluster architecture"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    # Apply optimizations by node class
    optimize_user_file_descriptors    # All nodes - fixes template gap
    optimize_memory_management        # General + GPU nodes
    optimize_network_buffers         # General + GPU nodes  
    enable_irq_balancing             # General + GPU nodes
    optimize_longhorn_disk_io        # General nodes ONLY (have /dev/vdb)
    optimize_process_limits          # General nodes ONLY (high load)
    
    create_targeted_monitoring
    
    echo
    success "=== TARGETED OPTIMIZATION COMPLETE ==="
    echo
    warning "REBOOT SEQUENCE:"
    warning "1. Reboot general nodes one at a time (they have the load issues)" 
    warning "2. Reboot GPU node"
    warning "3. Control plane nodes (if you applied optimizations)"
    warning "4. Monitor with: ./monitor_targeted_health.sh"
    echo
    log "Expected results on general nodes:"
    log "- Load average: 15-18 → target <8"
    log "- Rebuild success rate significantly improved"
    log "- Volume degradation should stop occurring"
}

main "$@"