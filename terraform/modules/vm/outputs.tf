# =============================================================================
# VM Module Outputs
# =============================================================================

output "vm_id" {
  description = "Libvirt domain ID of the created VM. Useful for dependency ordering and audit references."
  value       = libvirt_domain.vm.id
}

output "hostname" {
  description = "Hostname of the VM, matching the domain name."
  value       = libvirt_domain.vm.name
}

output "ip_address" {
  description = "Static IP address assigned to this VM via cloud-init."
  value       = var.ip_address
}
