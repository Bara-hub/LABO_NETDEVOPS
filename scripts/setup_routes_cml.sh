#!/usr/bin/env bash
# =============================================================
# setup_routes_cml.sh — Maintien des routes Ubuntu ↔ CML2
# =============================================================
# Utilisation :
#   bash scripts/setup_routes_cml.sh          # ajoute les routes maintenant
#   bash scripts/setup_routes_cml.sh --persist # écrit aussi le netplan
#   bash scripts/setup_routes_cml.sh --check   # vérifie la joignabilité
#
# Architecture :
#   Ubuntu (192.168.110.143/24) ──ens33──► FW-EDGE (192.168.110.30)
#   FW-EDGE route inside : 10.10.0.0/16 et 10.255.0.0/16
# =============================================================
set -euo pipefail

# --- Variables ---
IFACE="ens33"
GW_FW="192.168.110.30"       # FW-EDGE interface outside (gateway des routes lab)
LAB_ROUTES=(
  "10.10.0.0/16"             # Toutes les adresses de transit + LAN du lab
  "10.255.0.0/16"            # Loopbacks OSPF (R-EDGE: .1, R-CORE: .2)
)

# Couleurs
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

check_fw_alive() {
  if ping -c 1 -W 2 "$GW_FW" &>/dev/null; then
    echo -e "${GREEN}✓ FW-EDGE ($GW_FW) répond${NC}"
    return 0
  else
    echo -e "${RED}✗ FW-EDGE ($GW_FW) injoignable — le lab CML2 est-il démarré ?${NC}"
    return 1
  fi
}

add_routes() {
  echo -e "${YELLOW}→ Ajout des routes statiques vers les équipements du lab...${NC}"
  for route in "${LAB_ROUTES[@]}"; do
    if ip route show "$route" | grep -q "$GW_FW"; then
      echo -e "  ${GREEN}✓ Route $route déjà présente${NC}"
    else
      sudo ip route add "$route" via "$GW_FW" dev "$IFACE"
      echo -e "  ${GREEN}✓ Route $route ajoutée via $GW_FW${NC}"
    fi
  done
}

check_all() {
  echo ""
  echo "=== Vérification de joignabilité ==="
  local targets=(
    "192.168.110.30:FW-EDGE outside"
    "10.10.0.9:FW-EDGE inside (via R-EDGE Gi0/0)"
    "10.10.0.1:R-EDGE Gi0/1"
    "10.10.0.2:R-CORE Gi0/0"
    "10.255.0.1:R-EDGE Loopback0"
    "10.255.0.2:R-CORE Loopback0"
    "10.10.10.10:PC-USER"
  )
  for entry in "${targets[@]}"; do
    ip="${entry%%:*}"
    label="${entry##*:}"
    if ping -c 1 -W 2 "$ip" &>/dev/null; then
      echo -e "  ${GREEN}✓ $ip  ($label)${NC}"
    else
      echo -e "  ${RED}✗ $ip  ($label)${NC}"
    fi
  done
}

write_netplan() {
  local NETPLAN_CML="/etc/netplan/50-cloud-init.yaml"
  local NETPLAN_NM="/etc/netplan/01-network-manager-all.yaml"

  echo ""
  echo -e "${YELLOW}→ Écriture de la configuration Netplan persistante...${NC}"

  # Fichier principal : routes CML2 sur ens33
  sudo tee "$NETPLAN_CML" > /dev/null <<'EOF'
# Configuration réseau Ubuntu — LAB NetDevOps
# Les routes vers les équipements CML2 passent par FW-EDGE (192.168.110.30)
# Ce fichier est géré par scripts/setup_routes_cml.sh
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    ens33:
      dhcp4: true
      dhcp4-overrides:
        route-metric: 100
      routes:
        # Réseau de transit + LAN du lab (R-EDGE, R-CORE, PC-USER)
        - to: 10.10.0.0/16
          via: 192.168.110.30
          metric: 200
        # Loopbacks OSPF (10.255.0.1 R-EDGE, 10.255.0.2 R-CORE)
        - to: 10.255.0.0/16
          via: 192.168.110.30
          metric: 200
EOF
  sudo chmod 600 "$NETPLAN_CML"
  echo -e "  ${GREEN}✓ $NETPLAN_CML mis à jour${NC}"

  # Corriger 01-network-manager-all.yaml s'il a le double bloc network: invalide
  if grep -c '^network:' "$NETPLAN_NM" 2>/dev/null | grep -q '^[2-9]'; then
    echo -e "  ${YELLOW}⚠  Double bloc 'network:' détecté dans $NETPLAN_NM — correction...${NC}"
    sudo tee "$NETPLAN_NM" > /dev/null <<'EOF'
# Let NetworkManager manage all devices on this system
network:
  version: 2
  renderer: NetworkManager
EOF
    sudo chmod 600 "$NETPLAN_NM"
    echo -e "  ${GREEN}✓ $NETPLAN_NM corrigé (un seul bloc network:)${NC}"
  fi

  # Netplan generate pour valider avant d'appliquer
  echo ""
  echo -e "${YELLOW}→ Validation Netplan (netplan generate)...${NC}"
  if ! sudo netplan generate 2>&1 | grep -v "WARNING.*too open"; then
    echo -e "  ${RED}✗ Erreur de configuration Netplan — apply annulé${NC}"
    return 1
  fi
  echo -e "  ${GREEN}✓ Configuration valide${NC}"

  echo ""
  echo -e "${YELLOW}→ Application Netplan (sudo netplan apply)...${NC}"
  echo -e "  ℹ  L'interface va se reconfigurer brièvement (DHCP ~3s)..."
  sudo netplan apply
  echo -e "  ${YELLOW}→ Attente de la stabilisation réseau (5s)...${NC}"
  sleep 5

  # Supprimer les routes dupliquées metric 100 si elles coexistent
  for route in "${LAB_ROUTES[@]}"; do
    while ip route show "$route" metric 100 2>/dev/null | grep -q "$GW_FW"; do
      sudo ip route del "$route" via "$GW_FW" metric 100 2>/dev/null || break
      echo -e "  ${GREEN}✓ Route dupliquée $route metric 100 supprimée${NC}"
    done
  done

  echo -e "  ${GREEN}✓ Configuration appliquée et routes stabilisées${NC}"
}

# --- Main ---
MODE="${1:-}"

echo "=== Routes Ubuntu ↔ CML2 (FW-EDGE gateway: $GW_FW) ==="
echo ""

case "$MODE" in
  --check)
    check_all
    ;;
  --persist)
    write_netplan
    check_all
    ;;
  *)
    # Par défaut : vérifier que FW-EDGE répond, puis ajouter les routes
    check_fw_alive || {
      echo ""
      echo -e "${YELLOW}⚠️  Démarrez le lab CML2 avant d'exécuter ce script.${NC}"
      echo "    Les routes sont ajoutées au kernel mais seront inutilisables"
      echo "    tant que FW-EDGE n'aura pas répondu à l'ARP."
      echo ""
    }
    add_routes
    echo ""
    echo "Routes actuelles vers le lab :"
    ip route show | grep -E '(10\.10\.|10\.255\.)' | sed 's/^/  /'
    echo ""
    echo "Conseil : lancez '--persist' pour rendre les routes permanentes via Netplan."
    echo "Conseil : lancez '--check' pour tester la joignabilité de chaque équipement."
    ;;
esac

