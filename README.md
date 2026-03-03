# Interfacer Staging


## Prerequisites
1. Install Open Tofu
2. install ansible
3. Open an account on Hetzner provider (or any other provider of cloud)
4. Supply an (public) ssh key to a new hetzner cloud project
5. Create an API token on the dashboard (Read & Write)
6. Create a gandi account for DNS (or cloudflare or namecheap)
7. Generate a GANDI PAT (personal access token)
8. Create terraform.tfvars `hcloud_token = "{value}"`
9. Append terraform.tfvars `gandi_token = "{value}"`
10. Append terraform.tfvars `hetzner_ssh_key_name = "{value}"`
11. Append terraform.tfvars `private_ssh_key_path = "{value}"`

---

# Deployment Guide

## Overview

This repository automates the full provisioning and configuration of the Interfacer platform stack. OpenTofu creates a Hetzner Cloud server and registers DNS records, then automatically invokes Ansible to configure the server. Ansible installs Docker and deploys seven services via Docker Compose: **zenflows** (backend API + PostgreSQL), **dpp** (Digital Product Passport + MongoDB + MinIO), **proxy** (API gateway), **gui** (frontend), **ifacerlosh**, and **ingress** (Caddy reverse proxy with automatic HTTPS). Multiple independent environments (e.g. production, per-client deployments) are managed through Terraform workspaces — each workspace has its own isolated state and server.

Two DNS backends are supported and are mutually exclusive — choose one before deploying:

| Option | Provider | Best for |
|---|---|---|
| **A** | `hashicorp/dns` — RFC 2136 / TSIG | Self-hosted nameserver with dynamic update support |
| **B** | `go-gandi/gandi` — Gandi LiveDNS | Domains registered and managed through Gandi |

---

## 1. Prerequisites

Install these tools locally before starting:

```bash
# OpenTofu (Terraform-compatible)
# https://opentofu.org/docs/intro/install/

# Ansible
pip install ansible
ansible-galaxy collection install community.docker

# netcat (for the SSH readiness check)
apt install netcat-openbsd   # Debian/Ubuntu
```

Your local machine also needs:
- An SSH key pair registered with Hetzner Cloud
- Network access to the DNS server (for TSIG updates)

---

## 2. Hetzner Cloud Setup

