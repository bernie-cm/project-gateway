# Network IDs consumed by the VM module to attach VMs to the correct zone network.
output "network_ids" {
  description = "Map of network name => libvirt network ID"
  value       = { for name, net in libvirt_network.zone : name => net.id }
}

output "network_names" {
  description = "Map of network name => libvirt network name"
  value       = { for name, net in libvirt_network.zone : name => net.name }
}
