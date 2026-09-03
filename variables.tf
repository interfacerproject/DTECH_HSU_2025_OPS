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
  description = "Third level domain name. May be empty when suffix is set, giving suffix.domain"
  type        = string
  default     = ""
}

variable "suffix" {
  description = "Optional suffix for instance name and GUI service (e.g., 'tchibo')"
  type        = string
  default     = ""

  validation {
    condition     = var.name != "" || var.suffix != ""
    error_message = "At least one of name or suffix must be set: the host name is name-suffix, or whichever of the two is set."
  }
}

variable "hetzner_ssh_key_name" {}

variable "enable_watchtower" {
  description = "Deploy Watchtower to auto-update containers when image changes"
  type        = bool
  default     = false
}