1. Create an account at [console.hetzner.cloud](https://console.hetzner.cloud)
2. Go to **Security → SSH Keys** and upload your public key — note the key name exactly
3. Go to **Security → API Tokens** and create a token with **Read & Write** permissions

[This guide](https://justobjects.nl/terraform-first-steps/) is a nice starter and focuses on Hetzener cloud

---

## 3. DNS Setup

Choose one of the two supported DNS backends.

### Option A — RFC 2136 / TSIG (self-hosted nameserver)

You need the IP address of your nameserver and a TSIG key with write permission on the target zone.

Generate a TSIG key if you don't have one:

```bash
tsig-keygen -a hmac-sha256 mykey
```

This outputs:

```
key "mykey" {
    algorithm hmac-sha256;
    secret "base64encodedstring==";
};
```

Test that the key works before running Tofu:

```bash
nsupdate -k /path/to/key.conf <<EOF
server YOUR_DNS_SERVER_IP
zone YOUR_DOMAIN.
update add test.YOUR_DOMAIN. 300 A 1.2.3.4
send
EOF
```

This setup is available on the `self-hosted-dns` branch of this repo.

---

### Option B — Gandi LiveDNS

Use this if your domain is registered with and delegated to Gandi.

**1. Create a Gandi Personal Access Token:**
- Go to [account.gandi.net](https://account.gandi.net) → **Security** → **Personal Access Tokens**
- Create a token with the **"Manage domain name technical configurations"** permission enabled
- The token must belong to the account that owns the domain

**2. Test your token:**

```bash
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://api.gandi.net/v5/livedns/domains/YOUR_DOMAIN
```

A successful response returns domain metadata. A `403 Forbidden` means the token lacks permissions or belongs to a different account.

**3. Check the provider in [main.tf](main.tf):**

This are the relevant section to check:

```hcl
# In terraform { required_providers { ... } }
gandi = {
  source  = "go-gandi/gandi"
  version = "~> 2.0"
}

# Provider block
provider "gandi" {
  key = var.gandi_token
}
```

**4. Add `gandi_token` to [variables.tf](variables.tf):**

```hcl
variable "gandi_token" {
  sensitive = true
}
```

Remove the `dns_server`, `dns_tsig_key_name`, `dns_tsig_algorithm`, and `dns_tsig_secret` variables.

After making these changes run `tofu init -upgrade` to download the Gandi provider.

---

## 4. Configure `terraform.tfvars`

Edit [terraform.tfvars](terraform.tfvars) with your credentials. Use the block that matches your chosen DNS backend.

**Common (both options):**

```hcl
hcloud_token         = "YOUR_HETZNER_API_TOKEN"
hetzner_ssh_key_name = "your-key-name"   # must match name in Hetzner console

# Cloudflare (unused but required by provider block)
cloudflare_token = "placeholder"
```

**Option A — RFC 2136 / TSIG:**

```hcl
dns_server         = "YOUR_DNS_SERVER_IP"
dns_tsig_key_name  = "mykey."            # trailing dot required
dns_tsig_algorithm = "hmac-sha256"
dns_tsig_secret    = "base64encodedstring=="
```

**Option B — Gandi:**

```hcl
gandi_token = "YOUR_GANDI_PERSONAL_ACCESS_TOKEN"
```

---

## 5. Configure Ansible Vault Secrets

Each role's sensitive variables are stored in Ansible Vault. Create a vault password file:

```bash
echo "your-vault-password" > interfacer-devops-staging/.vault_pass
chmod 600 interfacer-devops-staging/.vault_pass
```

Inspect or edit any role's secrets:

```bash
ansible-vault edit interfacer-devops-staging/roles/dpp/vars/main.yaml \
  --vault-password-file interfacer-devops-staging/.vault_pass
```

The vaulted files contain per-service credentials (database passwords, API keys, etc.). The shared plain-text inventory variables live in [interfacer-devops-staging/inventory/group_vars/all/all.yml](interfacer-devops-staging/inventory/group_vars/all/all.yml). The `admin_key` and `room_salt` fields in that file are auto-generated by the playbook on first run.

---

## 6. Initialize OpenTofu

```bash
tofu init
```

This downloads the required providers:
- `hetznercloud/hcloud` — server provisioning
- `hashicorp/dns` — RFC 2136 DNS updates
- `hashicorp/local` / `null` / `template` — inventory and provisioner helpers

---

## 7. Deploy: Default Environment

The `default` workspace is used for your primary deployment.

```bash
# Verify the plan first
tofu plan -var="name=dpp-staging" -var="domain=example.com" -var="suffix="

# Deploy
tofu apply -var="name=dpp-staging" -var="domain=example.com" -var="suffix="
```

Tofu will:
1. Create a Hetzner `cx33` Debian 12 server named `dpp-staging`
2. Create DNS A records for `dpp-staging.example.com` and its subdomains (`proxy.*`, `zenflows.*`, `interfacer-dpp.*`)
3. Wait for SSH port 22 to be ready (`ping_new.sh`)
4. Add the host key to `~/.ssh/known_hosts`
5. Write `interfacer-devops-staging/inventory/hosts-default.yml`
6. Run the full Ansible playbook

After completion, the following URLs will be live (once Caddy obtains TLS certificates):

| Service | URL |
|---|---|
| GUI | `https://dpp-staging.example.com` |
| Proxy / API gateway | `https://proxy.dpp-staging.example.com` |
| Zenflows backend | `https://zenflows.dpp-staging.example.com` |
| DPP | `https://interfacer-dpp.dpp-staging.example.com` |

---

## 8. Deploy: Additional Environments (Workspaces)

Each additional environment runs as a completely independent Tofu workspace with its own server and DNS records.

```bash
# Create and switch to a new workspace
tofu workspace new tchibo

# Deploy — the suffix is appended to the server name and GUI image tag/name
tofu apply -var="name=dpp-staging" -var="domain=dnstest.example.org" -var="suffix=tchibo"
```

This creates `dpp-staging-tchibo.dnstest.example.org` and uses the Docker image `ghcr.io/interfacerproject/interfacer-gui-tchibo:tchibo`.

**Manage workspaces:**

```bash
tofu workspace list            # show all workspaces
tofu workspace select default  # switch back to production
tofu workspace select tchibo   # switch to tchibo environment
```

Per-workspace inventory files are written to:
- `interfacer-devops-staging/inventory/hosts-default.yml`
- `interfacer-devops-staging/inventory/hosts-tchibo.yml`

---

## 9. Re-running Ansible (Without Reprovisioning)

If you need to reconfigure services without recreating the server, run Ansible directly using the workspace inventory file.

**Full re-run:**

```bash
ansible-playbook \
  -i interfacer-devops-staging/inventory/hosts-tchibo.yml \
  --vault-password-file interfacer-devops-staging/.vault_pass \
  -e domain_name=dpp-staging-tchibo.dnstest.example.org \
  -e gui_suffix=tchibo \
  interfacer-devops-staging/install-proxy.yaml
```

**Partial re-run using tags** (roles run in this order):

| Tag | Role | What it does |
|---|---|---|
| `docker` | docker | Installs Docker CE |
| `zenflows` | zenflows | PostgreSQL + Zenflows backend |
| `dpp` | dpp | MongoDB + MinIO + interfacer-dpp |
| `proxy` | proxy | API gateway + inbox + wallet |
| `gui` | gui | Frontend container |
| `ifacerlosh` | ifacerlosh | Ifacerlosh service |
| `ingress` | ingress | Caddy config + TLS |

```bash
# Only re-deploy GUI and regenerate Caddy config
ansible-playbook ... --tags "gui,ingress"

# Skip the already-working lower services, run from gui onwards
ansible-playbook ... --skip-tags "docker,zenflows,dpp,proxy"
```

---

## 10. Destroy an Environment

```bash
# Destroy the tchibo environment
tofu workspace select tchibo
tofu destroy -var="name=dpp-staging" -var="domain=dnstest.example.org" -var="suffix=tchibo"

# Destroy the default environment
tofu workspace select default
tofu destroy -var="name=dpp-staging" -var="domain=example.com" -var="suffix="
```

This removes the Hetzner server and all DNS records for that workspace. Other workspaces are unaffected.

---

## Troubleshooting

**SSH connection timeout in Ansible**
The server booted and port 22 is accepting TCP connections, but `sshd` isn't fully ready. Re-run the playbook directly — it will succeed on the next attempt:

```bash
ansible-playbook -i interfacer-devops-staging/inventory/hosts-WORKSPACE.yml \
  --vault-password-file interfacer-devops-staging/.vault_pass \
  -e domain_name=HOSTNAME -e gui_suffix=SUFFIX \
  interfacer-devops-staging/install-proxy.yaml
```

**DNS state incompatible with provider version**
Remove stale DNS records from state and reapply:

```bash
tofu state rm dns_a_record_set.interfacer
tofu state rm dns_a_record_set.proxy_interfacer
tofu state rm dns_a_record_set.zenflows_interfacer
tofu state rm dns_a_record_set.dpp_interfacer
tofu apply ...
```

**Caddy SSL error (`ERR_SSL_PROTOCOL_ERROR`)**
Caddy is running but hasn't obtained a certificate yet, or the Caddyfile has the wrong domain. Check that ports 80 and 443 are reachable from the internet, then re-run just the ingress role:

```bash
ansible-playbook ... --tags ingress -e domain_name=CORRECT_HOSTNAME
```

**Wrong domain in Caddyfile**
This happens when two workspaces share the same inventory file. This repo uses per-workspace inventory files (`hosts-WORKSPACE.yml`) to prevent this. If you hit it anyway, re-run Ansible with the correct `domain_name` and `--tags ingress`.
