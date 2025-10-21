# 🏠 Homelab Infrastructure

A battle-tested Kubernetes homelab that provisions production-grade clusters from bare Proxmox VMs to fully operational infrastructure in minutes. ⚡

### The Magic ✨

**Cluster Definition** 📝 → **Infrastructure Provisioning** 🚀 → **GitOps Deployment** 🎯

Define your entire cluster in 50 lines of HCL. Run two commands. Get a production cluster with: 🔥
- External etcd cluster
- GPU nodes with PCIe passthrough for AI workloads
- Longhorn storage that works for RWX and RWO 
- Istio ambient mesh securing and observing networking
- Prometheus metrics from every component including control plane components and Longhorn

### My Cluster: "Gamma" 🌟

My `gamma` cluster configuration:
- **3x etcd nodes**: Dedicated external etcd for bulletproof data persistence
- **3x control plane**: HA API server with kube-vip load balancing  
- **3x general nodes**: 16GB RAM each with 1.2TB Longhorn storage
- **1x GPU node**: 24GB RAM with full PCIe GPU passthrough of my `NVIDIA GeForce RTX 3060 12GB`

Each node class is independently scalable with different resource profiles, storage configurations, and scheduling constraints.

## The Stack 🛠️

**Infrastructure Layer** 🏗️
- Proxmox VE hypervisor with Terraform provisioning
- Cilium CNI with eBPF networking and load balancing
- Longhorn distributed block storage 
- External etcd cluster for maximum data safety

**Platform Layer** 🎛️
- Istio service mesh in ambient mode (zero sidecar overhead)
- Flux v2 GitOps with SOPS age-encrypted secrets
- Cert-manager with Let's Encrypt automation
- Velero backup operator
- Renovate bot for automated dependency updates

**Observability** 👁️
- Prometheus + Grafana with 30+ dashboards
- Loki log aggregation with retention policies
- Alloy telemetry collection
- Full control plane metrics (etcd, scheduler, controller-manager)

**Applications** 📱
- PostgreSQL with CloudNativePG operator
- AI/ML stack: Jupyter, GPU scheduling
- N8N workflow automation
- Media services (Radarr, Sonarr, etc.)
- Hoarder bookmark management

## Deployment 🚀

### Proxmox Prerequisites 📋

Before anything else, set up Proxmox VE access:

```bash
# SSH into the proxmox host

# 1. Create Proxmox user
pveum user add terraform@pve

# 2. Create custom role with required permissions
pveum role add TerraformProv -privs "Audit,Datastore.Allocate,Datastore.AllocateSpace,Datastore.AllocateTemplate,Datastore.Audit,Pool.Allocate,SDN.Use,Sys.Audit,Sys.Console,Sys.Modify,VM.Allocate,VM.Audit,VM.Clone,VM.Config.CDROM,VM.Config.Cloudinit,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Console,VM.Migrate,VM.Monitor,VM.PowerMgmt"

# 3. Assign role to user at datacenter level
pveum aclmod / -user terraform@pve -role TerraformProv

# 4. Create API token
pveum user token add terraform@pve mytoken --privsep=0
```

Copy the API token - you'll need it for the secrets configuration.

### Initial Setup 🏁

First time setup requires configuration:

```bash
# 1. Setup the ccr command
./scripts/clustercreator.sh setup-ccr

# 2. Configure variables (Proxmox details, networking, etc.)
ccr configure-variables

# 3. Configure secrets (VM passwords, API tokens)
ccr configure-secrets

# 4. Configure cluster definitions (or edit terraform/clusters.tf directly)
ccr configure-clusters
```

### Cluster Deployment 🎬

Once configured, deploying a cluster:

```bash
# 1. Create VM template (one-time per Proxmox cluster)
ccr template

# 2. Set cluster context
ccr ctx gamma

# 3. Initialize Terraform
ccr tofu init -upgrade

# 4. Deploy VMs
ccr tofu apply -auto-approve

# 5. Bootstrap Kubernetes
ccr bootstrap --enable-metrics

# 6. Initialize GitOps
./scripts/flux-bootstrap.sh
```

The bootstrap process:
- Installs Kubernetes on all nodes
- Configures external etcd cluster
- Sets up Cilium networking with kube-vip
- Installs Longhorn distributed storage
- Enables comprehensive metrics collection from etcd and control-plane components
- Installs the Nvidia GPU Operator  

The GitOps initialization:
- Bootstraps Flux v2 with GitHub integration
- Deploys all platform services (Istio, monitoring, etc.)
- Configures SOPS secret management
- Validates the complete stack deployment

## What Makes This Different 💫

**Infrastructure as Code** 📄: Every VM, every network interface, every storage volume is declared in Terraform. No clicking through web UIs.

**GitOps Native** 🔄: All configuration lives in Git. Changes are automatically reconciled. Rollbacks are `git revert`.

**Production Patterns** 🏢: External etcd, HA control plane, distributed storage, service mesh, comprehensive monitoring - the same patterns used by companies running Kubernetes at scale.

**GPU Ready** 🤖: Full PCIe GPU passthrough configured out of the box. Deploy AI workloads immediately.

**Zero Downtime Updates** ⚙️: Rolling updates for everything. Update Kubernetes versions, add nodes, change configurations - all without service interruption.

## Cluster Operations 🎮

Beyond deployment, the `ccr` script handles day-to-day operations:

```bash
# Scaling and node management
ccr add-nodes             # Add more worker nodes
ccr drain-node <node>     # Safely drain workloads from a node  
ccr delete-node <node>    # Remove node from cluster
ccr reset-node <node>     # Reset Kubernetes on specific node

# Upgrades and maintenance  
ccr upgrade-k8s           # Upgrade control plane API version
ccr upgrade-node <node>   # Upgrade specific node's Kubernetes version
ccr upgrade-addons        # Update CNI, storage, and other addons
ccr update-metrics        # Enable metrics on existing clusters

# Operations and debugging
ccr health-check          # Comprehensive cluster health validation
ccr run-command <cmd>     # Execute commands on cluster nodes
ccr vmctl                 # VM power management and backups
ccr fix-gpu-operator      # Fix GPU operator validation issues
```

All commands include validation, detailed logging, and rollback capabilities.

## Dependency Management 🔄

This repository uses [Renovate Bot](https://docs.renovatebot.com/) to automatically keep dependencies up-to-date:

- **Helm Charts**: Automatic updates for all 17 HelmRelease resources
- **Terraform Providers**: Proxmox and Unifi provider version tracking
- **Container Images**: Flux components and system images with digest pinning
- **GitHub Actions**: Workflow dependency updates

Renovate runs daily at 2am UTC and creates grouped pull requests for review. See [docs/RENOVATE.md](docs/RENOVATE.md) for complete setup and configuration details.

Application container images (Jellyfin, Radarr, Sonarr, n8n, etc.) are managed by Flux's built-in image automation.

## Credits 🙏

This homelab builds heavily on the excellent work from [ClusterCreator](https://github.com/christensenjairus/ClusterCreator). The Terraform infrastructure definitions and Ansible playbooks are based on (~okay, mostly stolen from~) that project, with lots of tweaks and modifications for my homelab setup.

---

*Zero-click Kubernetes. Made for learning, ended up with production-quality KaaS* 🎉
