#  <RESOURCE TYPE>.<NAME>.<ATTRIBUTE>
terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.27.2"
    }
    gandi = {
      source  = "go-gandi/gandi"
      version = "~> 2.0"
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

provider "gandi" {
  personal_access_token = var.gandi_token
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}

resource "hcloud_server" "interfacer" {
  name        = var.name
  image       = "debian-12"
  server_type = "cx22"
  ssh_keys    = [var.hetzner_ssh_key_name]
}

output "instance_public_ip" {
  description = "Public IP of Hetzner cloud instance"
  value       = hcloud_server.interfacer.ipv4_address
}

resource "gandi_livedns_record" "interfacer" {
  zone       = var.domain
  name       = var.name
  type       = "A"
  ttl        = 300
  values     = [hcloud_server.interfacer.ipv4_address]
  depends_on = [hcloud_server.interfacer]
}

resource "gandi_livedns_record" "proxy_interfacer" {
  zone       = var.domain
  name       = "proxy.${gandi_livedns_record.interfacer.name}"
  type       = "A"
  ttl        = 300
  values     = [hcloud_server.interfacer.ipv4_address]
  depends_on = [hcloud_server.interfacer]
}

resource "gandi_livedns_record" "zenflows_interfacer" {
  zone       = var.domain
  name       = "zenflows.${gandi_livedns_record.interfacer.name}"
  type       = "A"
  ttl        = 300
  values     = [hcloud_server.interfacer.ipv4_address]
  depends_on = [hcloud_server.interfacer]
}

resource "gandi_livedns_record" "dpp_interfacer" {
  zone       = var.domain
  name       = "interfacer-dpp.${gandi_livedns_record.interfacer.name}"
  type       = "A"
  ttl        = 300
  values     = [hcloud_server.interfacer.ipv4_address]
  depends_on = [hcloud_server.interfacer]
}

resource "null_resource" "wait_for_ping" {
  depends_on = [hcloud_server.interfacer]

  provisioner "local-exec" {
    command = "./ping_new.sh ${local.hostname}"
  }
}

locals {
  depends_on       = null_resource.wait_for_ping
  hostname         = "${gandi_livedns_record.interfacer.name}.${gandi_livedns_record.interfacer.zone}"
  known_hosts_file = "~/.ssh/known_hosts"
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

# Write the inventory file to the filesystem
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/interfacer-devops-staging/inventory/hosts.yml"
  content  = data.template_file.ansible_inventory.rendered
}

resource "null_resource" "add_ssh_key_to_known_hosts" {
  depends_on = [null_resource.wait_for_ping]
  triggers = {
    hostname         = local.hostname
    known_hosts_file = local.known_hosts_file
  }

  provisioner "local-exec" {
    command = "ssh-keyscan -H ${self.triggers.hostname} >> ${local.known_hosts_file}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "ssh-keygen -f ${self.triggers.known_hosts_file} -R ${self.triggers.hostname}"
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

