# Set the variable value in *.tfvars file
# or using the -var="hcloud_token=..." CLI option
variable "hcloud_token" {
  sensitive = true
}

variable "gandi_token" {
  sensitive = true
}

variable "cloudflare_token" {
  sensitive = true
}

variable "domain" {
  description = "Main domain name"
  type        = string
  # default     = "dyne.im"
}

variable "name" {
  description = "Third level domain name"
  type        = string
}

variable "suffix" {
  description = "Optional suffix for instance name and GUI service (e.g., 'tchibo')"
  type        = string
}

variable "hetzner_ssh_key_name" {}