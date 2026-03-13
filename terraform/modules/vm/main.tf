# =============================================================================
# VM Module - Libvirt Domain for Cross-Domain Gateway Nodes
# =============================================================================
#
# WHY: Each VM represents a single node in the cross-domain architecture.
# Using a reusable module ensures every node is built identically, which is
# critical for government audit -- you can prove that the high-side consumer
# was provisioned with the same hardened process as the low-side producer.
#
# The module uses cloud-init for first-boot configuration so that:
#   1. No manual SSH-in-and-configure steps exist (reproducibility).
#   2. The audit trail starts at VM creation, not after a human touches it.
#   3. Static IPs are baked in -- no DHCP means deterministic addressing.
# =============================================================================

terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "= 0.7.6"
    }
  }
}

# -----------------------------------------------------------------------------
# Base Volume -- the shared Rocky 9 cloud image
# -----------------------------------------------------------------------------
# WHY: We use a base volume so that multiple VMs can clone from the same
# image without duplicating gigabytes of data. This also guarantees that
# every node starts from the same OS baseline, which simplifies STIG
# compliance checks.
resource "libvirt_volume" "base" {
  name   = "${var.hostname}-base.qcow2"
  source = var.rocky9_image_path
  pool   = var.storage_pool
  format = "qcow2"
}

# -----------------------------------------------------------------------------
# Per-VM Volume -- a copy-on-write clone of the base image
# -----------------------------------------------------------------------------
# WHY: Each VM gets its own writable disk layer. Changes are isolated per
# node, so a compromised low-side VM cannot taint the base image used by
# the high-side VM.
resource "libvirt_volume" "disk" {
  name           = "${var.hostname}.qcow2"
  base_volume_id = libvirt_volume.base.id
  pool           = var.storage_pool
  size           = var.disk_size_bytes
  format         = "qcow2"
}

# -----------------------------------------------------------------------------
# Cloud-Init Disk -- first-boot configuration
# -----------------------------------------------------------------------------
# WHY: cloud-init sets hostname, user accounts, SSH keys, and static IP in
# a single deterministic pass. No manual intervention is needed, and the
# entire configuration is version-controlled in this repo.
resource "libvirt_cloudinit_disk" "init" {
  name = "${var.hostname}-cloudinit.iso"
  pool = var.storage_pool

  user_data = templatefile(var.cloud_init_template, {
    hostname       = var.hostname
    ssh_public_key = var.ssh_public_key
    ip_address     = var.ip_address
    gateway        = var.gateway
    dns_servers    = var.dns_servers
  })
}

# -----------------------------------------------------------------------------
# Libvirt Domain -- the actual VM
# -----------------------------------------------------------------------------
# WHY: This is the compute resource for the zone node. RAM and vCPU are
# parameterised so that the guard node (NiFi) can get more resources than
# the lightweight producer/consumer nodes.
resource "libvirt_domain" "vm" {
  name   = var.hostname
  memory = var.ram_mb
  vcpu   = var.vcpus
  # kvm = hardware-accelerated (bare metal). qemu = software emulation (nested VM / no VT-x).
  type   = var.domain_type

  # Attach the cloud-init ISO so it runs on first boot.
  cloudinit = libvirt_cloudinit_disk.init.id

  # Primary disk -- the CoW clone of the Rocky 9 base image.
  disk {
    volume_id = libvirt_volume.disk.id
  }

  # Network interface -- attach to the zone network passed in by the caller.
  # WHY: Each VM connects to exactly ONE zone network. Cross-zone traffic
  # is only possible through the guard node's firewall rules (configured
  # later with Ansible). This enforces the principle of least privilege at
  # the network layer.
  network_interface {
    network_id     = var.network_id
    hostname       = var.hostname
    wait_for_lease = false # No DHCP, so there will be no lease to wait for.
  }

  # Serial console for troubleshooting without a graphical display.
  # WHY: Government labs often run headless hypervisors; serial console
  # access is essential for debugging boot issues.
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  # Ensure the VM starts when the hypervisor boots.
  autostart = true
}
