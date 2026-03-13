# =============================================================================
# VM Module Variables
# =============================================================================

variable "hostname" {
  description = "VM hostname. Used as the libvirt domain name and set inside the guest via cloud-init."
  type        = string
}

variable "zone" {
  description = "Security zone this VM belongs to (e.g., low, guard, high, mgmt). Used for tagging and documentation only."
  type        = string
}

variable "network_id" {
  description = "Libvirt network ID to attach this VM to. Obtained from the network module output."
  type        = string
}

variable "ram_mb" {
  description = "Amount of RAM in megabytes. Guard/mgmt nodes need more (4096) than producer/consumer nodes (2048)."
  type        = number
  default     = 2048
}

variable "vcpus" {
  description = "Number of virtual CPUs."
  type        = number
  default     = 2
}

variable "disk_size_bytes" {
  description = "Size of the VM disk in bytes. Defaults to 20 GB."
  type        = number
  default     = 21474836480 # 20 GiB
}

variable "storage_pool" {
  description = "Libvirt storage pool for volumes. Defaults to the system 'default' pool."
  type        = string
  default     = "default"
}

variable "rocky9_image_path" {
  description = "Absolute path to the Rocky 9 cloud image (qcow2) on the hypervisor."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key content to inject into the VM for the gateway-admin user."
  type        = string
}

variable "ip_address" {
  description = "Static IP address for this VM in CIDR notation (e.g., 10.10.0.10/24)."
  type        = string
}

variable "gateway" {
  description = "Default gateway IP. Only relevant for mgmt-net VMs that need internet access; set to empty string for isolated zones."
  type        = string
  default     = ""
}

variable "dns_servers" {
  description = "Space-separated list of DNS server IPs. Only relevant for mgmt-net VMs."
  type        = string
  default     = ""
}

variable "cloud_init_template" {
  description = "Path to the cloud-init template file."
  type        = string
}

variable "domain_type" {
  description = "Libvirt domain type. Use 'kvm' on bare metal (hardware acceleration). Use 'qemu' on VMs or machines without KVM support (slower, no hardware virt required)."
  type        = string
  default     = "kvm"

  validation {
    condition     = contains(["kvm", "qemu"], var.domain_type)
    error_message = "domain_type must be 'kvm' (bare metal) or 'qemu' (no hardware virt)."
  }
}
