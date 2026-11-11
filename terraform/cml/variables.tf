variable "cml_address" {
  description = "URL HTTPS du contrôleur CML2"
  type        = string
}

variable "cml_username" {
  description = "Compte CML2 utilisé par Terraform"
  type        = string
}

variable "cml_password" {
  description = "Mot de passe CML2"
  type        = string
  sensitive   = true
}

variable "skip_verify" {
  description = "Désactive la vérification TLS uniquement pour le laboratoire"
  type        = bool
  default     = true
}