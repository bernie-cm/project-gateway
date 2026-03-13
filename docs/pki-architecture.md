# PKI Architecture — Project GATEWAY

## Why PKI?

In a cross-domain solution, trust must be cryptographic. Without PKI:
- A compromised LOW node could *claim* to be GUARD and intercept data
- There is no way to prove a connection is going to the intended recipient
- "Is this really the HIGH consumer?" has no answer

With PKI, every node proves its identity with a certificate signed by a trusted CA.
A LOW node presenting a GUARD certificate is rejected — the signature chain fails.

**NIST 800-53 controls addressed:**
| Control | Requirement | How PKI satisfies it |
|---------|-------------|---------------------|
| SC-8 | Transmission confidentiality | TLS using node certificates |
| SC-12 | Cryptographic key management | CA hierarchy, offline root, lifecycle documented |
| SC-13 | Cryptographic protection | RSA 4096 / SHA-384, FIPS-compatible algorithms |
| IA-3 | Device identification | Each node has a unique certificate with its hostname in the Subject CN |

---

## CA Hierarchy

```
GATEWAY Root CA  (RSA 4096, SHA-384, 10yr)
  [self-signed, offline in LUKS store]
       |
       +---> LOW-CA   (RSA 4096, SHA-256, 5yr, pathlen:0)
       |       |
       |       +---> low-producer (server cert, 1yr)
       |       +---> low-producer-client (client cert for NiFi S2S, 1yr)
       |
       +---> GUARD-CA (RSA 4096, SHA-256, 5yr, pathlen:0)
       |       |
       |       +---> guard-nifi (server cert, 1yr)
       |       +---> guard-nifi-client (client cert for NiFi S2S, 1yr)
       |
       +---> HIGH-CA  (RSA 4096, SHA-256, 5yr, pathlen:0)
               |
               +---> high-consumer (server cert, 1yr)
               +---> high-consumer-client (client cert, 1yr)
```

### Why two tiers?

**Single-tier (all certs from one CA):** Simple, but if that CA's key is compromised
every certificate in the system is untrusted. Total rebuild.

**Two-tier (Root + zone Intermediates):** Root CA signs only intermediate CAs, then
goes offline. A compromised zone CA (e.g., LOW-CA) affects only that zone. You
revoke the intermediate, reissue zone certs, and the other zones are unaffected.

**pathlen:0** on intermediates: An intermediate CA with pathlen:0 cannot sign other
CAs — it can only sign end-entity certificates. This prevents a compromised
intermediate from creating a rogue sub-CA.

---

## Key Storage Strategy

| Key | Where | Why |
|-----|-------|-----|
| Root CA private key | LUKS-encrypted loopback file (`pki/root-ca-store.luks`) | Simulates HSM/offline CA. Only accessible with passphrase + explicit mount. |
| Intermediate CA keys | `pki/{LOW,GUARD,HIGH}-ca/private/` (400 permissions) | Needed for signing node certs. Accessible to operators but restricted. |
| Node keys | `pki/certs/{hostname}/` (400 permissions) | Deployed to nodes via Ansible. Encrypted at rest by LUKS (Session 11). |

**Production difference:** The Root CA key would live in a FIPS 140-2 Level 3 HSM
(e.g., Thales Luna, AWS CloudHSM). The LUKS loopback simulates the key-lifecycle
workflow without the hardware cost.

---

## Certificate Lifecycle

```
Generate key + CSR  -->  Sign with zone CA  -->  Deploy via Ansible
      |                                                   |
      |                                           Monitor expiry
      |                                           (Grafana dashboard, S15)
      |
  On expiry or compromise:
      Revoke cert  -->  Update CRL  -->  Redeploy  -->  Restart service
      (Session 10: cert rotation playbook automates this)
```

### Validity periods

| Cert type | Validity | Rationale |
|-----------|----------|-----------|
| Root CA | 10 years | Rarely rotated; offline storage reduces risk |
| Intermediate CAs | 5 years | Matches typical government system lifecycle |
| Node / service certs | 1 year | Short window limits exposure if key is compromised |

---

## Trust Distribution

All nodes receive `ca-chain.pem` (Intermediate + Root concatenated).
Ansible's `roles/pki` deploys this to `/etc/pki/ca-trust/source/anchors/`
and runs `update-ca-trust` so system tools (curl, openssl, Java) all
trust the chain without manual configuration.

---

## Files

| File | Purpose |
|------|---------|
| `scripts/pki/create-root-ca.sh` | One-time Root CA creation |
| `scripts/pki/create-intermediate-ca.sh` | Zone CA creation (run once per zone) |
| `scripts/pki/create-luks-store.sh` | LUKS encrypted store for root key |
| `scripts/pki/sign-cert.sh` | Sign a node or client cert |
| `scripts/pki/revoke-cert.sh` | Revoke a cert and update CRL |
| `scripts/pki/test-pki.sh` | CI validation of all cert chains |
| `pki/root-ca-store.luks` | Encrypted root CA key (gitignored) |
| `pki/ca-chain.pem` | Trust bundle deployed to all nodes (gitignored — contains no secrets but is environment-specific) |
