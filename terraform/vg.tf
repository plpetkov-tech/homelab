# Gamma Volume Group Configuration
# ==================================
#
# This file documents the gamma volume group used for Longhorn storage.
# The VG is created on the Proxmox host (not in Terraform) using Ansible.
#
# �  IMPORTANT: The gamma VG must be created on the Proxmox host BEFORE
# running terraform apply, as it's used by the VMs in the gamma cluster.
#
# Overview:
# ---------
# The gamma volume group provides storage for Longhorn distributed storage
# in the gamma Kubernetes cluster. Each "general" node class VM gets a 1200GB
# disk from this storage, which Longhorn then uses for replicated storage.
#
# Why use disk IDs instead of device names?
# ------------------------------------------
# Device names like /dev/sda, /dev/sdb change when:
# - Disks are reordered in the system
# - A disk fails and is replaced
# - The system reboots with a different device enumeration
# - You add or remove disks
#
# Using /dev/disk/by-id/* paths provides:
# - Stable, hardware-based identifiers
# - Idempotent configuration
# - Protection against accidental data loss
# - Easier troubleshooting
#
# Setup Instructions:
# -------------------
#
# 1. First, identify your disks on the Proxmox host:
#    ssh root@<proxmox-host> "lsblk -o NAME,SIZE,MODEL,SERIAL"
#    ssh root@<proxmox-host> "ls -la /dev/disk/by-id/ | grep -v part"
#
# 2. Find the disk IDs you want to use (look for ata-*, scsi-*, or wwn-* entries)
#    Example disk IDs:
#    - ata-WDC_WD40EFRX-68N32N0_WD-WCC7K1234567
#    - ata-ST4000VN008-2DR166_ZM12345678
#
# 3. If you need to clean up an existing gamma VG:
#    ./scripts/cleanup-gamma-vg.sh <proxmox-host> root
#
# 4. Create the gamma VG using the Ansible playbook:
#    ansible-playbook -i "localhost," ansible/proxmox-gamma-vg-setup.yaml \
#      -e "proxmox_host=10.11.12.10" \
#      -e "proxmox_user=root" \
#      -e "gamma_disk_ids=['ata-WDC_WD40EFRX-68N32N0_WD-XXX','ata-ST4000VN008-2DR166_ZM123456']"
#
#    OR use a pattern to auto-discover disks:
#    ansible-playbook -i "localhost," ansible/proxmox-gamma-vg-setup.yaml \
#      -e "proxmox_host=10.11.12.10" \
#      -e "proxmox_user=root" \
#      -e "gamma_disk_pattern='ata-WDC_WD40EFRX.*'"
#
# 5. The playbook will:
#    - Create physical volumes using disk IDs
#    - Create the gamma volume group
#    - Provide instructions for creating a thin pool
#    - Provide instructions for adding to Proxmox storage
#
# 6. Follow the post-setup instructions to create the thin pool:
#    ssh root@<proxmox-host> "lvcreate -l 95%FREE -T gamma/data"
#    ssh root@<proxmox-host> "pvesm add lvmthin gamma --thinpool data --vgname gamma"
#
# 7. Now you can run terraform apply to create VMs that use the gamma storage
#
# Troubleshooting:
# ----------------
#
# Issue: VG shows [unknown] physical volumes
# Solution: This happens when device names change. Run the Ansible playbook
#           with force_recreate=true to rebuild using disk IDs
#
# Issue: Disk went bad and needs replacement
# Solution:
#   1. Identify the failed disk: ssh root@<proxmox-host> "pvs -o +pv_uuid,pv_missing"
#   2. Replace the physical disk
#   3. Run cleanup script to remove old VG
#   4. Run Ansible playbook with updated disk IDs
#
# Issue: Need to add more disks to the VG
# Solution: Update gamma_disk_ids and run the playbook with the full list
#           of disks (the playbook will detect changes and prompt for recreation)
#
# Monitoring:
# -----------
# The disk-health-monitor.sh script monitors the gamma VG health:
# - Checks for missing PVs
# - Verifies VG is writable
# - Monitors thin pool health (if configured)
#
# Storage Configuration in clusters.tf:
# --------------------------------------
# See clusters.tf:147 where the gamma datastore is referenced:
#   datastore  = "gamma"
#   size       = 1100  # GB per VM
#
# Current allocation:
# - Total VG Size: 3.73TB (4x 1TB ADATA SU750 SSDs)
# - Thin Pool: 3.62TB (95% of VG)
# - Per-Node Allocation: 1100GB × 3 nodes = 3.3TB
# - Utilization: 91% (healthy)
# - Buffer: ~324GB for thin pool metadata and overhead
#

# No actual Terraform resources here - this is just documentation
# The gamma VG is managed via Ansible on the Proxmox host

# Optional: You could add a null_resource with a local-exec provisioner
# to automatically run the Ansible playbook, but it's better to run it
# manually to have control over the disk selection and confirmation prompts.
