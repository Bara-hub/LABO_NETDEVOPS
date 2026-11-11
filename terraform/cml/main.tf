
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    cml2 = {
      source = "CiscoDevNet/cml2"
    }
  }
}

# Déploiement du laboratoire CML2
resource "cml2_lifecycle" "lab" {
  topology = file("${path.module}/topology.yaml")
}

# Identifiant du laboratoire
output "lab_id" {
  value = cml2_lifecycle.lab.id
}
