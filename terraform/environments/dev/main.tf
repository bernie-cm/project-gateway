# =============================================================================
# Dev environment - networks (Session 1) + VMs (Session 2)
# =============================================================================
#
# Four isolated networks, one per zone:
#   LOW   (10.10.0.0/24) — untrusted data sources
#   GUARD (10.20.0.0/24) — content inspection / cross-domain gateway
#   HIGH  (10.30.0.0/24) — trusted consumers
#   MGMT  (10.40.0.0/24) — management plane, NAT for internet access
#
# Traffic policy: LOW -> GUARD -> HIGH only.
# GUARD is the only node with interfaces on two networks.

module "networks" {
  source = "../../modules/network"

  networks = [
    {
      name        = "low-net"
      subnet      = "10.10.0.0/24"
      nat_enabled = false # No internet access — untrusted zone
    },
    {
      name        = "guard-net"
      subnet      = "10.20.0.0/24"
      nat_enabled = false # Isolated — all traffic via explicit firewall rules
    },
    {
      name        = "high-net"
      subnet      = "10.30.0.0/24"
      nat_enabled = false # Isolated — only accepts from GUARD
    },
    {
      name        = "mgmt-net"
      subnet      = "10.40.0.0/24"
      nat_enabled = true # NAT: management host needs yum/dnf for package installs
    },
  ]
}

# =============================================================================
# Session 2: Virtual Machines
# =============================================================================
#
# WHY: Each VM is declared in code using a shared module. This means:
#  - Every node is provisioned identically (same cloud-init, same base image)
#  - Rebuilding the environment is `terraform apply`, not tribal knowledge
#  - The audit trail for "who authorised this server?" is the git log
#
# RAM allocation follows the role:
#  - low-producer / high-consumer: 2 GB — lightweight producer/consumer daemons
#  - guard-nifi / mgmt-rancher: 4 GB — NiFi and Rancher are JVM-based; hungry
#
# The cloud_init_template path is relative to the *module*, not this file.

locals {
  cloud_init_tpl = "${path.module}/../../modules/vm/cloud-init.cfg.tpl"
  # Use "qemu" on machines without hardware virtualisation (nested VMs, no VT-x).
  # Change to "kvm" on bare-metal hosts for hardware acceleration.
  domain_type    = "qemu"
}

module "low_producer" {
  source = "../../modules/vm"

  hostname            = "low-producer"
  zone                = "low"
  network_id          = module.networks.network_ids["low-net"]
  ram_mb              = 2048
  vcpus               = 2
  ip_address          = "10.10.0.10/24"
  gateway             = "" # No gateway — isolated network
  dns_servers         = "" # No DNS — isolated network
  rocky9_image_path   = var.rocky9_image_path
  ssh_public_key      = var.ssh_public_key
  cloud_init_template = local.cloud_init_tpl
  domain_type         = local.domain_type
}

module "guard_nifi" {
  source = "../../modules/vm"

  hostname            = "guard-nifi"
  zone                = "guard"
  network_id          = module.networks.network_ids["guard-net"]
  ram_mb              = 4096 # NiFi + ZooKeeper need more headroom
  vcpus               = 2
  ip_address          = "10.20.0.10/24"
  gateway             = "" # No gateway — traffic governed by firewall rules only
  dns_servers         = ""
  rocky9_image_path   = var.rocky9_image_path
  ssh_public_key      = var.ssh_public_key
  cloud_init_template = local.cloud_init_tpl
  domain_type         = local.domain_type
}

module "high_consumer" {
  source = "../../modules/vm"

  hostname            = "high-consumer"
  zone                = "high"
  network_id          = module.networks.network_ids["high-net"]
  ram_mb              = 2048
  vcpus               = 2
  ip_address          = "10.30.0.10/24"
  gateway             = ""
  dns_servers         = ""
  rocky9_image_path   = var.rocky9_image_path
  ssh_public_key      = var.ssh_public_key
  cloud_init_template = local.cloud_init_tpl
  domain_type         = local.domain_type
}

module "mgmt_rancher" {
  source = "../../modules/vm"

  hostname            = "mgmt-rancher"
  zone                = "mgmt"
  network_id          = module.networks.network_ids["mgmt-net"]
  ram_mb              = 4096 # Rancher UI + monitoring stack
  vcpus               = 2
  ip_address          = "10.40.0.10/24"
  gateway             = "10.40.0.1" # NAT gateway for internet access
  dns_servers         = "1.1.1.1 8.8.8.8"
  rocky9_image_path   = var.rocky9_image_path
  ssh_public_key      = var.ssh_public_key
  cloud_init_template = local.cloud_init_tpl
  domain_type         = local.domain_type
}
