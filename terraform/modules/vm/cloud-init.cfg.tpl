#cloud-config
# =============================================================================
# Cloud-Init Template - First-Boot Configuration for Gateway Nodes
# =============================================================================
#
# WHY: In a government environment every host must be configured identically
# and reproducibly. cloud-init runs exactly once at first boot, sets the
# hostname, creates the admin user, injects SSH keys, and configures static
# networking. After this single pass the host is ready for Ansible hardening.
#
# DHCP is deliberately not used. Static IPs assigned here match what the
# firewall rules expect. If a host somehow got a different IP, traffic would
# be blocked -- fail-closed by design.
# =============================================================================

# Set the system hostname to match the Terraform-managed inventory.
hostname: ${hostname}
fqdn: ${hostname}.gateway.local
manage_etc_hosts: true

# Create a dedicated admin user instead of relying on root.
# WHY: Root login is disabled in hardened government systems. The
# gateway-admin user has sudo access for provisioning but all actions
# are logged under a named account for accountability.
users:
  - name: gateway-admin
    gecos: Gateway Administration Account
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ${ssh_public_key}

# Disable SSH password authentication -- keys only.
# WHY: Password-based SSH is explicitly prohibited by most government
# security baselines (e.g., DISA STIG). Key-based auth is stronger and
# auditable.
ssh_pwauth: false

# Configure static networking.
# WHY: Deterministic IPs are required so that firewall rules, audit logs,
# and monitoring dashboards all reference the same address. DHCP would
# introduce unpredictability that is unacceptable in a controlled environment.
write_files:
  - path: /etc/NetworkManager/system-connections/eth0.nmconnection
    permissions: '0600'
    content: |
      [connection]
      id=eth0
      type=ethernet
      interface-name=eth0
      autoconnect=true

      [ipv4]
      method=manual
      addresses=${ip_address}
%{ if gateway != "" ~}
      gateway=${gateway}
%{ endif ~}
%{ if dns_servers != "" ~}
      dns=${dns_servers}
%{ endif ~}

      [ipv6]
      method=disabled

# Apply the network configuration and restart NetworkManager.
runcmd:
  - nmcli connection reload
  - nmcli connection up eth0 || true

# Disable cloud-init after first boot.
# WHY: cloud-init should only run once. Leaving it active is a security
# risk -- an attacker who can inject a modified datasource could
# reconfigure the host. Disabling it reduces the attack surface.
  - touch /etc/cloud/cloud-init.disabled

# Ensure the system clock is accurate for audit log timestamps.
# WHY: In government systems, accurate timestamps are legally required
# for evidence integrity. NTP keeps all nodes synchronised.
ntp:
  enabled: true

# Harden SSH on first boot (Ansible will do a deeper pass later).
ssh_genkeytypes:
  - ed25519
  - rsa
