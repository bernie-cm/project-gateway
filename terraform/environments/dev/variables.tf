variable "ssh_public_key" {
  description = "SSH public key content (not path) to inject into all VMs via cloud-init."
  type        = string
  # Set in terraform.tfvars (gitignored). Example:
  #   ssh_public_key = file("~/.ssh/id_ed25519.pub")
}

variable "rocky9_image_path" {
  description = "Absolute path to the Rocky Linux 9 GenericCloud qcow2 image on the hypervisor."
  type        = string
  # Download from: https://dl.rockylinux.org/pub/rocky/9/images/x86_64/
  # Place at: /var/lib/libvirt/images/Rocky-9-GenericCloud.latest.x86_64.qcow2
}
