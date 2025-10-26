# Gamma Volume Group Setup Guide

## Overview

The **gamma volume group** provides LVM-based storage on your Proxmox host for Longhorn distributed storage in the gamma Kubernetes cluster. This guide explains how to create and manage it using **disk IDs** instead of device names for idempotency and reliability.

## The Problem

Traditional LVM setups use device names like `/dev/sda`, `/dev/sdb`, etc. These have critical issues:

- **Device names change** when disks are reordered, added, or removed
- **System reboots** can enumerate devices differently
- **Disk failures** cause the VG to show `[unknown]` physical volumes
- **Non-idempotent** - running the same setup twice can target different disks

This causes the VG to stop working and break your Kubernetes cluster's storage.

## The Solution

Use `/dev/disk/by-id/*` paths which provide:

- ✅ **Stable identifiers** - based on hardware serial numbers
- ✅ **Idempotent** - always targets the same physical disks
- ✅ **Survives reboots** - disk IDs don't change
- ✅ **Easy troubleshooting** - clear mapping between IDs and physical disks
- ✅ **Safe disk replacement** - explicitly identify which disk to replace

## Quick Start

### 1. Identify Your Disks

When the Proxmox host is running, SSH in and identify your disks:

```bash
# List all disks with their details
ssh root@<proxmox-host> "lsblk -o NAME,SIZE,MODEL,SERIAL,TYPE"

# List disk IDs (these are what we'll use)
ssh root@<proxmox-host> "ls -la /dev/disk/by-id/ | grep -v part"
```

Look for entries like:
- `ata-WDC_WD40EFRX-68N32N0_WD-WCC7K1234567` (WD Red 4TB)
- `ata-ST4000VN008-2DR166_ZM12345678` (Seagate IronWolf 4TB)
- `wwn-0x5000c500a1234567` (SAS drives)

**Avoid using:**
- Anything with `-partN` at the end (these are partitions)
- `dm-*` or `lvm-*` entries (these are LVM devices)
- USB device IDs (unless you really want USB storage)

### 2. Clean Up Old VG (If Needed)

If you have an existing gamma VG that's broken or needs to be rebuilt:

```bash
./scripts/cleanup-gamma-vg.sh <proxmox-host> root
```

This script will:
- ⚠️  Show you what will be deleted (with warnings)
- Ask for explicit confirmation
- Safely remove the VG, LVs, and PVs
- Wipe disk signatures

**WARNING:** This destroys all data in the VG!

### 3. Create the Gamma VG

Run the Ansible playbook to create the VG idempotently:

#### Option A: Specify exact disk IDs

```bash
ansible-playbook -i "localhost," ansible/proxmox-gamma-vg-setup.yaml \
  -e "proxmox_host=10.11.12.10" \
  -e "proxmox_user=root" \
  -e "gamma_disk_ids=['ata-WDC_WD40EFRX-68N32N0_WD-XXX','ata-WDC_WD40EFRX-68N32N0_WD-YYY']"
```

#### Option B: Use a pattern to auto-discover disks

```bash
ansible-playbook -i "localhost," ansible/proxmox-gamma-vg-setup.yaml \
  -e "proxmox_host=10.11.12.10" \
  -e "proxmox_user=root" \
  -e "gamma_disk_pattern='ata-WDC_WD40EFRX.*'"
```

The playbook will:
- ✅ Validate all disks exist
- ✅ Show you the disk mapping
- ✅ Create PVs using disk IDs
- ✅ Create the gamma VG
- ✅ Save a configuration file for future reference

### 4. Create the Thin Pool

After the VG is created, set up the thin pool for Proxmox:

```bash
# Create thin pool (uses 95% of space, leaving room for metadata)
ssh root@<proxmox-host> "lvcreate -l 95%FREE -T gamma/data"

# Add to Proxmox storage configuration
ssh root@<proxmox-host> "pvesm add lvmthin gamma --thinpool data --vgname gamma"

# Verify it's available
ssh root@<proxmox-host> "pvesm status | grep gamma"
```

### 5. Deploy Your Cluster

Now you can run `terraform apply` to create VMs that use the gamma storage:

```bash
cd terraform
terraform workspace select gamma
terraform apply
```

