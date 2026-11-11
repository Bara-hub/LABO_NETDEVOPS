#!/usr/bin/env bash
set -uo pipefail
rc=0

ansible-playbook ansible/site.yml --limit ios --check --diff | tee drift_ansible.txt
if grep -Eq 'changed=[1-9]' drift_ansible.txt; then echo "DÉRIVE détectée (Ansible)"; rc=1; fi

bash scripts/tf_init.sh cml > /dev/null
terraform -chdir="terraform/cml" plan -input=false -detailed-exitcode > drift_tf_cml.txt
code=$?
if [ "$code" -eq 2 ]; then echo "DÉRIVE détectée (Terraform CML)"; rc=1; fi
if [ "$code" -eq 1 ]; then echo "ERREUR Terraform CML"; rc=1; fi

exit $rc