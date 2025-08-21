locals {
  all_nodes = flatten([
    for cluster_name, cluster in var.clusters : [
      for node_class, specs in cluster.node_classes : [
        for i in range(specs.count) : {
          cluster_name = cluster.cluster_name
          cluster_id   = cluster.cluster_id
          node_class   = node_class
          index        = i
          vm_id        = tonumber("${cluster.cluster_id}${specs.start_ip + i}")
          on_boot      = cluster.start_on_proxmox_boot
          use_pve_ha   = cluster.use_pve_ha
          cores        = specs.cores
          sockets      = specs.sockets
          memory       = specs.memory
          disks        = specs.disks
          devices      = specs.devices
          pve_nodes    = specs.pve_nodes
          machine      = specs.machine
          cpu_type     = specs.cpu_type
          bridge       = cluster.networking.bridge
          use_unifi    = cluster.networking.use_unifi
          vlan_id      = cluster.networking.assign_vlan ? (cluster.networking.vlan_id == null ? "${cluster.cluster_id}00" : cluster.networking.vlan_id) : null
          ipv4 : {
            vm_ip    = "${cluster.networking.ipv4.subnet_prefix}.${specs.start_ip + i}"
            gateway  = cluster.networking.ipv4.gateway
            dns1     = cluster.networking.ipv4.dns1
            dns2     = cluster.networking.ipv4.dns2
            lb_cidrs = cluster.networking.ipv4.lb_cidrs
          }
          ipv6 : {
            enabled    = cluster.networking.ipv6.enabled
            dual_stack = cluster.networking.ipv6.enabled ? cluster.networking.ipv6.dual_stack : false
            vm_ip      = cluster.networking.ipv6.enabled ? "${cluster.networking.ipv6.subnet_prefix}::${specs.start_ip + i}" : null
            gateway    = cluster.networking.ipv6.enabled ? cluster.networking.ipv6.gateway : null
            dns1       = cluster.networking.ipv6.enabled ? cluster.networking.ipv6.dns1 : null
            dns2       = cluster.networking.ipv6.enabled ? cluster.networking.ipv6.dns2 : null
            lb_cidrs   = cluster.networking.ipv6.enabled ? cluster.networking.ipv6.lb_cidrs : null
          }
          dns_search_domain = cluster.networking.dns_search_domain
          labels            = specs.labels
          taints            = specs.taints
          # Disk metadata for Longhorn configuration
          has_secondary_disks = length(specs.disks) > 1
          secondary_disks = length(specs.disks) > 1 ? [for idx, disk in slice(specs.disks, 1, length(specs.disks)) : {
            device_path = "/dev/vd${substr("bcdefghijklmnopqrstuvwxyz", idx, 1)}"
            datastore   = disk.datastore
            size_gb     = disk.size
            mount_path  = "/var/lib/longhorn-disk-${idx}"
          }] : []
        }
      ]
    ]
  ])

  cluster_config = var.clusters[terraform.workspace]

  management_cidrs_ipv4_list = split(",", local.cluster_config.networking.ipv4.management_cidrs)
  management_cidrs_ipv6_list = split(",", local.cluster_config.networking.ipv6.management_cidrs)

  # Now filter all_nodes to only include those from the specified cluster
  nodes = [for node in local.all_nodes : node if node.cluster_name == terraform.workspace]

  # Generate list of nodes with secondary disks for Longhorn
  nodes_with_secondary_disks = [for node in local.nodes : node if node.has_secondary_disks]
}

# Local file resource to write the clusters config to a JSON file
resource "local_file" "cluster_config_json" {
  content  = jsonencode(local.cluster_config)
  filename = "../ansible/tmp/${local.cluster_config.cluster_name}/cluster_config.json"
}

# Local file resource to write nodes with secondary disks metadata for Ansible
resource "local_file" "longhorn_nodes_json" {
  content = jsonencode({
    nodes_with_secondary_disks = local.nodes_with_secondary_disks
  })
  filename = "../ansible/tmp/${local.cluster_config.cluster_name}/longhorn_nodes.json"
}
