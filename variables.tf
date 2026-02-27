# Set the variable value in *.tfvars file
# or using the -var="hcloud_token=..." CLI option
variable "hcloud_token" {
  sensitive = true
}

variable "cloudflare_token" {
  sensitive = true
}

variable "dns_server" {
  description = "DNS server address for dynamic updates"
  type        = string
}

variable "dns_tsig_key_name" {
  description = "TSIG key name"
  type        = string
}

variable "dns_tsig_algorithm" {
  description = "TSIG key algorithm (e.g., hmac-sha256)"
  type        = string
  default     = "hmac-sha256"
}

variable "dns_tsig_secret" {
  description = "TSIG key secret (base64 encoded)"
  type        = string
  sensitive   = true
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