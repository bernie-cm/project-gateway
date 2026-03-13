# =============================================================================
# Provider configuration for the dev environment
# =============================================================================
#
# libvirt connects to the local hypervisor over a Unix socket.
# "qemu:///system" means system-level libvirt (requires libvirtd running).
# No remote state backend yet — added in Phase 3 (Session 15).

terraform {
  required_version = ">= 1.6"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "= 0.7.6"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}
