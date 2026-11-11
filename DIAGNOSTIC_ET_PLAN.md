# Diagnostic et plan de correction — LABO NetDevOps

## Corrections effectuées dans cette copie

1. Suppression des métadonnées `.terraform` et des dépôts Git imbriqués de l'archive de livraison. Le cache `.terraform/terraform.tfstate` contenait un backend `http` avec `address = null`, ce qui explique directement `Error: address argument is required` lors d'une initialisation qui réutilise ce cache.
2. Suppression de `terraform.tfvars` de la copie livrée car il contenait un mot de passe en clair. Il faut considérer ce secret comme potentiellement exposé et le changer dans CML2. Un exemple sans secret est fourni.
3. Harmonisation des variables Terraform : `address`, `username`, `password` sont les variables canoniques; `provider.tf` les utilise désormais de manière cohérente. Ajout de `skip_verify`, désactivé par défaut.
4. Réécriture de `scripts/tf_init.sh` : backend local par défaut; génération d'un fichier de backend HTTP éphémère uniquement quand les variables GitLab CI nécessaires sont présentes.
5. Réparation de la structure Ansible : les fichiers de rôles étaient des fichiers ordinaires, pas des rôles Ansible. Ils sont maintenant dans `roles/<nom>/tasks/main.yml`. Les noms de rôles qui avaient des espaces terminaux ont été normalisés.
6. Corrections ciblées du rôle IOS de base (placement de `no_log`) et des interfaces OSPF (les variables étaient des listes utilisées comme nom d'interface).
7. Ajout des règles `.gitignore` et d'une configuration yamllint non vide.

## Vérifications effectuées dans l'environnement d'analyse

- `scripts/check_vars.py` : réussite, 0 erreur de VLAN/chevauchement/séquence ACL.
- Chargement syntaxique YAML des fichiers YAML présents après corrections : aucune erreur de parsing détectée.
- Les binaires `terraform`, `ansible-playbook`, `ansible-lint` et `yamllint` ne sont pas installés dans l'environnement d'analyse; je ne peux donc pas déclarer `terraform init`, `validate`, `plan` ou un déploiement CML réussi.

## Blocages restants empêchant d'affirmer que `terraform plan` est réussi

### 1. `terraform/cml/topology.yaml` est absent de l'archive d'origine

`main.tf` utilise `file("${path.module}/topology.yaml")`, mais aucun `topology.yaml` n'a été fourni. Le plan Terraform ne peut pas être considéré comme opérationnel tant que cette topologie n'est pas ajoutée. Je ne l'ai pas inventée, car les définitions d'images, les interfaces et les connecteurs disponibles doivent correspondre à la version et aux images réellement installées sur le contrôleur CML.

### 2. La topologie réseau et CML Free doivent être conciliées

Le projet suppose trois équipements IOS, un PC, un serveur RPA et une connectivité d'administration/NAT. Il faut vérifier sur la version CML exacte si le connecteur externe est autorisé dans la limite de nœuds de l'édition utilisée. Sans connectivité vers les équipements, Ansible et les tests Netmiko échoueront même si Terraform peut créer le laboratoire.

### 3. AWS n'est pas implémenté dans cette archive

Le script `tf_init.sh` initial prévoyait un répertoire `terraform/aws`, mais celui-ci n'est pas présent. Les ressources AWS décrites dans le projet ne peuvent donc pas être planifiées ou déployées à partir de cette archive.

### 4. La chaîne de sauvegarde n'est pas encore cohérente de bout en bout

Le service `rpa-backup.service` exécute `rsync` sur SRV-RPA vers `/backup/rpa/current` local à SRV-RPA, alors que le test vérifie `/backup/rpa/current` sur le runner CI. Le rôle backup ne configure pas encore le transfert SSH/rsync de SRV-RPA vers l'hôte de sauvegarde. Cette incohérence doit être résolue avant de considérer le test de sauvegarde comme valide.

### 5. Accès SSH et ordre de configuration

L'inventaire utilise l'adresse loopback `10.255.0.2` pour R-CORE. Le playbook commence par configurer le groupe `ios`, avant de garantir que l'adjacence et le routage OSPF rendent cette loopback joignable. Il faut prévoir une adresse de bootstrap accessible ou scinder le bootstrap et la configuration finale.

## Étapes de validation à effectuer sur la machine Linux de l'utilisateur

1. Copier `terraform/cml/terraform.tfvars.example` vers `terraform/cml/terraform.tfvars` si besoin, renseigner l'adresse et l'utilisateur, puis fournir le mot de passe via `export TF_VAR_password='…'`. Ne pas committer ce fichier.
2. Vérifier que la topologie réelle est présente sous `terraform/cml/topology.yaml` et qu'elle utilise des node definitions présentes dans CML. Le job CI de plan échoue maintenant avec un message explicite tant que ce fichier manque.
3. Depuis la racine du dépôt : `bash scripts/tf_init.sh cml`
4. Puis : `terraform -chdir=terraform/cml validate`
5. Puis : `terraform -chdir=terraform/cml plan`
6. Avant `apply`, examiner le plan et vérifier que le contrôleur CML est joignable, que la version CML est compatible avec la version du provider installée et que la limite de nœuds est respectée.

**Important :** l'option `-reconfigure` sélectionne le backend local et ne migre pas automatiquement un état distant. Si le projet a déjà un état GitLab utile, ne bascule pas ce même workspace vers un état local sans sauvegarder et décider explicitement de la stratégie de migration.
