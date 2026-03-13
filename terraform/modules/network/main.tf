# =============================================================================
# Network Module - Isolated libvirt networks per classification zone
# =============================================================================
#
# WHY: Each zone (LOW, GUARD, HIGH) gets its own isolated network.
# GUARD is the only permitted crossing point. If LOW can reach HIGH
# directly, the cross-domain solution is bypassed — data spill + incident.
#
# NIST 800-53 SC-7:  Boundary Protection
# NIST 800-53 AC-4:  Information Flow Enforcement
#
# DHCP is disabled on all networks — IPs assigned statically via cloud-init
# so every address is declared in code and auditable without SSH access.

terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "= 0.7.6"
    }
  }
}

resource "libvirt_network" "zone" {
  for_each = { for net in var.networks : net.name => net }

  name   = each.value.name
  # "none" = completely isolated (no routing out). "nat" = can reach internet.
  # Only mgmt-net gets NAT for package installs. All classification zones: "none".
  mode   = each.value.nat_enabled ? "nat" : "none"
  domain = "${each.value.name}.gateway.local"

  addresses = [each.value.subnet]

  # DHCP off — static IPs via cloud-init
  dhcp { enabled = false }

  # DNS only on mgmt-net — isolated zones must not have resolvable DNS
  # (DNS over UDP is a known exfiltration channel)
  dns { enabled = each.value.nat_enabled }

  autostart = true
}
