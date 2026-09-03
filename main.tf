#  <RESOURCE TYPE>.<NAME>.<ATTRIBUTE>
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.27.2"
    }
    dns = {
      source  = "hashicorp/dns"
      version = "~> 3.0"
    }
    # cloudflare = {
    #   source  = "cloudflare/cloudflare"
    #   version = "4.38.0"
    # }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "dns" {
  update {
    server        = var.dns_server
    key_name      = var.dns_tsig_key_name
    key_algorithm = var.dns_tsig_algorithm
    key_secret    = var.dns_tsig_secret
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}

resource "hcloud_server" "interfacer" {
  name        = local.name_with_suffix
  image       = "debian-12"
  server_type = "cx33"
  ssh_keys    = [var.hetzner_ssh_key_name]

  # Must be kept in sync with each other (hcloud provider requirement).
  # delete_protection  = false
  # rebuild_protection = false
}

output "instance_public_ip" {
  description = "Public IP of Hetzner cloud instance"
  value       = hcloud_server.interfacer.ipv4_address
}

resource "dns_a_record_set" "interfacer" {
  zone      = "${var.domain}."
  name      = local.name_with_suffix
  addresses = [hcloud_server.interfacer.ipv4_address]
  ttl       = 300
}

resource "dns_a_record_set" "proxy_interfacer" {
  zone      = "${var.domain}."
  name      = "proxy.${local.name_with_suffix}"
  addresses = [hcloud_server.interfacer.ipv4_address]
  ttl       = 300
}

resource "dns_a_record_set" "zenflows_interfacer" {
  zone      = "${var.domain}."
  name      = "zenflows.${local.name_with_suffix}"
  addresses = [hcloud_server.interfacer.ipv4_address]
  ttl       = 300
}

resource "dns_a_record_set" "dpp_interfacer" {
  zone      = "${var.domain}."
  name      = "interfacer-dpp.${local.name_with_suffix}"
  addresses = [hcloud_server.interfacer.ipv4_address]
  ttl       = 300
}

resource "dns_a_record_set" "feedback_interfacer" {
  zone      = "${var.domain}."
  name      = "feedback.${local.name_with_suffix}"
  addresses = [hcloud_server.interfacer.ipv4_address]
  ttl       = 300
}

resource "null_resource" "wait_for_ping" {
  depends_on = [
    hcloud_server.interfacer,
    dns_a_record_set.interfacer,
  ]

  provisioner "local-exec" {
    command = "./ping_new.sh ${local.hostname}"
  }
}

locals {
  depends_on = null_resource.wait_for_ping
  # name + suffix -> "name-suffix"; only one of the two set -> that one alone
  name_with_suffix = var.name != "" && var.suffix != "" ? "${var.name}-${var.suffix}" : "${var.name}${var.suffix}"
  hostname         = "${local.name_with_suffix}.${var.domain}"
  known_hosts_file = "$HOME/.ssh/known_hosts"
}

output "instance_name" {
  description = "DNS name of Hetzner cloud instance"
  value       = local.hostname
}

# Generate the inventory/hosts.yml file
data "template_file" "ansible_inventory" {
  template = <<EOT
all:
  hosts:
    ${local.hostname}:
EOT
}

# Write the inventory file to the filesystem (per-workspace to avoid conflicts)
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/interfacer-devops-staging/inventory/hosts-${terraform.workspace}.yml"
  content  = data.template_file.ansible_inventory.rendered
}

resource "null_resource" "add_ssh_key_to_known_hosts" {
  depends_on = [null_resource.wait_for_ping]
  triggers = {
    hostname         = local.hostname
    ipv4_address     = hcloud_server.interfacer.ipv4_address
    known_hosts_file = local.known_hosts_file
  }

  provisioner "local-exec" {
    command = "ssh-keyscan -H ${self.triggers.hostname} ${self.triggers.ipv4_address} >> ${local.known_hosts_file}"
  }

  # Hetzner recycles public IPs: a stale key left behind for a reassigned
  # address breaks the next connection to it, so drop both entries.
  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
ssh-keygen -f ${self.triggers.known_hosts_file} -R ${self.triggers.hostname}
ssh-keygen -f ${self.triggers.known_hosts_file} -R ${self.triggers.ipv4_address}
EOT
  }
}

# Run Ansible after creating the instance
resource "null_resource" "run_ansible" {
  depends_on = [null_resource.wait_for_ping, null_resource.add_ssh_key_to_known_hosts]

  provisioner "local-exec" {
    command = <<EOT
ansible-playbook -i ${local_file.ansible_inventory.filename} \
--vault-password-file interfacer-devops-staging/.vault_pass \
-e domain_name=${local.hostname} \
-e gui_suffix=${var.suffix} \
-e enable_watchtower=${var.enable_watchtower} \
interfacer-devops-staging/install-proxy.yaml
EOT
  }
}

# Remove SSH key from known_hosts upon destroy
# resource "null_resource" "remove_ssh_keys" {
#   depends_on = [gandi_livedns_record.gpm_dyne_im]
#   triggers = {
#     keys_id = local.hostname
#   }

#   provisioner "local-exec" {
#     when    = destroy
#     command = <<EOT
# ssh-keygen -f ~/.ssh/known_hosts -R ${self.triggers["keys_id"]} > ~/.ssh/known_hosts.new && /
# mv ~/.ssh/known_hosts.new ~/.ssh/known_hosts
#     EOT
#   }
# }

# Create a record
# resource "cloudflare_record" "tofutwo" {
#   zone_id = "dyne.im"
#   name    = "tofutwo"
#   content = hcloud_server.interfacer.ipv4_address
#   type    = "A"
#   ttl     = 300
# }

# 2024-12-18.17:51:54 trkdz-d7-ceres antoniotrkdz /home/antoniotrkdz/dyne/devops  2016  ansible-playbook -u root -i hosts_test.yaml --vault-pass-file .vault_pass install-proxy.yaml --key-file ~/.ssh/id_rsa