The VMs will automatically get disks from the gamma storage (see `clusters.tf:146`).

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Proxmox Host                        │
│                                                         │
│  Physical Disks (using disk IDs):                      │
│  ┌────────────────────────────────────────────────┐    │
│  │ /dev/disk/by-id/ata-WDC_WD40EFRX..._WD-XXX    │    │
│  │ /dev/disk/by-id/ata-WDC_WD40EFRX..._WD-YYY    │    │
│  │ /dev/disk/by-id/ata-ST4000VN008..._ZM12345    │    │
│  └────────────────────────────────────────────────┘    │
│                          ↓                               │
│  Physical Volumes (PVs)                                 │
│  ┌────────────────────────────────────────────────┐    │
│  │ pvcreate /dev/disk/by-id/ata-WDC...           │    │
│  └────────────────────────────────────────────────┘    │
│                          ↓                               │
│  Volume Group: gamma                                    │
│  ┌────────────────────────────────────────────────┐    │
│  │ vgcreate gamma /dev/disk/by-id/ata-WDC... ...  │    │
│  │ Total Size: ~12TB (3x 4TB disks)               │    │
│  └────────────────────────────────────────────────┘    │
│                          ↓                               │
│  Thin Pool: gamma/data                                  │
│  ┌────────────────────────────────────────────────┐    │
│  │ lvcreate -l 95%FREE -T gamma/data              │    │
│  │ Provisioned: ~11.4TB                           │    │
│  └────────────────────────────────────────────────┘    │
│                          ↓                               │
│  Proxmox Storage: gamma (LVM-Thin)                      │
│  ┌────────────────────────────────────────────────┐    │
│  │ pvesm add lvmthin gamma --thinpool data        │    │
│  └────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│              Kubernetes VMs (gamma cluster)             │
│                                                         │
│  VM: gamma-general-0                                    │
│  ┌────────────────────────────────────────────────┐    │
│  │ Disk 1: 100GB (OS) from local-lvm              │    │
│  │ Disk 2: 1200GB (Longhorn) from gamma           │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  VM: gamma-general-1                                    │
│  ┌────────────────────────────────────────────────┐    │
│  │ Disk 1: 100GB (OS) from local-lvm              │    │
│  │ Disk 2: 1200GB (Longhorn) from gamma           │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  VM: gamma-general-2                                    │
│  ┌────────────────────────────────────────────────┐    │
│  │ Disk 1: 100GB (OS) from local-lvm              │    │
│  │ Disk 2: 1200GB (Longhorn) from gamma           │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│  Total: 3 x 1200GB = 3.6TB for Longhorn                │
│  Remaining: ~7.8TB available for future expansion      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│           Longhorn Distributed Storage                  │
│                                                         │
│  - Replicates data across 3 nodes                       │
│  - Provides PVCs for Kubernetes workloads               │
│  - Snapshots and backups                                │
└─────────────────────────────────────────────────────────┘
```

## Idempotency & Safety

The Ansible playbook is designed to be **idempotent** and **safe**:

### On First Run
- Creates PVs using disk IDs
- Creates the gamma VG
- Saves configuration for future reference

### On Subsequent Runs
- Detects if VG already exists
- Compares current vs desired disk configuration
- Only recreates if configuration differs
- **Prompts for confirmation** before destroying data

### Safety Features
- ✅ Validates all disks exist before proceeding
- ✅ Shows disk mapping and device paths
- ✅ Warns if VG has logical volumes
- ✅ Requires explicit confirmation to destroy data
- ✅ Checks for active VMs using the storage
- ✅ Creates a configuration summary file

## Common Operations

### Check VG Status

```bash
ssh root@<proxmox-host> "vgs gamma"
ssh root@<proxmox-host> "pvs | grep gamma"
ssh root@<proxmox-host> "lvs gamma"
```

### Add More Disks to VG

1. Identify new disk IDs
2. Update the `gamma_disk_ids` list with ALL disks (old + new)
3. Run the playbook - it will detect changes and prompt for recreation

```bash
ansible-playbook -i "localhost," ansible/proxmox-gamma-vg-setup.yaml \
  -e "proxmox_host=10.11.12.10" \
  -e "proxmox_user=root" \
  -e "gamma_disk_ids=['disk-1','disk-2','disk-3','NEW-disk-4']"
```

**Note:** Adding disks requires VG recreation, which destroys data. Plan accordingly!

### Replace a Failed Disk

1. Identify the failed disk:
```bash
ssh root@<proxmox-host> "pvs -o +pv_uuid,pv_missing | grep gamma"
```

2. Physically replace the disk

3. Run the cleanup script:
```bash
./scripts/cleanup-gamma-vg.sh <proxmox-host> root
```

4. Run the playbook with updated disk IDs:
```bash
ansible-playbook -i "localhost," ansible/proxmox-gamma-vg-setup.yaml \
  -e "proxmox_host=10.11.12.10" \
  -e "gamma_disk_ids=['new-disk-id-1','new-disk-id-2']"
```

### Verify Configuration

The playbook saves a configuration file to `/tmp/gamma-vg-config-<date>.txt` with:
- Disk IDs used
- Device mapping
- VG and PV information
- Command to recreate the same setup

Keep this file for your records!

### Force Rebuild

If you need to rebuild the VG without changing disks:

```bash
ansible-playbook -i "localhost," ansible/proxmox-gamma-vg-setup.yaml \
  -e "proxmox_host=10.11.12.10" \
  -e "gamma_disk_ids=['disk-1','disk-2']" \
  -e "force_recreate=true"
