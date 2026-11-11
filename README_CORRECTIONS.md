# Copie de travail corrigée

Lire d'abord `DIAGNOSTIC_ET_PLAN.md` : il décrit les corrections et les limites qui restent.

La copie ne contient volontairement ni secrets, ni état Terraform, ni cache `.terraform`, ni métadonnées `.git`.

Pour l'usage local, fournir les valeurs avec `TF_VAR_address`, `TF_VAR_username`, `TF_VAR_password` (et éventuellement `TF_VAR_skip_verify=true` seulement pour un certificat de laboratoire non approuvé). La topologie CML réelle doit encore être fournie sous `terraform/cml/topology.yaml`.
