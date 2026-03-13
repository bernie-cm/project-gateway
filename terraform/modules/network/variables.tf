variable "networks" {
  description = "List of networks to create. Each represents one classification zone boundary."
  type = list(object({
    name        = string # e.g. "low-net", "guard-net", "high-net", "mgmt-net"
    subnet      = string # CIDR block e.g. "10.10.0.0/24"
    nat_enabled = bool   # Only mgmt-net should be true
  }))

  validation {
    condition     = length(var.networks) > 0
    error_message = "At least one network must be defined."
  }

  validation {
    # Enforce the design constraint: only ONE network (mgmt) gets internet access.
    # If this fires, someone is trying to give a classification zone internet access.
    condition     = length([for n in var.networks : n if n.nat_enabled]) <= 1
    error_message = "Only mgmt-net should have NAT. Classification zones must be air-gapped."
  }
}