```

## Troubleshooting

### Issue: VG shows [unknown] physical volumes

**Cause:** Device names changed (e.g., /dev/sda became /dev/sdc)

**Solution:**
```bash
# Clean up the broken VG
./scripts/cleanup-gamma-vg.sh <proxmox-host> root

# Recreate using disk IDs
ansible-playbook -i "localhost," ansible/proxmox-gamma-vg-setup.yaml \
  -e "proxmox_host=10.11.12.10" \
  -e "gamma_disk_ids=['your-disk-ids']"
```

### Issue: Disk went bad

**Symptoms:**
- SMART errors
- Disk not responding
- VG shows missing PV

**Solution:**
1. Check disk health:
```bash
ssh root@<proxmox-host> "smartctl -a /dev/disk/by-id/<disk-id>"
```

2. Follow the "Replace a Failed Disk" procedure above

### Issue: Can't find disk IDs

**Solution:**
```bash
# List all block devices with their IDs
ssh root@<proxmox-host> "lsblk -o NAME,SIZE,MODEL,SERIAL"

# Find the corresponding disk-by-id path
ssh root@<proxmox-host> "ls -la /dev/disk/by-id/ | grep <serial-number>"
```

### Issue: Playbook says disk doesn't exist

**Causes:**
- Typo in disk ID
- Disk is actually not present
- Disk ID format changed

**Solution:**
```bash
# Verify the disk ID exists
ssh root@<proxmox-host> "ls -la /dev/disk/by-id/<your-disk-id>"

# Check for similar disk IDs
ssh root@<proxmox-host> "ls -la /dev/disk/by-id/ | grep -i <partial-match>"
```

### Issue: VG in use, can't remove

**Cause:** VMs are still using the storage

**Solution:**
```bash
# Find VMs using gamma storage
ssh root@<proxmox-host> "qm list | while read vmid name status; do
  qm config \$vmid 2>/dev/null | grep -q 'gamma:' && echo \"VM \$vmid uses gamma\"
done"

# Stop the VMs or migrate them first
ssh root@<proxmox-host> "qm stop <vmid>"
```

## Monitoring

The `scripts/disk-health-monitor.sh` script monitors the gamma VG health:

```bash
# It checks for:
# - Missing PVs
# - VG writability
# - Thin pool health

# Set up monitoring (if not already configured)
# Add to crontab or run via systemd timer
```

See `scripts/disk-health-monitor.sh:140` for implementation details.

## Files Reference

- **Ansible Playbook:** `ansible/proxmox-gamma-vg-setup.yaml`
  - Creates/manages the gamma VG idempotently
  - Uses disk IDs for stable device identification
  - Includes safety checks and confirmations

- **Cleanup Script:** `scripts/cleanup-gamma-vg.sh`
  - Safely removes the gamma VG
  - Checks for active VMs
  - Requires explicit confirmation

- **Terraform Documentation:** `terraform/vg.tf`
  - Documents the gamma VG requirements
  - Provides setup instructions
  - References relevant Terraform resources

- **Cluster Configuration:** `terraform/clusters.tf:146`
  - Defines VM disks using gamma storage
  - Configures Longhorn storage allocation

- **Disk Setup Playbook:** `ansible/longhorn-disks-setup.yaml`
  - Formats and mounts Longhorn disks on VMs
  - Uses UUIDs for idempotent mounting
  - Creates Longhorn data directories

## Best Practices

1. **Always use disk IDs** - Never use /dev/sdX device names
2. **Keep configuration records** - Save the generated config files
3. **Test after changes** - Verify VG and storage work after any changes
4. **Monitor disk health** - Use SMART monitoring and the health check script
5. **Plan disk replacements** - Have spare disks ready for hot swaps
6. **Document your setup** - Note which physical slot each disk ID corresponds to
7. **Regular backups** - Longhorn handles replication, but have backup strategies

## When You Need the Proxmox Host

You'll need to turn on the Proxmox host and SSH into it for:

1. **Initial setup** - Creating the gamma VG for the first time
2. **Disk identification** - Finding disk IDs
3. **Troubleshooting** - Checking VG/PV status
4. **Disk replacement** - Replacing failed disks
5. **Configuration changes** - Adding/removing disks from VG
6. **Health checks** - Verifying disk and VG health

For now, review this documentation. When you're ready to proceed, turn on the Proxmox host and I'll help you:
1. Identify the disk IDs
2. Clean up the old VG (if needed)
3. Create the new idempotent VG
4. Verify everything works

## Additional Resources

- [LVM Documentation](https://www.sourceware.org/lvm2/)
- [Proxmox Storage Documentation](https://pve.proxmox.com/wiki/Storage)
- [Longhorn Documentation](https://longhorn.io/docs/)
- [Disk ID Naming Conventions](https://wiki.archlinux.org/title/Persistent_block_device_naming)
