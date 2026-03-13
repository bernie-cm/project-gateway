output "network_ids" {
  description = "libvirt network IDs per zone"
  value       = module.networks.network_ids
}

output "network_names" {
  description = "libvirt network names per zone"
  value       = module.networks.network_names
}

output "vm_ips" {
  description = "Static IP addresses of all VMs — these match firewall rules and Ansible inventory."
  value = {
    low_producer  = module.low_producer.ip_address
    guard_nifi    = module.guard_nifi.ip_address
    high_consumer = module.high_consumer.ip_address
    mgmt_rancher  = module.mgmt_rancher.ip_address
  }
}
